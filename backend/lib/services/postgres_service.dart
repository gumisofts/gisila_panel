import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart' show env, systemPgPort;
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:postgres/postgres.dart' as pg;

/// Postgres settings the panel lets users tune via the Configuration tab.
/// Keys must match `pg_settings.name`; the agent applies them with
/// `ALTER SYSTEM SET` and restarts the cluster.
const kTunableSettings = <String>[
  'max_connections',
  'shared_buffers',
  'effective_cache_size',
  'work_mem',
  'maintenance_work_mem',
  'wal_buffers',
  'min_wal_size',
  'max_wal_size',
  'checkpoint_completion_target',
  'random_page_cost',
  'effective_io_concurrency',
  'max_worker_processes',
  'max_parallel_workers',
  'max_parallel_workers_per_gather',
  'log_min_duration_statement',
];

// Postgres major versions available from the pgdg repository.
const kSupportedVersions = [14, 15, 16, 17, 18];

// Valid backup scopes (maps to pg_dump --schema-only / --data-only).
const kBackupScopes = {'full', 'schema', 'data'};
const kBackupFrequencies = {'hourly', 'daily', 'weekly'};

/// Root directory for on-disk backup artifacts. Overridable via env for dev.
/// Owned by the `gisila` user so the API can stream downloads and stage uploads
/// while the root agent writes the dumps.
String pgBackupDir() =>
    env.getOrElse('GISILA_BACKUP_DIR', () => '/var/lib/gisila/backups');

/// Compute the next UTC run time for a preset schedule, strictly after [from].
DateTime computeNextRun(
  String frequency,
  int hour,
  int minute,
  int? weekday,
  DateTime from,
) {
  final f = from.toUtc();
  switch (frequency) {
    case 'hourly':
      var next = DateTime.utc(f.year, f.month, f.day, f.hour, minute);
      while (!next.isAfter(f)) {
        next = next.add(const Duration(hours: 1));
      }
      return next;
    case 'weekly':
      // Our weekday is 0=Sunday … 6=Saturday; Dart's is Mon=1 … Sun=7.
      final target = (weekday ?? 0).clamp(0, 6);
      final currentDow = f.weekday % 7; // Sun(7)→0, Mon(1)→1 … Sat(6)→6
      var delta = (target - currentDow) % 7;
      if (delta < 0) delta += 7;
      var next = DateTime.utc(f.year, f.month, f.day, hour, minute)
          .add(Duration(days: delta));
      if (!next.isAfter(f)) next = next.add(const Duration(days: 7));
      return next;
    case 'daily':
    default:
      var next = DateTime.utc(f.year, f.month, f.day, hour, minute);
      if (!next.isAfter(f)) next = next.add(const Duration(days: 1));
      return next;
  }
}

// Default port for each version when installed side-by-side.
const _defaultPorts = {
  14: 5414,
  15: 5415,
  16: 5416,
  17: 5417,
  18: 5418,
};

class PostgresService extends Service {
  Database get _db => db<Database>();

  // ── Instance CRUD ───────────────────────────────────────────────────────────

  Future<List<PostgresInstance>> listInstances() =>
      Query<PostgresInstance>(PostgresInstanceTable.metadata)
          .orderBy(PostgresInstanceTable.version)
          .all(_db.context());

