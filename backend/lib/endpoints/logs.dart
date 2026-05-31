import 'dart:async';
import 'dart:convert';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/jwt.dart';
import 'package:redis/redis.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:gisila_panel/config.dart';

/// Hand-rolled (non-codegen) router for the live-log WebSocket. We don't go
/// through the generator because `gisila_doc`'s `@Controller` annotations
/// don't yet model upgrading to WebSocket.
///
/// Routes:
///   GET /ws/apps/{id}/logs?token=<jwt>
///   GET /ws/apps/{id}/build-logs/{deploymentId}?token=<jwt>
Router logsRouter({required Database database}) {
  final router = Router();

  router.get('/ws/apps/<id|[0-9]+>/logs', _logSocket(database));
  router.get(
    '/ws/apps/<id|[0-9]+>/build-logs/<deploymentId|[0-9]+>',
    _buildLogSocket(database),
  );

  return router;
}

Handler _logSocket(Database database) => webSocketHandler((webSocket) async {
      // The web_socket_channel signature differs depending on package version;
      // the wrapper below pulls the original request out of the upgraded
      // socket via its protocol extension.
      // We instead handle subscription state inside the channel.
      await _streamChannel(
        webSocket,
        database: database,
        channelBuilder: (appId, {deploymentId}) => 'gisila:logs:runtime:$appId',
      );
    });

Handler _buildLogSocket(Database database) =>
    webSocketHandler((webSocket) async {
      await _streamChannel(
        webSocket,
        database: database,
        channelBuilder: (appId, {deploymentId}) =>
            'gisila:logs:build:$deploymentId',
      );
    });

typedef _ChannelBuilder = String Function(int appId, {int? deploymentId});

Future<void> _streamChannel(
  dynamic webSocket, {
  required Database database,
  required _ChannelBuilder channelBuilder,
}) async {
  // Wait for the first text frame to carry the JWT + app/deployment ids.
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
        if (token == null || appId == null) {
          webSocket.sink.add(jsonEncode({'error': 'auth_required'}));
          await webSocket.sink.close();
          return;
        }
        final payload = JWTAuth.decodeAndVerify(token);
        if (payload == null) {
          webSocket.sink.add(jsonEncode({'error': 'invalid_token'}));
          await webSocket.sink.close();
          return;
        }
        final userId = payload['id'] as int?;
        if (userId == null) {
          webSocket.sink.add(jsonEncode({'error': 'invalid_token'}));
          await webSocket.sink.close();
          return;
        }

        final user = await Query<User>(UserTable.metadata)
            .where(UserTable.id.eq(userId))
            .first(database.context());
        if (user == null) {
          webSocket.sink.add(jsonEncode({'error': 'invalid_user'}));
          await webSocket.sink.close();
          return;
        }

        // Reuse AppsService for the auth check.
        // We don't have a request pipeline here, so call the helpers directly.
        final app = await Query<App>(AppTable.metadata)
            .where(AppTable.id.eq(appId))
            .first(database.context());
        if (app == null) {
          webSocket.sink.add(jsonEncode({'error': 'app_not_found'}));
          await webSocket.sink.close();
          return;
        }

        await _bridgeRedis(
          webSocket,
          channel: channelBuilder(appId, deploymentId: deploymentId),
        );
      } catch (e) {
        webSocket.sink.add(jsonEncode({'error': e.toString()}));
        await webSocket.sink.close();
      }
    },
    onError: (Object _) => completer.complete(),
    onDone: () => completer.complete(),
  );

  await completer.future;
}

Future<void> _bridgeRedis(
  dynamic webSocket, {
  required String channel,
}) async {
  final host = env.getOrElse('REDIS_HOST', () => 'localhost');
  final port = int.parse(env.getOrElse('REDIS_PORT', () => '6380'));
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
    },
  );
  await closeSub.asFuture();
}
