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
  router.get('/services/<id|[0-9]+>/logs', _serviceLogSocket(database));

  return router;
}

/// Live runtime logs — tails the app's systemd journal through the agent.
Handler _logSocket(Database database) => webSocketHandler((webSocket) async {
      await _authThen(webSocket, database: database, handler: (auth) async {
        if (auth.app == null) {
          _sendError(webSocket, 'app_not_found');
          return;
        }
        await _streamRuntimeLogs(webSocket, app: auth.app!);
      });
    });

/// Live build logs — bridges the Redis pub/sub channel the worker publishes to.
Handler _buildLogSocket(Database database) =>
    webSocketHandler((webSocket) async {
      await _authThen(webSocket, database: database, handler: (auth) async {
        final deploymentId = auth.deploymentId;
        if (deploymentId == null) {
          _sendError(webSocket, 'deployment_required');
          return;
        }
        await _bridgeRedis(
          webSocket,
          channel: 'gisila:logs:build:$deploymentId',
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
        handler: (auth) async {
          final serviceId = auth.serviceId;
          if (serviceId == null) {
            _sendError(webSocket, 'service_required');
            return;
          }
          await _bridgeRedis(
            webSocket,
            channel: 'gisila:logs:service:$serviceId',
            historyKey: 'gisila:logs:service:$serviceId:history',
          );
        },
      );
    });

// ── Auth handshake ───────────────────────────────────────────────────────────

class _Auth {
  _Auth({this.app, this.deploymentId, this.serviceId});
  final App? app;
  final int? deploymentId;
  final int? serviceId;
}

/// Waits for the first frame, validates the JWT and (optionally) loads the App,
/// then invokes [handler]. Closes the socket on any auth failure.
Future<void> _authThen(
  dynamic webSocket, {
  required Database database,
  required Future<void> Function(_Auth auth) handler,
  bool requireApp = true,
}) async {
  late StreamSubscription sub;
  final completer = Completer<void>();

  sub = webSocket.stream.listen(
    (Object? raw) async {
      if (completer.isCompleted) return;
      completer.complete();
      await sub.cancel();
      try {
        final msg = jsonDecode(raw as String) as Map<String, Object?>;
        final token = msg['token'] as String?;
        final appId = msg['appId'] as int?;
        final deploymentId = msg['deploymentId'] as int?;
        final serviceId = msg['serviceId'] as int?;

        if (token == null) {
          _sendError(webSocket, 'auth_required');
          await webSocket.sink.close();
          return;
        }
        final payload = JWTAuth.decodeAndVerify(token);
        final userId = payload?['id'] as int?;
        if (userId == null) {
          _sendError(webSocket, 'invalid_token');
          await webSocket.sink.close();
          return;
        }
        final user = await Query<User>(UserTable.metadata)
            .where(UserTable.id.eq(userId))
            .first(database.context());
        if (user == null) {
          _sendError(webSocket, 'invalid_user');
          await webSocket.sink.close();
          return;
        }

        App? app;
        if (requireApp) {
          if (appId == null) {
            _sendError(webSocket, 'auth_required');
            await webSocket.sink.close();
            return;
          }
          app = await Query<App>(AppTable.metadata)
              .where(AppTable.id.eq(appId))
              .first(database.context());
          if (app == null) {
            _sendError(webSocket, 'app_not_found');
            await webSocket.sink.close();
            return;
          }
        }

        await handler(_Auth(
          app: app,
          deploymentId: deploymentId,
          serviceId: serviceId,
        ));
      } catch (e) {
        _sendError(webSocket, e.toString());
        await webSocket.sink.close();
      }
    },
    onError: (Object _) => completer.complete(),
    onDone: () => completer.complete(),
  );

  await completer.future;
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

Future<void> _streamRuntimeLogs(dynamic webSocket, {required App app}) async {
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
    // Keep the socket open until the client disconnects.
    await webSocket.stream.drain<void>().catchError((_) {});
    return;
  }

  final args = [
    'logs',
    '--user',
    user,
    '--work-dir',
    app.workDir,
    '--lines',
    '300',
    '--follow',
  ];
  final List<String> cmd;
  if (hostConfig.agentBin == 'dart') {
    cmd = ['dart', 'run', hostConfig.agentDartEntry, ...args];
  } else if (hostConfig.agentMode == 'sudo') {
    cmd = ['sudo', '--non-interactive', hostConfig.agentBin, ...args];
  } else {
    cmd = [hostConfig.agentBin, ...args];
  }

  Process? process;
  try {
    process = await Process.start(cmd.first, cmd.skip(1).toList());
  } catch (e) {
    _sendLine(webSocket, 'system', 'Failed to start log stream: $e');
    await webSocket.sink.close();
    return;
  }

  final proc = process;
  final stdoutSub = proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => _sendLine(webSocket, 'stdout', line));
  final stderrSub = proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => _sendLine(webSocket, 'stderr', line));

  // Kill the journalctl process as soon as the client disconnects.
  final closeSub = webSocket.stream.listen((_) {}, onDone: () {
    proc.kill(ProcessSignal.sigterm);
  });

  await proc.exitCode;
  await stdoutSub.cancel();
  await stderrSub.cancel();
  await closeSub.cancel();
  try {
    await webSocket.sink.close();
  } catch (_) {}
}

// ── Redis bridge (build + service logs) ──────────────────────────────────────

Future<void> _bridgeRedis(
  dynamic webSocket, {
  required String channel,
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
  late StreamSubscription redisSub;
  redisSub = ps.getStream().listen(
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

  final closeSub = webSocket.stream.listen(
    (_) {},
    onDone: () async {
      await redisSub.cancel();
      try {
        await cmd.get_connection().close();
      } catch (_) {}
    },
  );
  await closeSub.asFuture();
}
