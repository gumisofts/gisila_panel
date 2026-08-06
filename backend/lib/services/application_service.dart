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
///
/// An Application is a runtime *family* (Python, Node, …). For families the
/// catalog marks [ApplicationDef.versioned], each installed toolchain version
/// is an [ApplicationVersion] child row, so several can live on the host at
/// once — the panel side of what pyenv/fnm/rustup already do on disk.
/// Unversioned families (static, binary, zig, celery) have no child rows and
/// are tracked by the [Application] row alone.
class ApplicationService extends Service {
  Database get _db => db<Database>();

  /// Apps pin their runtime version in a per-runtime column. Used to refuse
  /// removing a version that something still deploys against.
  static const Map<String, ColumnRef<String?>> _appVersionColumn = {
    'python': AppTable.pythonVersion,
    // Celery apps are Python apps — they pin the same column.
    'celery': AppTable.pythonVersion,
    'node': AppTable.nodeVersion,
    'dart': AppTable.dartVersion,
    'go': AppTable.goVersion,
    'rust': AppTable.rustVersion,
    'bun': AppTable.bunVersion,
  };

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

  // ── Versions ──────────────────────────────────────────────────────────────

  Future<List<ApplicationVersion>> listVersions(int applicationId) =>
      Query<ApplicationVersion>(ApplicationVersionTable.metadata)
          .where(ApplicationVersionTable.applicationId.eq(applicationId))
          .orderBy(ApplicationVersionTable.createdAt)
          .all(_db.context());

