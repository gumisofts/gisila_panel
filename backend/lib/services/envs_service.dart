import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';

class EnvsService extends Service {
  Database get _db => db<Database>();

  Future<List<EnvVar>> list(User actor, int appId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.findForUser(actor, appId);
    return Query<EnvVar>(EnvVarTable.metadata)
        .where(EnvVarTable.appId.eq(app.id!))
        .all(_db.context());
  }

  Future<EnvVar> upsert(
    User actor,
    int appId, {
    required String name,
    String? value,
    bool isSecret = false,
  }) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.requireAppRole(actor, appId, TeamRole.developer);

    final existing = await Query<EnvVar>(EnvVarTable.metadata)
        .where(EnvVarTable.appId.eq(app.id!))
        .where(EnvVarTable.name.eq(name))
        .first(_db.context());

    final now = DateTime.now().toUtc().toIso8601String();
    if (existing == null) {
      return Query<EnvVar>(EnvVarTable.metadata).insert(<String, Object?>{
        'appId': app.id,
        'name': name,
        'value': value,
        'isSecret': isSecret,
        'updatedAt': now,
      }).one(_db.context());
    }
    final rows = await Query<EnvVar>(EnvVarTable.metadata)
        .where(EnvVarTable.id.eq(existing.id!))
        .update(<String, Object?>{
      'value': value,
      'isSecret': isSecret,
      'updatedAt': now,
    }).run(_db.context());
    return rows.first;
  }

  Future<void> bulkUpsert(
    User actor,
    int appId,
    Map<String, Object?> entries,
  ) async {
    for (final entry in entries.entries) {
      await upsert(actor, appId,
          name: entry.key, value: entry.value?.toString());
    }
  }

  Future<void> delete(User actor, int appId, int envId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.requireAppRole(actor, appId, TeamRole.developer);
    await Query<EnvVar>(EnvVarTable.metadata)
        .where(EnvVarTable.id.eq(envId))
        .where(EnvVarTable.appId.eq(app.id!))
        .delete()
        .run(_db.context());
  }
}
