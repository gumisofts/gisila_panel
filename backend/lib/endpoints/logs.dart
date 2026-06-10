import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/jwt.dart';
import 'package:redis/redis.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:gisila_panel/config.dart';

/// Hand-rolled (non-codegen) router for the live-log WebSockets. We don't go
/// through the generator because `gisila_doc`'s `@Controller` annotations
/// don't yet model upgrading to WebSocket.
///
/// The router is mounted at `/ws`, so shelf strips that prefix before routing.
/// Routes below are therefore registered *without* the `/ws` prefix.
///
/// Routes (as seen by the client):
///   GET /ws/apps/{id}/logs                          → live runtime logs
///   GET /ws/apps/{id}/build-logs/{deploymentId}     → live build logs
///   GET /ws/services/{id}/logs                      → live service install logs
///
/// Authentication: the client sends a single JSON text frame immediately after
/// the socket opens carrying the JWT and the relevant ids, e.g.
///   { "token": "<jwt>", "appId": 1 }
///   { "token": "<jwt>", "appId": 1, "deploymentId": 7 }
///   { "token": "<jwt>", "serviceId": 3 }
Router logsRouter({required Database database}) {
  final router = Router();

  router.get('/apps/<id|[0-9]+>/logs', _logSocket(database));
  router.get(
    '/apps/<id|[0-9]+>/build-logs/<deploymentId|[0-9]+>',
    _buildLogSocket(database),
  );
  router.get('/apps/<id|[0-9]+>/exec/<execId>', _execLogSocket(database));
  router.get('/services/<id|[0-9]+>/logs', _serviceLogSocket(database));

  return router;
}

/// Live command-execution logs — replays the buffered history then tails the
/// channel the exec worker publishes to.
Handler _execLogSocket(Database database) => webSocketHandler((webSocket) async {
      await _authThen(webSocket, database: database,
          handler: (auth, closed) async {
        final execId = auth.execId;
        if (execId == null) {
          _sendError(webSocket, 'exec_required');
          return;
        }
        await _bridgeRedis(
          webSocket,
          channel: 'gisila:logs:exec:$execId',
          historyKey: 'gisila:logs:exec:$execId:history',
          closed: closed,
        );
      });
    });

/// Live runtime logs — tails the app's systemd journal through the agent.
Handler _logSocket(Database database) => webSocketHandler((webSocket) async {
      await _authThen(webSocket, database: database,
          handler: (auth, closed) async {
        if (auth.app == null) {
          _sendError(webSocket, 'app_not_found');
          return;
        }
        await _streamRuntimeLogs(webSocket, app: auth.app!, closed: closed);
      });
    });

/// Live build logs — bridges the Redis pub/sub channel the worker publishes to.
Handler _buildLogSocket(Database database) =>
    webSocketHandler((webSocket) async {
      await _authThen(webSocket, database: database,
          handler: (auth, closed) async {
        final deploymentId = auth.deploymentId;
        if (deploymentId == null) {
          _sendError(webSocket, 'deployment_required');
          return;
        }
        await _bridgeRedis(
          webSocket,
          channel: 'gisila:logs:build:$deploymentId',
          closed: closed,
        );
      });
    });

/// Live service install logs — replays the recent history list then subscribes
/// to the live channel the service worker publishes to.
Handler _serviceLogSocket(Database database) =>
    webSocketHandler((webSocket) async {
      await _authThen(
        webSocket,
        database: database,
        requireApp: false,
        handler: (auth, closed) async {
          final serviceId = auth.serviceId;
          if (serviceId == null) {
            _sendError(webSocket, 'service_required');
            return;
          }
          await _bridgeRedis(
            webSocket,
            channel: 'gisila:logs:service:$serviceId',
            historyKey: 'gisila:logs:service:$serviceId:history',
            closed: closed,
          );
        },
      );
    });

// ── Auth handshake ───────────────────────────────────────────────────────────

class _Auth {
  _Auth({this.app, this.deploymentId, this.serviceId, this.execId});
  final App? app;
  final int? deploymentId;
  final int? serviceId;
  final String? execId;
}

/// Drives the whole socket lifecycle with a **single** subscription (the
/// WebSocket stream is single-subscription, so we must never re-listen).
///
/// The first frame carries the JWT + ids. Once validated, [handler] runs and is
/// handed a `closed` future that resolves when the client disconnects, so it
/// can tear down any tail process / Redis subscription without listening to the
/// socket itself.
Future<void> _authThen(
  dynamic webSocket, {
  required Database database,
  required Future<void> Function(_Auth auth, Future<void> closed) handler,
  bool requireApp = true,
}) async {
  final closed = Completer<void>();
  var handled = false;
  Future<void>? handlerFuture;

  final sub = webSocket.stream.listen(
    (Object? raw) async {
      if (handled) return; // ignore any further frames
      handled = true;
      try {
        final auth =
            await _authenticate(webSocket, database, raw, requireApp);
        if (auth == null) return; // error already sent + socket closed
        handlerFuture = handler(auth, closed.future);
        await handlerFuture;
      } catch (e) {
        _sendError(webSocket, e.toString());
        try {
          await webSocket.sink.close();
        } catch (_) {}
      }
    },
    onError: (Object _) {
      if (!closed.isCompleted) closed.complete();
    },
    onDone: () {
      if (!closed.isCompleted) closed.complete();
    },
    cancelOnError: false,
  );

  await closed.future;
  // Let the handler finish its cleanup before we drop the subscription.
  if (handlerFuture != null) {
    try {
      await handlerFuture;
    } catch (_) {}
  }
  await sub.cancel();
}

