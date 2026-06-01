import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';

/// Handles async PostgreSQL jobs from the [gisila:queue:postgres] queue.
///
/// Actions: install_instance | uninstall_instance | start_instance |
///          stop_instance | create_database | drop_database
class PostgresWorker {
  PostgresWorker(this.database);

  final Database database;

  Future<void> onPostgresJob(Map<String, Object?> payload) async {
    final action = payload['action'] as String?;
    if (action == null) return;

    switch (action) {
      case 'install_instance':
        await _installInstance(payload['instanceId'] as int);
      case 'uninstall_instance':
        await _uninstallInstance(payload['instanceId'] as int);
      case 'start_instance':
        await _startInstance(payload['instanceId'] as int);
      case 'stop_instance':
        await _stopInstance(payload['instanceId'] as int);
      case 'create_database':
        await _createDatabase(
          payload['instanceId'] as int,
          payload['databaseId'] as int,
        );
      case 'drop_database':
        await _dropDatabase(
          payload['instanceId'] as int,
          payload['databaseId'] as int,
        );
      default:
        logger.w('postgres_worker: unknown action $action — skipping');
    }
  }

  // ── Instance lifecycle ────────────────────────────────────────────────────

  Future<void> _installInstance(int instanceId) async {
    await _patchInstance(instanceId, {'status': 'installing'});
    try {
      final instance = await _findInstance(instanceId);
      if (instance == null) return;

      await _runAgent([
        'postgres',
        'install-instance',
        '--version',
        '${instance.version}',
        '--port',
        '${instance.port}',
      ]);

      await _patchInstance(instanceId, {
        'status': 'running',
        'installedAt': DateTime.now().toUtc().toIso8601String(),
        'errorMessage': null,
      });
    } catch (e) {
      // Attempt best-effort rollback to avoid leaving a partially-installed
      // PostgreSQL package on the host.
      final instance = await _findInstance(instanceId);
      if (instance != null) {
        try {
          await _runAgent([
            'postgres',
            'uninstall-instance',
            '--version',
            '${instance.version}',
          ]);
        } catch (rollbackErr) {
          logger.w(
              'postgres_worker: rollback uninstall failed (ignored): $rollbackErr');
        }
      }
      await _patchInstance(instanceId, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _uninstallInstance(int instanceId) async {
    final instance = await _findInstance(instanceId);
    if (instance == null) return;

    try {
      await _runAgent([
        'postgres',
        'uninstall-instance',
        '--version',
        '${instance.version}',
      ]);
    } catch (e) {
      // Log but do not re-throw: the package may not be installed if a previous
      // install attempt failed. The intent is removal, so always delete the record.
      logger.w(
          'postgres_worker: agent uninstall-instance error (continuing): $e');
    }

    // Hard-delete the instance record regardless of agent result.
    await Query<PostgresInstance>(PostgresInstanceTable.metadata)
        .where(PostgresInstanceTable.id.eq(instanceId))
        .delete()
        .run(database.context());
  }

  Future<void> _startInstance(int instanceId) async {
    try {
      final instance = await _findInstance(instanceId);
      if (instance == null) return;

      await _runAgent([
        'postgres',
        'start-instance',
        '--version',
        '${instance.version}',
      ]);
      await _patchInstance(
          instanceId, {'status': 'running', 'errorMessage': null});
    } catch (e) {
      await _patchInstance(instanceId, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _stopInstance(int instanceId) async {
    try {
      final instance = await _findInstance(instanceId);
      if (instance == null) return;

      await _runAgent([
        'postgres',
        'stop-instance',
        '--version',
        '${instance.version}',
      ]);
      await _patchInstance(instanceId, {'status': 'stopped'});
    } catch (e) {
      await _patchInstance(instanceId, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  // ── Database lifecycle ────────────────────────────────────────────────────

  Future<void> _createDatabase(int instanceId, int databaseId) async {
    try {
      final instance = await _findInstance(instanceId);
      final db = await _findDatabase(databaseId);
      if (instance == null || db == null) return;

      final extensions = <String>[];
      try {
        final decoded = jsonDecode(db.extensions ?? '[]');
        if (decoded is List) extensions.addAll(decoded.cast<String>());
      } catch (_) {}

      await _runAgent([
        'postgres',
        'create-db',
        '--version',
        '${instance.version}',
        '--db',
        db.dbName,
        '--role',
        db.roleName,
        '--password',
        db.password,
        if (extensions.isNotEmpty) ...[
          '--extensions',
          extensions.join(','),
        ],
      ]);

      await _patchDatabase(databaseId, {
        'status': 'active',
        'errorMessage': null,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      await _patchDatabase(databaseId, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _dropDatabase(int instanceId, int databaseId) async {
    final instance = await _findInstance(instanceId);
    final db = await _findDatabase(databaseId);
    if (instance == null || db == null) return;

    try {
      await _runAgent([
        'postgres',
        'drop-db',
        '--version',
        '${instance.version}',
        '--db',
        db.dbName,
        '--role',
        db.roleName,
      ]);
    } catch (e) {
      // Log but do not re-throw: the database may not exist on the server if
      // creation previously failed. Always delete the record.
      logger.w('postgres_worker: agent drop-db error (continuing): $e');
    }

    // Hard-delete the database record regardless of agent result.
    await Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
        .where(PostgresDatabaseTable.id.eq(databaseId))
        .delete()
        .run(database.context());
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<PostgresInstance?> _findInstance(int id) =>
      Query<PostgresInstance>(PostgresInstanceTable.metadata)
          .where(PostgresInstanceTable.id.eq(id))
          .first(database.context());

  Future<PostgresDatabase?> _findDatabase(int id) =>
      Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
          .where(PostgresDatabaseTable.id.eq(id))
          .first(database.context());

  Future<void> _patchInstance(int id, Map<String, Object?> data) =>
      Query<PostgresInstance>(PostgresInstanceTable.metadata)
          .where(PostgresInstanceTable.id.eq(id))
          .update(data)
          .run(database.context());

  Future<void> _patchDatabase(int id, Map<String, Object?> data) =>
      Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
          .where(PostgresDatabaseTable.id.eq(id))
          .update(data)
          .run(database.context());

  Future<void> _runAgent(List<String> args) async {
    if (hostConfig.agentMode == 'dev') {
      logger.i('postgres_worker (dev): agent ${args.join(' ')}');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return;
    }

    // When AGENT_BIN=dart, call: dart run <entry> <args>
    // When AGENT_MODE=sudo, prepend sudo.
    final List<String> cmd;
    if (hostConfig.agentBin == 'dart') {
      cmd = ['dart', 'run', hostConfig.agentDartEntry, ...args];
    } else if (hostConfig.agentMode == 'sudo') {
      cmd = ['sudo', '--non-interactive', hostConfig.agentBin, ...args];
    } else {
      cmd = [hostConfig.agentBin, ...args];
    }

    logger.i('postgres_worker: ${cmd.join(' ')}');
    final result = await Process.run(cmd.first, cmd.skip(1).toList());
    if (result.exitCode != 0) {
      throw Exception(
        'Agent exited ${result.exitCode}: ${result.stderr}'.trim(),
      );
    }
  }
}
