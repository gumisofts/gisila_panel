import 'dart:convert';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';

/// Sends start / stop / restart commands to the worker, which forwards
/// them to the privileged `gisila-agent`.
class LifecycleService extends Service {
  Database get _db => db<Database>();

  Future<void> _enqueueLifecycle(int appId, String action) =>
      RedisClient.instance.rpush(
        'gisila:queue:lifecycle',
        jsonEncode(<String, Object?>{
          'appId': appId,
          'action': action,
          'requestedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );

  Future<void> start(User actor, int appId) async {
    final app = await _resolveApp(actor, appId);
    await _enqueueLifecycle(app.id!, 'start');
    await _markEvent(app, actor, 'restart', 'Start requested.');
  }

  Future<void> stop(User actor, int appId) async {
    final app = await _resolveApp(actor, appId);
    await _enqueueLifecycle(app.id!, 'stop');
    await _markEvent(app, actor, 'stop', 'Stop requested.');
  }

  Future<void> restart(User actor, int appId) async {
    final app = await _resolveApp(actor, appId);
    await _enqueueLifecycle(app.id!, 'restart');
    await _markEvent(app, actor, 'restart', 'Restart requested.');
  }

  Future<App> _resolveApp(User actor, int appId) async {
    final appsSvc = AppsService()..attach(ctx);
    return appsSvc.findForUser(actor, appId);
  }

  Future<void> _markEvent(App app, User actor, String kind, String msg) async {
    await Query<AppEvent>(AppEventTable.metadata).insert(<String, Object?>{
      'appId': app.id,
      'actorId': actor.id,
      'kind': kind,
      'message': msg,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).run(_db.context());
  }
}