/// Validate the first frame. Returns the resolved [_Auth], or null after having
/// sent an error frame and closed the socket.
Future<_Auth?> _authenticate(
  dynamic webSocket,
  Database database,
  Object? raw,
  bool requireApp,
) async {
  final msg = jsonDecode(raw as String) as Map<String, Object?>;
  final token = msg['token'] as String?;
  final appId = msg['appId'] as int?;
  final deploymentId = msg['deploymentId'] as int?;
  final serviceId = msg['serviceId'] as int?;
  final execId = msg['execId'] as String?;

  Future<_Auth?> fail(String error) async {
    _sendError(webSocket, error);
    try {
      await webSocket.sink.close();
    } catch (_) {}
    return null;
  }

  if (token == null) return fail('auth_required');
  final payload = JWTAuth.decodeAndVerify(token);
  final userId = payload?['id'] as int?;
  if (userId == null) return fail('invalid_token');

  final user = await Query<User>(UserTable.metadata)
      .where(UserTable.id.eq(userId))
      .first(database.context());
  if (user == null) return fail('invalid_user');

  App? app;
  if (requireApp) {
    if (appId == null) return fail('auth_required');
    app = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(appId))
        .first(database.context());
    if (app == null) return fail('app_not_found');
  }

  return _Auth(
    app: app,
    deploymentId: deploymentId,
    serviceId: serviceId,
    execId: execId,
  );
}

void _sendError(dynamic webSocket, String error) {
  try {
    webSocket.sink.add(jsonEncode({'error': error}));
  } catch (_) {/* socket already gone */}
}

void _sendLine(dynamic webSocket, String stream, String line) {
  try {
    webSocket.sink.add(jsonEncode({
      'message': jsonEncode({'stream': stream, 'line': line}),
      'ts': DateTime.now().toUtc().toIso8601String(),
    }));
  } catch (_) {/* socket already gone */}
}

// ── Runtime logs (journalctl via agent) ──────────────────────────────────────

Future<void> _streamRuntimeLogs(
  dynamic webSocket, {
  required App app,
  required Future<void> closed,
}) async {
  final user = app.linuxUser;
  if (user == null) {
    _sendLine(webSocket, 'system',
        'App has not been provisioned yet — deploy it to start the service.');
    await webSocket.sink.close();
    return;
  }

  if (hostConfig.agentMode == 'dev') {
    _sendLine(webSocket, 'system',
        'Runtime log streaming is disabled in dev mode (no journald).');
    await closed; // hold the socket open until the client disconnects
    return;
  }

  // Never use sudo here: the API runs as the unprivileged `gisila` user with
  // NoNewPrivileges=true and can't escalate. The agent reads journald directly
  // via the systemd-journal group instead.
  final cmd = buildAgentCmdNoSudo([
    'logs',
    '--user',
    user,
    '--work-dir',
    app.workDir,
    '--runtime',
    app.runtime ?? '',
    '--lines',
    '300',
    '--follow',
  ]);

  Process process;
  try {
    process = await Process.start(cmd.first, cmd.skip(1).toList());
  } catch (e) {
    _sendLine(webSocket, 'system', 'Failed to start log stream: $e');
    await webSocket.sink.close();
    return;
  }

  final stdoutSub = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => _sendLine(webSocket, 'stdout', line));
  final stderrSub = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => _sendLine(webSocket, 'stderr', line));

  // Stop as soon as either the client disconnects or the tail process exits.
  await Future.any([closed, process.exitCode]);
  process.kill(ProcessSignal.sigterm);
  await stdoutSub.cancel();
  await stderrSub.cancel();
  try {
    await webSocket.sink.close();
  } catch (_) {}
}

// ── Redis bridge (build + service logs) ──────────────────────────────────────

Future<void> _bridgeRedis(
  dynamic webSocket, {
  required String channel,
  required Future<void> closed,
  String? historyKey,
}) async {
  final host = env.getOrElse('REDIS_HOST', () => 'localhost');
  final port = int.parse(env.getOrElse('REDIS_PORT', () => '6380'));

  // Replay buffered history (if any) on a dedicated short-lived connection so
  // reconnecting clients see prior lines before live tailing begins.
  if (historyKey != null) {
    try {
      final histConn = await RedisConnection().connect(host, port);
      final raw = await histConn.send_object(['LRANGE', historyKey, '0', '-1']);
      if (raw is List) {
        for (final entry in raw) {
          webSocket.sink.add(jsonEncode({
            'message': entry.toString(),
            'ts': DateTime.now().toUtc().toIso8601String(),
          }));
        }
      }
      await histConn.get_connection().close();
    } catch (_) {/* history is best-effort */}
  }

  final cmd = await RedisConnection().connect(host, port);
  final ps = PubSub(cmd);
  ps.subscribe([channel]);
  final redisSub = ps.getStream().listen(
    (event) {
      if (event is List && event.length >= 3 && event[0] == 'message') {
        webSocket.sink.add(jsonEncode({
          'channel': event[1],
          'message': event[2],
          'ts': DateTime.now().toUtc().toIso8601String(),
        }));
      }
    },
    onError: (Object _) {},
  );

  // Hold until the client disconnects, then tear down the Redis connection.
  await closed;
  await redisSub.cancel();
  try {
    await cmd.get_connection().close();
  } catch (_) {}
}
