import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
// Reuse the shared, engine-agnostic helpers rather than duplicating them.
import 'package:gisila_panel/services/postgres_service.dart'
    show computeNextRun, generatePassword, pgBackupDir;
import 'package:mongo_dart/mongo_dart.dart' as mongo;

/// MongoDB Community versions the panel can install side-by-side.
const kMongoVersions = ['6.0', '7.0', '8.0'];

/// Built-in MongoDB roles an operator may grant a database user. These names are
/// interpolated into a createUser command on the agent, so the allowlist is the
/// guard. Kept in sync with `_kMongoRoleOptions` in database_engine.dart.
const kMongoRoles = {
  'read',
  'readWrite',
  'dbAdmin',
  'dbOwner',
  'readAnyDatabase',
  'readWriteAnyDatabase',
  'dbAdminAnyDatabase',
  'clusterMonitor',
};

/// mongodump produces a single archive — there is no schema/data split, so the
/// only meaningful scope is `full`. Kept for symmetry with the Postgres model.
const kMongoBackupScopes = {'full'};
const kMongoBackupFrequencies = {'hourly', 'daily', 'weekly'};

/// Tunable mongod settings the panel surfaces in the Configuration tab. The
/// agent writes them into the instance's mongod config and restarts the unit.
const kMongoTunables = <Map<String, String>>[
  {
    'name': 'cacheSizeGB',
    'unit': 'GB',
    'type': 'real',
    'description':
        'WiredTiger internal cache size. Defaults to 50% of (RAM − 1GB).',
  },
  {
    'name': 'maxIncomingConnections',
    'unit': '',
    'type': 'integer',
    'description': 'Maximum number of simultaneous client connections.',
  },
];

// Default port for each version when installed side-by-side. The stock MongoDB
// port is 27017; subsequent versions step up so they can coexist.
const _defaultPorts = {
  '6.0': 27017,
  '7.0': 27018,
  '8.0': 27019,
};

class MongoService extends Service {
  Database get _db => db<Database>();

  // ── Instance CRUD ───────────────────────────────────────────────────────────

  Future<List<MongoInstance>> listInstances() =>
      Query<MongoInstance>(MongoInstanceTable.metadata)
          .orderBy(MongoInstanceTable.version)
          .all(_db.context());

  Future<MongoInstance> findInstance(int id) async {
    final row = await Query<MongoInstance>(MongoInstanceTable.metadata)
        .where(MongoInstanceTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('MongoDB instance #$id not found.');
    return row;
  }

  Future<MongoInstance> installInstance({
    required String version,
    required String displayName,
    int? port,
  }) async {
    if (!kMongoVersions.contains(version)) {
      throw HttpException(
          422, 'Unsupported version $version. Supported: $kMongoVersions');
    }

    final existing = await Query<MongoInstance>(MongoInstanceTable.metadata)
        .where(MongoInstanceTable.version.eq(version))
        .first(_db.context());
    if (existing != null) {
      if (existing.status == 'failed') {
        // A previous install attempt failed — remove the stale record so we can
        // start fresh.
        await Query<MongoInstance>(MongoInstanceTable.metadata)
            .where(MongoInstanceTable.id.eq(existing.id!))
            .delete()
            .run(_db.context());
      } else {
        throw HttpException(409, 'MongoDB $version is already installed.');
      }
    }

    final resolvedPort = port ?? _defaultPorts[version] ?? 27017;

    final portConflict = await Query<MongoInstance>(MongoInstanceTable.metadata)
        .where(MongoInstanceTable.port.eq(resolvedPort))
        .first(_db.context());
    if (portConflict != null) {
      throw HttpException(
          409, 'Port $resolvedPort is already used by another instance.');
    }

    // Never mark default until the install succeeds — a failed first attempt
    // used to become the default and then blocked Uninstall in the UI/API.
    final instance = await Query<MongoInstance>(MongoInstanceTable.metadata)
        .insert(<String, Object?>{
      'version': version,
      'displayName': displayName,
      'port': resolvedPort,
      'status': 'pending',
      'isDefault': false,
      // The root admin password is generated up front so the agent can create
      // the authenticated root user during install.
      'rootPassword': generatePassword(),
      'dataDirectory': '/var/lib/mongo/$version',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());

    await _enqueue('install_instance', {'instanceId': instance.id});
    return findInstance(instance.id!);
  }

  /// Re-queue a failed install. The host was rolled back on failure, so this
  /// runs the full install path again against the same row.
  Future<MongoInstance> retryInstall(int id) async {
    final instance = await findInstance(id);
    if (instance.status != 'failed') {
      throw HttpException(422, 'Only failed installations can be retried.');
    }
    await _patchInstance(id, {
      'status': 'pending',
      'errorMessage': null,
    });
    await _enqueue('install_instance', {'instanceId': id});
    return findInstance(id);
  }

  Future<MongoInstance> setDefault(int id) async {
    final target = await findInstance(id);
    if (target.status != 'running') {
      throw HttpException(422, 'Instance must be running to set as default.');
    }
    await Query<MongoInstance>(MongoInstanceTable.metadata)
        .where(MongoInstanceTable.isDefault.eq(true))
        .update({'isDefault': false}).run(_db.context());
    await _patchInstance(id, {'isDefault': true});
    return findInstance(id);
  }

  /// Make a MongoDB instance publicly reachable over TLS (or revert to
  /// localhost-only). When [isPublic] the agent obtains a Let's Encrypt cert for
  /// [domain], enables TLS + binds all interfaces, opens the firewall, and the
  /// server becomes reachable at domain:port with tls=true.
  Future<MongoInstance> setPublicExposure(
    int id, {
    required bool isPublic,
    String? domain,
  }) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      throw HttpException(422, 'Instance must be running to change exposure.');
    }
    if (isPublic) {
      final host = (domain ?? '').trim().toLowerCase();
      if (host.isEmpty) {
        throw HttpException(
            422, 'A domain is required to make the database public.');
      }
      if (!RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$').hasMatch(host)) {
        throw HttpException(422, 'Enter a valid domain, e.g. db.example.com');
      }
      await _patchInstance(id, {
        'isPublic': true,
        'publicDomain': host,
        'errorMessage': null,
      });
      await _enqueue('expose_instance', {'instanceId': id});
    } else {
      await _patchInstance(id, {'isPublic': false});
      await _enqueue('unexpose_instance', {'instanceId': id});
    }
    return findInstance(id);
  }