  Future<PostgresInstance> findInstance(int id) async {
    final row = await Query<PostgresInstance>(PostgresInstanceTable.metadata)
        .where(PostgresInstanceTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Postgres instance #$id not found.');
    return row;
  }

  Future<PostgresInstance> installInstance({
    required int version,
    required String displayName,
    int? port,
  }) async {
    if (!kSupportedVersions.contains(version)) {
      throw HttpException(
          422, 'Unsupported version $version. Supported: $kSupportedVersions');
    }

    final existing =
        await Query<PostgresInstance>(PostgresInstanceTable.metadata)
            .where(PostgresInstanceTable.version.eq(version))
            .first(_db.context());
    if (existing != null) {
      if (existing.status == 'failed') {
        // A previous install attempt failed — remove the stale record so we
        // can start fresh.
        await Query<PostgresInstance>(PostgresInstanceTable.metadata)
            .where(PostgresInstanceTable.id.eq(existing.id!))
            .delete()
            .run(_db.context());
      } else {
        throw HttpException(409, 'PostgreSQL $version is already installed.');
      }
    }

    final resolvedPort = port ?? _defaultPorts[version] ?? (5432 + version);

    // Check port not already taken.
    final portConflict =
        await Query<PostgresInstance>(PostgresInstanceTable.metadata)
            .where(PostgresInstanceTable.port.eq(resolvedPort))
            .first(_db.context());
    if (portConflict != null) {
      throw HttpException(
          409, 'Port $resolvedPort is already used by another instance.');
    }

    final isFirst = (await listInstances()).isEmpty;

    final instance =
        await Query<PostgresInstance>(PostgresInstanceTable.metadata)
            .insert(<String, Object?>{
      'version': version,
      'displayName': displayName,
      'port': resolvedPort,
      'status': 'pending',
      'isDefault': isFirst,
      'dataDirectory': '/var/lib/postgresql/$version/main',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());

    await _enqueue('install_instance', {'instanceId': instance.id});
    return findInstance(instance.id!);
  }

  Future<PostgresInstance> setDefault(int id) async {
    final target = await findInstance(id);
    if (target.status != 'running') {
      throw HttpException(422, 'Instance must be running to set as default.');
    }

    // Clear current default.
    await Query<PostgresInstance>(PostgresInstanceTable.metadata)
        .where(PostgresInstanceTable.isDefault.eq(true))
        .update({'isDefault': false}).run(_db.context());

    await _patchInstance(id, {'isDefault': true});
    return findInstance(id);
  }

  Future<PostgresInstance> startInstance(int id) async {
    final instance = await findInstance(id);
    if (instance.status == 'running') return instance;
    await _patchInstance(id, {'status': 'pending'});
    await _enqueue('start_instance', {'instanceId': id});
    return findInstance(id);
  }

  Future<PostgresInstance> stopInstance(int id) async {
    final instance = await findInstance(id);
    if (isSystemInstance(instance)) {
      // Stopping this cluster would take the panel itself offline.
      throw HttpException(422, 'Cannot stop the system database.');
    }
    if (instance.status == 'stopped') return instance;
    await _enqueue('stop_instance', {'instanceId': id});
    return findInstance(id);
  }

  Future<void> uninstallInstance(int id) async {
    final instance = await findInstance(id);
    if (isSystemInstance(instance)) {
      throw HttpException(422, 'Cannot uninstall the system database.');
    }
    if (instance.isDefault == true) {
      throw HttpException(422,
          'Cannot uninstall the default instance. Set another as default first.');
    }
    await _patchInstance(id, {'status': 'uninstalling'});
    await _enqueue('uninstall_instance', {'instanceId': id});
  }

  /// Whether [instance] is the always-available cluster that backs the panel
  /// itself. Identified by its port, which is fixed in database.yaml. Its port
  /// is never editable and it can be neither stopped nor uninstalled.
  bool isSystemInstance(PostgresInstance instance) =>
      instance.port == systemPgPort;

  // ── Database CRUD ───────────────────────────────────────────────────────────

  Future<List<PostgresDatabase>> listDatabases(int instanceId) =>
      Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
          .where(PostgresDatabaseTable.instanceId.eq(instanceId))
          .orderBy(PostgresDatabaseTable.createdAt, desc: true)
          .all(_db.context());

  Future<PostgresDatabase> findDatabase(int id) async {
    final row = await Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
        .where(PostgresDatabaseTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Database #$id not found.');
    return row;
  }

  Future<PostgresDatabase> createDatabase({
    required int instanceId,
    required String dbName,
    required String roleName,
    required String password,
    List<String>? extensions,
  }) async {
    final instance = await findInstance(instanceId);
    if (instance.status != 'running') {
      throw HttpException(
          422, 'Instance must be running to create a database.');
    }

    _validateIdentifier('database name', dbName);
    _validateIdentifier('role name', roleName);

    final db = await Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
        .insert(<String, Object?>{
      'instanceId': instanceId,
      'dbName': dbName,
      'roleName': roleName,
      'password': password,
      'extensions': jsonEncode(extensions ?? []),
      'status': 'pending',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());

    await _enqueue('create_database', {
      'instanceId': instanceId,
      'databaseId': db.id,
    });
    return findDatabase(db.id!);
  }

  Future<void> dropDatabase(int id) async {
    final db = await findDatabase(id);

    // If the database was never successfully created, remove the record directly
    // without involving the agent — there is nothing to drop on the server.
    if (db.status == 'failed' || db.status == 'pending') {
      await Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
          .where(PostgresDatabaseTable.id.eq(id))
          .delete()
          .run(_db.context());
      return;
    }

    final instance = await findInstance(db.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to drop a database.');
    }
    await _patchDatabase(id, {'status': 'dropped'});
    await _enqueue('drop_database', {
      'instanceId': db.instanceId,
      'databaseId': id,
    });
  }

  // ── Connection info ─────────────────────────────────────────────────────────

  Map<String, Object?> connectionInfo(
      PostgresInstance instance, PostgresDatabase db) {
    final host = 'localhost';
    final port = instance.port;
    final url =
        'postgresql://${db.roleName}:${db.password}@$host:$port/${db.dbName}';
    return {
      'host': host,
      'port': port,
      'database': db.dbName,
      'username': db.roleName,
      'password': db.password,
      'url': url,
    };
  }

  // ── Metrics ───────────────────────────────────────────────────────────────

  /// Live metrics for an instance: connection counts, throughput, cache hit
  /// ratio, per-database sizes, plus host CPU/RAM sampled by the worker.
  ///
  /// Connection/DB stats are read directly over a localhost connection using
  /// the read-only `gisila_monitor` role. If that role is not provisioned yet,
  /// returns `{status: 'initializing'}` and triggers provisioning in the
  /// background; the UI polls until it flips to `ok`.
  Future<Map<String, Object?>> metrics(int id) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      return {'status': 'not_running'};
    }
    if (inst.monitorPassword == null || inst.monitorPassword!.isEmpty) {
      await _ensureMonitor(inst);
      return {'status': 'initializing'};
    }
    try {
      final sql = await _queryStats(inst);
      final host = await _hostStats(id);
      return {'status': 'ok', 'host': host, ...sql};
    } catch (e) {
      // Most likely the monitor role isn't created yet (auth failure) — kick off
      // provisioning and ask the client to retry.
      await _ensureMonitor(inst);
      return {'status': 'initializing', 'detail': e.toString()};
    }
  }

  Future<Map<String, Object?>> _queryStats(PostgresInstance inst) async {
    final conn = await pg.Connection.open(
      pg.Endpoint(
        host: '127.0.0.1',
        port: inst.port,
        database: 'postgres',
        username: 'gisila_monitor',
        password: inst.monitorPassword,
      ),
      settings: pg.ConnectionSettings(
        sslMode: pg.SslMode.disable,
        connectTimeout: const Duration(seconds: 5),
        queryTimeout: const Duration(seconds: 10),
      ),
    );
    try {
      final activity = (await conn.execute(
        "SELECT count(*) AS total, "
        "count(*) FILTER (WHERE state='active') AS active, "
        "count(*) FILTER (WHERE state='idle') AS idle, "
        "count(*) FILTER (WHERE state='idle in transaction') AS idle_in_txn, "
        "count(*) FILTER (WHERE wait_event_type='Lock') AS waiting "
        "FROM pg_stat_activity WHERE backend_type='client backend'",
      ))
          .first
          .toColumnMap();

      final maxConn = _toInt((await conn.execute(
        "SELECT setting::int AS v FROM pg_settings WHERE name='max_connections'",
      ))
          .first
          .toColumnMap()['v']);

      final db = (await conn.execute(
        "SELECT coalesce(sum(xact_commit),0)::bigint AS commits, "
        "coalesce(sum(xact_rollback),0)::bigint AS rollbacks, "
        "coalesce(sum(blks_hit),0)::bigint AS hits, "
        "coalesce(sum(blks_read),0)::bigint AS reads, "
        "coalesce(sum(tup_inserted),0)::bigint AS inserted, "
        "coalesce(sum(tup_updated),0)::bigint AS updated, "
        "coalesce(sum(tup_deleted),0)::bigint AS deleted, "
        "coalesce(sum(deadlocks),0)::bigint AS deadlocks "
        "FROM pg_stat_database",
      ))
          .first
          .toColumnMap();

      final sizes = (await conn.execute(
        "SELECT datname, pg_database_size(datname)::bigint AS size "
        "FROM pg_database WHERE datname NOT IN ('template0','template1') "
        "ORDER BY size DESC",
      ))
          .map((r) {
        final m = r.toColumnMap();
        return {'name': m['datname'], 'sizeBytes': _toInt(m['size'])};
      }).toList();

      final uptime = _toInt((await conn.execute(
        "SELECT EXTRACT(EPOCH FROM (now()-pg_postmaster_start_time()))::bigint AS s",
      ))
          .first
          .toColumnMap()['s']);

      final hits = _toInt(db['hits']);
      final reads = _toInt(db['reads']);
      final total = hits + reads;
      final cacheHitRatio = total > 0 ? hits / total : 1.0;

      return {
        'connections': {
          'total': _toInt(activity['total']),
          'active': _toInt(activity['active']),
          'idle': _toInt(activity['idle']),
          'idleInTransaction': _toInt(activity['idle_in_txn']),
          'waiting': _toInt(activity['waiting']),
          'max': maxConn,
        },
        'throughput': {
          'commits': _toInt(db['commits']),
          'rollbacks': _toInt(db['rollbacks']),
          'inserted': _toInt(db['inserted']),
          'updated': _toInt(db['updated']),
          'deleted': _toInt(db['deleted']),
          'deadlocks': _toInt(db['deadlocks']),
        },
        'cacheHitRatio': cacheHitRatio,
        'uptimeSeconds': uptime,
        'databases': sizes,
      };
    } finally {
      await conn.close();
    }
  }

  /// Read the host CPU%/RAM snapshot the worker writes to Redis for this
  /// instance's systemd unit, if present.
  Future<Map<String, Object?>?> _hostStats(int id) async {
    try {
      final raw = await RedisClient.instance.get('gisila:pgstat:$id');
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Read the current value of every tunable setting from `pg_settings`.
  Future<Map<String, Object?>> getConfig(int id) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      return {'status': 'not_running', 'settings': []};
    }
    if (inst.monitorPassword == null || inst.monitorPassword!.isEmpty) {
      await _ensureMonitor(inst);
      return {'status': 'initializing', 'settings': []};
    }
    try {
      final conn = await pg.Connection.open(
        pg.Endpoint(
          host: '127.0.0.1',
          port: inst.port,
          database: 'postgres',
          username: 'gisila_monitor',
          password: inst.monitorPassword,
        ),
        settings: pg.ConnectionSettings(
          sslMode: pg.SslMode.disable,
          connectTimeout: const Duration(seconds: 5),
        ),
      );
      try {
        final names = kTunableSettings.map((s) => "'$s'").join(',');
        final rows = (await conn.execute(
          "SELECT name, setting, unit, short_desc, context, vartype, "
          "min_val, max_val, enumvals, boot_val, pending_restart "
          "FROM pg_settings WHERE name IN ($names)",
        ))
            .map((r) {
          final m = r.toColumnMap();
          return {
            'name': m['name'],
            'value': m['setting']?.toString(),
            'unit': m['unit']?.toString(),
            'description': m['short_desc']?.toString(),
            'context': m['context']?.toString(),
            'type': m['vartype']?.toString(),
            'min': m['min_val']?.toString(),
            'max': m['max_val']?.toString(),
            'enumVals': m['enumvals']?.toString(),
            'bootValue': m['boot_val']?.toString(),
            'pendingRestart': m['pending_restart'] == true,
          };
        }).toList();
        // Preserve the curated order.
        rows.sort((a, b) => kTunableSettings
            .indexOf(a['name'] as String)
            .compareTo(kTunableSettings.indexOf(b['name'] as String)));
        return {'status': 'ok', 'settings': rows};
      } finally {
        await conn.close();
      }
    } catch (e) {
      await _ensureMonitor(inst);
      return {'status': 'initializing', 'settings': [], 'detail': e.toString()};
    }
  }

  /// Apply configuration changes. Only whitelisted keys are accepted; the
  /// change is applied with `ALTER SYSTEM SET` and the cluster restarted by the
  /// worker (some settings such as `max_connections` require a restart).
  Future<PostgresInstance> updateConfig(
      int id, Map<String, String> settings) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      throw HttpException(422, 'Instance must be running to change settings.');
    }
    final clean = <String, String>{};
    settings.forEach((key, value) {
      if (!kTunableSettings.contains(key)) return;
      final v = value.trim();
      // Reject values containing quotes/backslashes to keep ALTER SYSTEM safe.
      if (v.contains("'") || v.contains(r'\')) {
        throw HttpException(422, 'Invalid value for $key.');
      }
      clean[key] = v;
    });
    if (clean.isEmpty) {
      throw HttpException(422, 'No valid settings to apply.');
    }
    await _patchInstance(id, {'status': 'pending'});
    await _enqueue('configure_instance', {
      'instanceId': id,
      'settings': clean,
    });
    return findInstance(id);
  }

  /// Generate + persist a monitor password (if missing) and enqueue creation of
  /// the `gisila_monitor` role on the instance.
  Future<void> _ensureMonitor(PostgresInstance inst) async {
    if (inst.monitorPassword == null || inst.monitorPassword!.isEmpty) {
      await _patchInstance(inst.id!, {'monitorPassword': generatePassword()});
    }
    await _enqueue('ensure_monitor', {'instanceId': inst.id});
  }

  static int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  // ── Backups ───────────────────────────────────────────────────────────────

  Future<List<PostgresBackup>> listBackups(int databaseId) =>
      Query<PostgresBackup>(PostgresBackupTable.metadata)
          .where(PostgresBackupTable.databaseId.eq(databaseId))
          .orderBy(PostgresBackupTable.createdAt, desc: true)
          .all(_db.context());

  Future<PostgresBackup> findBackup(int id) async {
    final row = await Query<PostgresBackup>(PostgresBackupTable.metadata)
        .where(PostgresBackupTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Backup #$id not found.');
    return row;
  }

  /// Queue a backup of [databaseId] with the given [scope]. Returns the new
  /// pending [PostgresBackup] row; the worker fills in the file + status.
  Future<PostgresBackup> triggerBackup(
    int databaseId, {
    String scope = 'full',
    String trigger = 'manual',
  }) async {
    if (!kBackupScopes.contains(scope)) {
      throw HttpException(422, 'Invalid backup scope "$scope".');
    }
    final db = await findDatabase(databaseId);
    if (db.status != 'active') {
      throw HttpException(422, 'Database must be active to back it up.');
    }
    final instance = await findInstance(db.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to back up a database.');
    }
    final row = await Query<PostgresBackup>(PostgresBackupTable.metadata)
        .insert(<String, Object?>{
      'databaseId': databaseId,
      'scope': scope,
      'status': 'pending',
      'trigger': trigger,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());

    await _enqueue('backup_database', {
      'instanceId': db.instanceId,
      'databaseId': databaseId,
      'backupId': row.id,
    });
    return row;
  }

  /// Delete a backup row and its file on disk.
  Future<void> deleteBackup(int id) async {
    final b = await findBackup(id);
    final path = b.filePath;
    if (path != null && path.isNotEmpty) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // best-effort — the row is removed regardless.
      }
    }
    await Query<PostgresBackup>(PostgresBackupTable.metadata)
        .where(PostgresBackupTable.id.eq(id))
        .delete()
        .run(_db.context());
  }

  /// Restore a database from one of its completed backups.
  Future<void> restoreFromBackup(int backupId) async {
    final b = await findBackup(backupId);
    if (b.status != 'completed' || (b.filePath?.isEmpty ?? true)) {
      throw HttpException(422, 'Backup is not available to restore.');
    }
    final db = await findDatabase(b.databaseId);
    final instance = await findInstance(db.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to restore.');
    }
    await _enqueue('restore_database', {
      'instanceId': db.instanceId,
      'databaseId': db.id,
      'inputPath': b.filePath,
    });
  }

  /// Stage an uploaded dump to disk and queue a restore from it.
  Future<void> saveUploadAndRestore(
    int databaseId,
    List<int> bytes,
    String filename,
  ) async {
    final db = await findDatabase(databaseId);
    final instance = await findInstance(db.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to restore.');
    }
    if (bytes.isEmpty) throw HttpException(422, 'Uploaded file is empty.');

    final lower = filename.toLowerCase();
    final String ext;
    if (lower.endsWith('.sql.gz') || lower.endsWith('.gz')) {
      ext = '.sql.gz';
    } else if (lower.endsWith('.sql')) {
      ext = '.sql';
    } else {
      throw HttpException(422, 'Upload must be a .sql or .sql.gz file.');
    }

    final dir = Directory('${pgBackupDir()}/uploads');
    await dir.create(recursive: true);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final suffix = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final path = '${dir.path}/upload-$stamp-$suffix$ext';
    await File(path).writeAsBytes(bytes, flush: true);

    await _enqueue('restore_database', {
      'instanceId': db.instanceId,
      'databaseId': db.id,
      'inputPath': path,
    });
  }

  // ── Backup schedule ─────────────────────────────────────────────────────────

  /// Get the schedule for a database, creating a disabled default if absent.
  Future<PostgresBackupSchedule> getSchedule(int databaseId) async {
    await findDatabase(databaseId); // validates existence
    final existing =
        await Query<PostgresBackupSchedule>(PostgresBackupScheduleTable.metadata)
            .where(PostgresBackupScheduleTable.databaseId.eq(databaseId))
            .first(_db.context());
    if (existing != null) return existing;
    return Query<PostgresBackupSchedule>(PostgresBackupScheduleTable.metadata)
        .insert(<String, Object?>{
      'databaseId': databaseId,
      'enabled': false,
      'frequency': 'daily',
      'hour': 2,
      'minute': 0,
      'scope': 'full',
      'keepCount': 7,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
  }

  Future<PostgresBackupSchedule> updateSchedule(
    int databaseId, {
    bool? enabled,
    String? frequency,
    int? hour,
    int? minute,
    int? weekday,
    String? scope,
    int? keepCount,
  }) async {
    final current = await getSchedule(databaseId);
    if (frequency != null && !kBackupFrequencies.contains(frequency)) {
      throw HttpException(422, 'Invalid frequency "$frequency".');
    }
    if (scope != null && !kBackupScopes.contains(scope)) {
      throw HttpException(422, 'Invalid scope "$scope".');
    }

    final mergedEnabled = enabled ?? current.enabled ?? false;
    final mergedFreq = frequency ?? current.frequency ?? 'daily';
    final mergedHour = (hour ?? current.hour ?? 2).clamp(0, 23);
    final mergedMinute = (minute ?? current.minute ?? 0).clamp(0, 59);
    final mergedWeekday =
        weekday != null ? weekday.clamp(0, 6) : current.weekday;

    final patch = <String, Object?>{
      'enabled': mergedEnabled,
      'frequency': mergedFreq,
      'hour': mergedHour,
      'minute': mergedMinute,
      'weekday': mergedWeekday,
      if (scope != null) 'scope': scope,
      if (keepCount != null) 'keepCount': keepCount.clamp(1, 365),
      'nextRunAt': mergedEnabled
          ? computeNextRun(mergedFreq, mergedHour, mergedMinute, mergedWeekday,
                  DateTime.now().toUtc())
              .toIso8601String()
          : null,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

    await Query<PostgresBackupSchedule>(PostgresBackupScheduleTable.metadata)
        .where(PostgresBackupScheduleTable.databaseId.eq(databaseId))
        .update(patch)
        .run(_db.context());
    return getSchedule(databaseId);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _validateIdentifier(String label, String value) {
    final re = RegExp(r'^[a-z][a-z0-9_]{0,62}$');
    if (!re.hasMatch(value)) {
      throw HttpException(
          422,
          'Invalid $label "$value". Must start with a letter, contain only '
          'lowercase letters, digits and underscores, max 63 chars.');
    }
  }

  Future<void> _patchInstance(int id, Map<String, Object?> data) =>
      Query<PostgresInstance>(PostgresInstanceTable.metadata)
          .where(PostgresInstanceTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _patchDatabase(int id, Map<String, Object?> data) =>
      Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
          .where(PostgresDatabaseTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _enqueue(String action, Map<String, Object?> payload) =>
      RedisClient.instance.rpush(
        'gisila:queue:postgres',
        jsonEncode({'action': action, ...payload}),
      );
}

/// Generate a random password (48 URL-safe chars).
String generatePassword() {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final rng = Random.secure();
  return List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
}
