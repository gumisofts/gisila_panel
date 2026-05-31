import 'dart:convert';
import 'dart:math';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';

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
      throw HttpException(409, 'PostgreSQL $version is already installed.');
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
