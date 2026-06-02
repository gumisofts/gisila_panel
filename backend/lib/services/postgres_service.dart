import 'dart:convert';
import 'dart:math';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
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
    if (instance.status == 'stopped') return instance;
    await _enqueue('stop_instance', {'instanceId': id});
    return findInstance(id);
  }

  Future<void> uninstallInstance(int id) async {
    final instance = await findInstance(id);
    if (instance.isDefault == true) {
      throw HttpException(422,
          'Cannot uninstall the default instance. Set another as default first.');
    }
    await _patchInstance(id, {'status': 'uninstalling'});
    await _enqueue('uninstall_instance', {'instanceId': id});
  }

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