  /// All versions for every Application, keyed by application id — so the
  /// list endpoint can include them without one query per row.
  Future<Map<int, List<ApplicationVersion>>> versionsByApplication() async {
    final rows = await Query<ApplicationVersion>(
      ApplicationVersionTable.metadata,
    ).orderBy(ApplicationVersionTable.createdAt).all(_db.context());

    final grouped = <int, List<ApplicationVersion>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.applicationId, () => []).add(row);
    }
    return grouped;
  }

  Future<ApplicationVersion> findVersion(int applicationId, int versionId) async {
    final row = await Query<ApplicationVersion>(
      ApplicationVersionTable.metadata,
    )
        .where(ApplicationVersionTable.id.eq(versionId))
        .where(ApplicationVersionTable.applicationId.eq(applicationId))
        .first(_db.context());
    if (row == null) {
      throw NotFound('Version #$versionId not found for Application '
          '#$applicationId.');
    }
    return row;
  }

  Future<ApplicationVersion?> _findVersionByName(
    int applicationId,
    String version,
  ) =>
      Query<ApplicationVersion>(ApplicationVersionTable.metadata)
          .where(ApplicationVersionTable.applicationId.eq(applicationId))
          .where(ApplicationVersionTable.version.eq(version))
          .first(_db.context());

  // ── Install ───────────────────────────────────────────────────────────────

  /// Install an Application, or an additional version of one already
  /// installed. Unlike the single-version predecessor this no longer refuses
  /// when the family exists — for versioned families that is the whole point.
  Future<Application> install({
    required String key,
    String? version,
  }) async {
    final def = findApplicationDef(key);
    if (def == null) {
      throw HttpException(422, 'Unknown Application key: $key');
    }

    final existing = await findByKey(key);

    if (!def.versioned) {
      if (existing != null && existing.status != 'failed') {
        throw HttpException(409, 'Application "$key" is already installed.');
      }
      final app = existing ?? await _createFamily(def, null);
      if (existing != null) {
        await _patch(app.id!, {'status': 'installing', 'errorMessage': null});
      }
      await _enqueue('install', app.id!);
      return findById(app.id!);
    }

    final resolved = (version?.trim().isNotEmpty ?? false)
        ? version!.trim()
        : def.defaultVersion;
    if (resolved == null || resolved.isEmpty) {
      throw HttpException(
        422,
        '${def.displayName} needs a version — pick one of: '
        '${def.availableVersions.take(5).join(', ')}…',
      );
    }

    final app = existing ?? await _createFamily(def, resolved);
    await _installVersionRow(app, resolved);
    return findById(app.id!);
  }

  /// Install another version of an already-installed Application.
  Future<ApplicationVersion> installVersion(
    int applicationId,
    String version,
  ) async {
    final app = await findById(applicationId);
    final def = findApplicationDef(app.key ?? '');
    if (def != null && !def.versioned) {
      throw HttpException(
        422,
        '${app.displayName} does not support multiple versions.',
      );
    }
    final trimmed = version.trim();
    if (trimmed.isEmpty) throw HttpException(422, 'A version is required.');

    await _installVersionRow(app, trimmed);
    return (await _findVersionByName(applicationId, trimmed))!;
  }

  /// Create (or retry) the child row for [version] and queue the agent job.
  Future<void> _installVersionRow(Application app, String version) async {
    final existing = await _findVersionByName(app.id!, version);
    if (existing != null && existing.status != 'failed') {
      throw HttpException(
        409,
        '${app.displayName} $version is already installed.',
      );
    }

    final now = DateTime.now().toUtc();
    final int versionId;
    if (existing != null) {
      versionId = existing.id!;
      await _patchVersion(versionId, {
        'status': 'installing',
        'errorMessage': null,
        'updatedAt': now.toIso8601String(),
      });
    } else {
      // The first version installed becomes the default for new apps.
      final siblings = await listVersions(app.id!);
      final row = await Query<ApplicationVersion>(
        ApplicationVersionTable.metadata,
      ).insert(<String, Object?>{
        'applicationId': app.id,
        'version': version,
        'status': 'installing',
        'isDefault': siblings.isEmpty,
        'createdAt': now.toIso8601String(),
      }).one(_db.context());
      versionId = row.id!;
      if (siblings.isEmpty) {
        await _patch(app.id!, {'defaultVersion': version});
      }
    }

    await _patch(app.id!, {'status': 'installing', 'errorMessage': null});
    await _enqueue(
      'install',
      app.id!,
      version: version,
      applicationVersionId: versionId,
    );
  }

  Future<Application> _createFamily(ApplicationDef def, String? version) =>
      Query<Application>(ApplicationTable.metadata).insert(<String, Object?>{
        'key': def.key,
        'displayName': def.displayName,
        'deployModes': DeployMode.toCsv(def.deployModes),
        'defaultDeployMode': def.defaultDeployMode.value,
        'defaultVersion': version ?? def.defaultVersion,
        'defaultBuildCommand': def.defaultBuildCommand,
        'defaultStartCommand': def.defaultStartCommand,
        'status': 'installing',
        'isBuiltin': true,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }).one(_db.context());

  // ── Update ────────────────────────────────────────────────────────────────

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
      if (def != null && def.versioned) {
        // Changing the default no longer replaces the installed toolchain: it
        // points new apps at another version, installing it first if it isn't
        // on the host yet.
        final existing = await _findVersionByName(id, defaultVersion);
        if (existing == null || existing.status == 'failed') {
          await _installVersionRow(app, defaultVersion);
        }
        await _markDefaultByName(id, defaultVersion);
      } else {
        await _patch(id, {'status': 'updating'});
        await _enqueue('install', id, version: defaultVersion);
      }
    }

    return findById(id);
  }

  /// Point new apps at an already-installed version.
  Future<ApplicationVersion> setDefaultVersion(
    int applicationId,
    int versionId,
  ) async {
    final row = await findVersion(applicationId, versionId);
    if (row.status != 'installed') {
      throw HttpException(
        409,
        'Version ${row.version} is not installed yet.',
      );
    }
    await _markDefaultByName(applicationId, row.version);
    return findVersion(applicationId, versionId);
  }

  Future<void> _markDefaultByName(int applicationId, String version) async {
    await Query<ApplicationVersion>(ApplicationVersionTable.metadata)
        .where(ApplicationVersionTable.applicationId.eq(applicationId))
        .update({'isDefault': false}).run(_db.context());
    await Query<ApplicationVersion>(ApplicationVersionTable.metadata)
        .where(ApplicationVersionTable.applicationId.eq(applicationId))
        .where(ApplicationVersionTable.version.eq(version))
        .update({'isDefault': true}).run(_db.context());
    await _patch(applicationId, {'defaultVersion': version});
  }

  // ── Remove ────────────────────────────────────────────────────────────────

  /// Remove a single installed version, leaving the rest in place.
  Future<void> removeVersion(int applicationId, int versionId) async {
    final app = await findById(applicationId);
    final row = await findVersion(applicationId, versionId);

    final inUse = await _appsPinning(app.key ?? '', row.version);
    if (inUse > 0) {
      throw HttpException(
        409,
        '${app.displayName} ${row.version} is pinned by $inUse app(s) — '
        'move them to another version before removing it.',
      );
    }

    // The family must keep pointing at something installed.
    final siblings = await listVersions(applicationId);
    final remaining = siblings.where((v) => v.id != versionId).toList();
    if ((row.isDefault ?? false) && remaining.isNotEmpty) {
      await _markDefaultByName(applicationId, remaining.first.version);
    } else if (remaining.isEmpty) {
      await _patch(applicationId, {'defaultVersion': null});
    }

    await _patchVersion(versionId, {'status': 'removing'});
    await _enqueue(
      'remove',
      applicationId,
      version: row.version,
      applicationVersionId: versionId,
    );
  }

  /// Remove an installed Application entirely, versions and all. Refuses
  /// while any [App] still references it — same guard style used elsewhere
  /// (e.g. deleting a [StorageProvider] with linked buckets).
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

    // One agent job per installed version, then the family row itself. The
    // child rows go with it via ON DELETE CASCADE.
    final versions = await listVersions(id);
    if (versions.isEmpty) {
      await _enqueue('remove', id, version: app.defaultVersion, dropFamily: true);
      return;
    }
    for (var i = 0; i < versions.length; i++) {
      await _enqueue(
        'remove',
        id,
        version: versions[i].version,
        applicationVersionId: versions[i].id,
        // Only the last job tears down the family row.
        dropFamily: i == versions.length - 1,
      );
    }
  }

  /// How many apps pin [version] of the runtime [key].
  Future<int> _appsPinning(String key, String version) async {
    final column = _appVersionColumn[key];
    if (column == null) return 0;
    return Query<App>(AppTable.metadata)
        .where(column.eq(version))
        .count(_db.context());
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _patch(int id, Map<String, Object?> data) =>
      Query<Application>(ApplicationTable.metadata)
          .where(ApplicationTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _patchVersion(int id, Map<String, Object?> data) =>
      Query<ApplicationVersion>(ApplicationVersionTable.metadata)
          .where(ApplicationVersionTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _enqueue(
    String action,
    int applicationId, {
    String? version,
    int? applicationVersionId,
    // Whether finishing this job should also tear down the Application row.
    // Only ever true for the final job of a whole-family removal — removing a
    // single version must leave the family and its other versions alone.
    bool dropFamily = false,
  }) =>
      RedisClient.instance.rpush(
        'gisila:queue:applications',
        jsonEncode({
          'action': action,
          'applicationId': applicationId,
          if (version != null) 'version': version,
          if (applicationVersionId != null)
            'applicationVersionId': applicationVersionId,
          if (action == 'remove') 'dropFamily': dropFamily,
        }),
      );
}