  Future<MongoInstance> startInstance(int id) async {
    final instance = await findInstance(id);
    if (instance.status == 'running') return instance;
    await _patchInstance(id, {'status': 'pending'});
    await _enqueue('start_instance', {'instanceId': id});
    return findInstance(id);
  }

  Future<MongoInstance> stopInstance(int id) async {
    final instance = await findInstance(id);
    if (instance.status == 'stopped') return instance;
    await _enqueue('stop_instance', {'instanceId': id});
    return findInstance(id);
  }

  Future<void> uninstallInstance(int id) async {
    final instance = await findInstance(id);
    final failed = instance.status == 'failed';
    // Failed installs already rolled back on the host — allow removal even when
    // they were incorrectly marked as default (legacy rows).
    if (instance.isDefault == true && !failed) {
      throw HttpException(422,
          'Cannot uninstall the default instance. Set another as default first.');
    }
    await _patchInstance(id, {
      'status': 'uninstalling',
      if (failed) 'isDefault': false,
      if (failed) 'errorMessage': null,
    });
    await _enqueue('uninstall_instance', {'instanceId': id});
  }

  // ── Database CRUD ───────────────────────────────────────────────────────────

  Future<List<MongoDatabase>> listDatabases(int instanceId) =>
      Query<MongoDatabase>(MongoDatabaseTable.metadata)
          .where(MongoDatabaseTable.instanceId.eq(instanceId))
          .orderBy(MongoDatabaseTable.createdAt, desc: true)
          .all(_db.context());

