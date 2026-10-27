import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';
import 'package:gisila_panel/infra/secret_box.dart';

class EnvsService extends Service {
  Database get _db => db<Database>();

  Future<List<EnvVar>> list(User actor, int appId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.findForUser(actor, appId);
    final rows = await Query<EnvVar>(EnvVarTable.metadata)
        .where(EnvVarTable.appId.eq(app.id!))
        .orderBy(EnvVarTable.name)
        .all(_db.context());
    return [for (final e in rows) e.opened()];
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
    final sealed = SecretBox.instance.sealOrNull(value, SecretBox.envVarValue);
    if (existing == null) {
      final row = await Query<EnvVar>(EnvVarTable.metadata)
          .insert(<String, Object?>{
        'appId': app.id,
        'name': name,
        'value': sealed,
        'isSecret': isSecret,
        'updatedAt': now,
      }).one(_db.context());
      return row.opened();
    }
    final rows = await Query<EnvVar>(EnvVarTable.metadata)
        .where(EnvVarTable.id.eq(existing.id!))
        .update(<String, Object?>{
      // An omitted value keeps the stored one: secrets are never sent to
      // clients, so an edit that only flips `isSecret` has no value to send.
      if (value != null) 'value': sealed,
      'isSecret': isSecret,
      'updatedAt': now,
    }).run(_db.context());
    return rows.first.opened();
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
