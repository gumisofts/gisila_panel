import 'dart:convert';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/application_catalog.dart';

/// CRUD + lifecycle for [Application] rows — the panel-side half of
/// Application Management. Mirrors [ManagedServiceService] deliberately:
/// Applications are installed/updated/removed independently of the panel
/// itself, on the same install → enqueue → agent pattern.
class ApplicationService extends Service {
  Database get _db => db<Database>();

  // ── Catalog ──────────────────────────────────────────────────────────────

  List<Map<String, Object?>> listCatalog() =>
      kApplicationCatalog.map((d) => d.toJson()).toList();

  // ── CRUD ─────────────────────────────────────────────────────────────────

  Future<List<Application>> listInstalled() =>
      Query<Application>(ApplicationTable.metadata)
          .orderBy(ApplicationTable.createdAt, desc: true)
          .all(_db.context());

  Future<Application> findById(int id) async {
    final app = await Query<Application>(ApplicationTable.metadata)
        .where(ApplicationTable.id.eq(id))
        .first(_db.context());
    if (app == null) throw NotFound('Application #$id not found.');
    return app;
  }

  Future<Application?> findByKey(String key) =>
      Query<Application>(ApplicationTable.metadata)
          .where(ApplicationTable.key.eq(key))
          .first(_db.context());

  Future<Application> install({
    required String key,
    String? version,
  }) async {
    final def = findApplicationDef(key);
    if (def == null) {
      throw HttpException(422, 'Unknown Application key: $key');
    }

    final existing = await findByKey(key);
    if (existing != null && existing.status != 'failed') {
      throw HttpException(409, 'Application "$key" is already installed.');
    }

    final now = DateTime.now().toUtc();
    final Application app;
    if (existing != null) {
      await _patch(existing.id!, {'status': 'installing', 'errorMessage': null});
      app = await findById(existing.id!);
    } else {
      app = await Query<Application>(ApplicationTable.metadata)
          .insert(<String, Object?>{
        'key': def.key,
        'displayName': def.displayName,
        'deployModes': DeployMode.toCsv(def.deployModes),
        'defaultDeployMode': def.defaultDeployMode.value,
        'defaultVersion': version ?? def.defaultVersion,
        'defaultBuildCommand': def.defaultBuildCommand,
        'defaultStartCommand': def.defaultStartCommand,
        'status': 'installing',
        'isBuiltin': true,
        'createdAt': now.toIso8601String(),
      }).one(_db.context());
    }

    await _enqueue('install', app.id!, version: version ?? app.defaultVersion);
    return findById(app.id!);
  }

  Future<Application> update(
    int id, {
    String? defaultVersion,
    String? defaultDeployMode,
    String? defaultBuildCommand,
    String? defaultStartCommand,
  }) async {
    final app = await findById(id);
    final def = findApplicationDef(app.key ?? '');
    if (defaultDeployMode != null &&
        def != null &&
        !def.deployModes.map((m) => m.value).contains(defaultDeployMode)) {
      throw HttpException(422,
          'Application "${app.key}" does not support deploy mode $defaultDeployMode.');
    }

    final versionChanged =
        defaultVersion != null && defaultVersion != app.defaultVersion;

    await _patch(id, {
      if (defaultVersion != null) 'defaultVersion': defaultVersion,
      if (defaultDeployMode != null) 'defaultDeployMode': defaultDeployMode,
      if (defaultBuildCommand != null) 'defaultBuildCommand': defaultBuildCommand,
      if (defaultStartCommand != null) 'defaultStartCommand': defaultStartCommand,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    if (versionChanged) {
      await _patch(id, {'status': 'updating'});
      await _enqueue('install', id, version: defaultVersion);
    }

    return findById(id);
  }

  /// Remove an installed Application. Refuses while any [App] still
  /// references it — same guard style used elsewhere (e.g. deleting a
  /// [StorageProvider] with linked buckets).
  Future<void> remove(int id) async {
    final app = await findById(id);
    final inUse = await Query<App>(AppTable.metadata)
        .where(AppTable.applicationId.eq(id))
        .count(_db.context());
    if (inUse > 0) {
      throw HttpException(409,
          '${app.displayName} is used by $inUse app(s) — reassign or delete '
          'them before removing this Application.');
    }
    await _patch(id, {'status': 'removing'});
    await _enqueue('remove', id, version: app.defaultVersion);
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _patch(int id, Map<String, Object?> data) =>
      Query<Application>(ApplicationTable.metadata)
          .where(ApplicationTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _enqueue(String action, int applicationId, {String? version}) =>
      RedisClient.instance.rpush(
        'gisila:queue:applications',
        jsonEncode({
          'action': action,
          'applicationId': applicationId,
          if (version != null) 'version': version,
        }),
      );
}