  Future<MongoDatabase> findDatabase(int id) async {
    final row = await Query<MongoDatabase>(MongoDatabaseTable.metadata)
        .where(MongoDatabaseTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Database #$id not found.');
    return row;
  }

  Future<MongoDatabase> createDatabase({
    required int instanceId,
    required String dbName,
    required String userName,
    required String password,
    List<String>? roles,
  }) async {
    final instance = await findInstance(instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to create a database.');
    }

    _validateIdentifier('database name', dbName);
    _validateIdentifier('user name', userName);
    final normRoles = _normalizeRoles(roles, fallback: ['readWrite']);

    final database = await Query<MongoDatabase>(MongoDatabaseTable.metadata)
        .insert(<String, Object?>{
      'instanceId': instanceId,
      'dbName': dbName,
      'userName': userName,
      'password': password,
      'roles': jsonEncode(normRoles),
      'status': 'pending',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());

    await _enqueue('create_database', {
      'instanceId': instanceId,
      'databaseId': database.id,
    });
    return findDatabase(database.id!);
  }

  /// Change the granted roles of an existing database user. The full desired set
  /// is supplied; the agent reconciles via `updateUser`.
  Future<MongoDatabase> updateRoles(int id, List<String>? roles) async {
    final database = await findDatabase(id);
    if (database.status != 'active') {
      throw HttpException(
          422, 'Database user must be active to change its roles.');
    }
    final instance = await findInstance(database.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to change roles.');
    }
    final normRoles = _normalizeRoles(roles, fallback: const []);
    await _patchDatabase(id, {
      'roles': jsonEncode(normRoles),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _enqueue('update_roles', {
      'instanceId': database.instanceId,
      'databaseId': id,
    });
    return findDatabase(id);
  }

  /// Validate, de-duplicate and preserve the case of a requested role list
  /// against [kMongoRoles]. Unknown roles are rejected.
  List<String> _normalizeRoles(List<String>? requested,
      {required List<String> fallback}) {
    final out = <String>[];
    for (final raw in requested ?? const <String>[]) {
      final r = raw.trim();
      if (r.isEmpty) continue;
      if (!kMongoRoles.contains(r)) {
        throw HttpException(
            422,
            'Unknown role "$raw". Allowed: ${kMongoRoles.join(', ')}.');
      }
      if (!out.contains(r)) out.add(r);
    }
    return out.isEmpty ? List.of(fallback) : out;
  }

  Future<void> dropDatabase(int id) async {
    final database = await findDatabase(id);

    // Never-provisioned rows can be removed directly — nothing exists on the
    // server to drop.
    if (database.status == 'failed' || database.status == 'pending') {
      await Query<MongoDatabase>(MongoDatabaseTable.metadata)
          .where(MongoDatabaseTable.id.eq(id))
          .delete()
          .run(_db.context());
      return;
    }

    final instance = await findInstance(database.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to drop a database.');
    }
    await _patchDatabase(id, {'status': 'dropped'});
    await _enqueue('drop_database', {
      'instanceId': database.instanceId,
      'databaseId': id,
    });
  }

  // ── Connection info ─────────────────────────────────────────────────────────

  Map<String, Object?> connectionInfo(
      MongoInstance instance, MongoDatabase database) {
    final host = '127.0.0.1';
    final port = instance.port;
    final url =
        'mongodb://${database.userName}:${database.password}@$host:$port/${database.dbName}?authSource=${database.dbName}';
    final info = <String, Object?>{
      'host': host,
      'port': port,
      'database': database.dbName,
      'username': database.userName,
      'password': database.password,
      'authSource': database.dbName,
      'url': url,
    };
    if (instance.isPublic == true && (instance.publicDomain ?? '').isNotEmpty) {
      final pubHost = instance.publicDomain!;
      info['publicHost'] = pubHost;
      info['publicUrl'] =
          'mongodb://${database.userName}:${database.password}@$pubHost:$port/${database.dbName}?authSource=${database.dbName}&tls=true';
    }
    return info;
  }

  // ── Metrics ───────────────────────────────────────────────────────────────

  /// Live metrics for an instance via the read-only `gisila_monitor` user:
  /// connections, opcounters, memory, uptime and per-database sizes. Provisions
  /// the monitor user on first use (returns `initializing` until ready).
  Future<Map<String, Object?>> metrics(int id) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      return {'status': 'not_running'};
    }
    if (inst.monitorPassword == null || inst.monitorPassword!.isEmpty) {
      await _ensureMonitor(inst);
      return {'status': 'initializing'};
    }
    mongo.Db? conn;
    try {
      conn = await _openMonitor(inst);
      final status = await conn.runCommand({'serverStatus': 1});
      final listDbs = await conn.runCommand({'listDatabases': 1});

      final connections = (status['connections'] as Map?) ?? const {};
      final opcounters = (status['opcounters'] as Map?) ?? const {};
      final mem = (status['mem'] as Map?) ?? const {};
      final network = (status['network'] as Map?) ?? const {};

      final dbs = ((listDbs['databases'] as List?) ?? const [])
          .map((d) {
        final m = d as Map;
        return {
          'name': m['name'],
          'sizeBytes': _toInt(m['sizeOnDisk']),
        };
      }).toList()
        ..sort((a, b) =>
            _toInt(b['sizeBytes']).compareTo(_toInt(a['sizeBytes'])));

      final host = await _hostStats(id);

      return {
        'status': 'ok',
        'host': host,
        'connections': {
          'current': _toInt(connections['current']),
          'available': _toInt(connections['available']),
          'active': _toInt(connections['active']),
          'total': _toInt(connections['current']),
          'max': _toInt(connections['current']) +
              _toInt(connections['available']),
        },
        'opcounters': {
          'insert': _toInt(opcounters['insert']),
          'query': _toInt(opcounters['query']),
          'update': _toInt(opcounters['update']),
          'delete': _toInt(opcounters['delete']),
          'getmore': _toInt(opcounters['getmore']),
          'command': _toInt(opcounters['command']),
        },
        'memory': {
          'residentMb': _toInt(mem['resident']),
          'virtualMb': _toInt(mem['virtual']),
        },
        'network': {
          'bytesIn': _toInt(network['bytesIn']),
          'bytesOut': _toInt(network['bytesOut']),
        },
        'uptimeSeconds': _toInt(status['uptime']),
        'databases': dbs,
      };
    } catch (e) {
      // Most likely the monitor user isn't created yet — provision and retry.
      await _ensureMonitor(inst);
      return {'status': 'initializing', 'detail': e.toString()};
    } finally {
      await conn?.close();
    }
  }

  Future<Map<String, Object?>?> _hostStats(int id) async {
    try {
      final raw = await RedisClient.instance.get('gisila:mongostat:$id');
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Read the current value of every tunable from the running server's launch
  /// options (`getCmdLineOpts`).
  Future<Map<String, Object?>> getConfig(int id) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      return {'status': 'not_running', 'settings': []};
    }
    if (inst.monitorPassword == null || inst.monitorPassword!.isEmpty) {
      await _ensureMonitor(inst);
      return {'status': 'initializing', 'settings': []};
    }
    mongo.Db? conn;
    try {
      conn = await _openMonitor(inst);
      final opts = await conn.runCommand({'getCmdLineOpts': 1});
      final parsed = (opts['parsed'] as Map?) ?? const {};
      final storage = (parsed['storage'] as Map?) ?? const {};
      final wiredTiger = (storage['wiredTiger'] as Map?) ?? const {};
      final engineConfig = (wiredTiger['engineConfig'] as Map?) ?? const {};
      final net = (parsed['net'] as Map?) ?? const {};

      final current = <String, Object?>{
        'cacheSizeGB': engineConfig['cacheSizeGB'],
        'maxIncomingConnections': net['maxIncomingConnections'],
      };

      final settings = kMongoTunables.map((t) {
        final name = t['name']!;
        return {
          'name': name,
          'value': current[name]?.toString(),
          'unit': t['unit'],
          'description': t['description'],
          'type': t['type'],
        };
      }).toList();
      return {'status': 'ok', 'settings': settings};
    } catch (e) {
      await _ensureMonitor(inst);
      return {'status': 'initializing', 'settings': [], 'detail': e.toString()};
    } finally {
      await conn?.close();
    }
  }

  /// Apply configuration changes. Only whitelisted keys are accepted; the change
  /// is written into the instance's mongod config and the unit restarted.
  Future<MongoInstance> updateConfig(
      int id, Map<String, String> settings) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      throw HttpException(422, 'Instance must be running to change settings.');
    }
    final allowed = kMongoTunables.map((t) => t['name']).toSet();
    final clean = <String, String>{};
    settings.forEach((key, value) {
      if (!allowed.contains(key)) return;
      final v = value.trim();
      // Tunables are all numeric — reject anything that isn't, so nothing unsafe
      // reaches the YAML config the agent writes.
      if (v.isEmpty || double.tryParse(v) == null) {
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
  /// the read-only `gisila_monitor` user on the instance.
  Future<void> _ensureMonitor(MongoInstance inst) async {
    if (inst.monitorPassword == null || inst.monitorPassword!.isEmpty) {
      await _patchInstance(inst.id!, {'monitorPassword': generatePassword()});
    }
    await _enqueue('ensure_monitor', {'instanceId': inst.id});
  }

  Future<mongo.Db> _openMonitor(MongoInstance inst) async {
    final uri =
        'mongodb://gisila_monitor:${inst.monitorPassword}@127.0.0.1:${inst.port}/admin?authSource=admin';
    final conn = await mongo.Db.create(uri);
    await conn.open();
    return conn;
  }

  static int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  // ── Backups ───────────────────────────────────────────────────────────────

  Future<List<MongoBackup>> listBackups(int databaseId) =>
      Query<MongoBackup>(MongoBackupTable.metadata)
          .where(MongoBackupTable.databaseId.eq(databaseId))
          .orderBy(MongoBackupTable.createdAt, desc: true)
          .all(_db.context());

  Future<MongoBackup> findBackup(int id) async {
    final row = await Query<MongoBackup>(MongoBackupTable.metadata)
        .where(MongoBackupTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Backup #$id not found.');
    return row;
  }

  Future<MongoBackup> triggerBackup(
    int databaseId, {
    String scope = 'full',
    String trigger = 'manual',
  }) async {
    if (!kMongoBackupScopes.contains(scope)) {
      throw HttpException(422, 'Invalid backup scope "$scope".');
    }
    final database = await findDatabase(databaseId);
    if (database.status != 'active') {
      throw HttpException(422, 'Database must be active to back it up.');
    }
    final instance = await findInstance(database.instanceId);
    if (instance.status != 'running') {
      throw HttpException(
          422, 'Instance must be running to back up a database.');
    }
    final row = await Query<MongoBackup>(MongoBackupTable.metadata)
        .insert(<String, Object?>{
      'databaseId': databaseId,
      'scope': scope,
      'status': 'pending',
      'trigger': trigger,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());

    await _enqueue('backup_database', {
      'instanceId': database.instanceId,
      'databaseId': databaseId,
      'backupId': row.id,
    });
    return row;
  }

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
    await Query<MongoBackup>(MongoBackupTable.metadata)
        .where(MongoBackupTable.id.eq(id))
        .delete()
        .run(_db.context());
  }

  Future<void> restoreFromBackup(int backupId) async {
    final b = await findBackup(backupId);
    if (b.status != 'completed' || (b.filePath?.isEmpty ?? true)) {
      throw HttpException(422, 'Backup is not available to restore.');
    }
    final database = await findDatabase(b.databaseId);
    final instance = await findInstance(database.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to restore.');
    }
    await _enqueue('restore_database', {
      'instanceId': database.instanceId,
      'databaseId': database.id,
      'inputPath': b.filePath,
    });
  }

  Future<void> saveUploadAndRestore(
    int databaseId,
    List<int> bytes,
    String filename,
  ) async {
    final database = await findDatabase(databaseId);
    final instance = await findInstance(database.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to restore.');
    }
    if (bytes.isEmpty) throw HttpException(422, 'Uploaded file is empty.');

    final lower = filename.toLowerCase();
    if (!lower.endsWith('.archive') &&
        !lower.endsWith('.gz') &&
        !lower.endsWith('.archive.gz')) {
      throw HttpException(
          422, 'Upload must be a mongodump .archive or .archive.gz file.');
    }
    final ext = lower.endsWith('.gz') ? '.archive.gz' : '.archive';

    final dir = Directory('${pgBackupDir()}/uploads');
    await dir.create(recursive: true);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final suffix = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final path = '${dir.path}/mongo-upload-$stamp-$suffix$ext';
    await File(path).writeAsBytes(bytes, flush: true);

    await _enqueue('restore_database', {
      'instanceId': database.instanceId,
      'databaseId': database.id,
      'inputPath': path,
    });
  }

  // ── Backup schedule ─────────────────────────────────────────────────────────

  Future<MongoBackupSchedule> getSchedule(int databaseId) async {
    await findDatabase(databaseId); // validates existence
    final existing =
        await Query<MongoBackupSchedule>(MongoBackupScheduleTable.metadata)
            .where(MongoBackupScheduleTable.databaseId.eq(databaseId))
            .first(_db.context());
    if (existing != null) return existing;
    return Query<MongoBackupSchedule>(MongoBackupScheduleTable.metadata)
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

  Future<MongoBackupSchedule> updateSchedule(
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
    if (frequency != null && !kMongoBackupFrequencies.contains(frequency)) {
      throw HttpException(422, 'Invalid frequency "$frequency".');
    }
    if (scope != null && !kMongoBackupScopes.contains(scope)) {
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

    await Query<MongoBackupSchedule>(MongoBackupScheduleTable.metadata)
        .where(MongoBackupScheduleTable.databaseId.eq(databaseId))
        .update(patch)
        .run(_db.context());
    return getSchedule(databaseId);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _validateIdentifier(String label, String value) {
    final re = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,62}$');
    if (!re.hasMatch(value)) {
      throw HttpException(
          422,
          'Invalid $label "$value". Must start with a letter, contain only '
          'letters, digits and underscores, max 63 chars.');
    }
  }

  Future<void> _patchInstance(int id, Map<String, Object?> data) =>
      Query<MongoInstance>(MongoInstanceTable.metadata)
          .where(MongoInstanceTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _patchDatabase(int id, Map<String, Object?> data) =>
      Query<MongoDatabase>(MongoDatabaseTable.metadata)
          .where(MongoDatabaseTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _enqueue(String action, Map<String, Object?> payload) =>
      RedisClient.instance.rpush(
        'gisila:queue:mongo',
        jsonEncode({'action': action, ...payload}),
      );
}
