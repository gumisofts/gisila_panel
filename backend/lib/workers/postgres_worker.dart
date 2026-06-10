import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/postgres_service.dart'
    show generatePassword, pgBackupDir;

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
      case 'ensure_monitor':
        await _ensureMonitor(payload['instanceId'] as int);
      case 'configure_instance':
        await _configureInstance(
          payload['instanceId'] as int,
          payload['settings'],
        );
      case 'backup_database':
        await _backupDatabase(
          payload['instanceId'] as int,
          payload['databaseId'] as int,
          payload['backupId'] as int,
        );
      case 'restore_database':
        await _restoreDatabase(
          payload['instanceId'] as int,
          payload['databaseId'] as int,
          payload['inputPath'] as String,
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

      // Provision the read-only monitoring role used by the metrics endpoint.
      final monitorPassword = generatePassword();
      await _patchInstance(instanceId, {
        'status': 'running',
        'installedAt': DateTime.now().toUtc().toIso8601String(),
        'errorMessage': null,
        'monitorPassword': monitorPassword,
      });
      try {
        await _runAgent([
          'postgres',
          'ensure-monitor',
          '--version',
          '${instance.version}',
          '--port',
          '${instance.port}',
          '--password',
          monitorPassword,
        ]);
      } catch (e) {
        logger.w('postgres_worker: monitor role provisioning failed: $e');
      }
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

    // Remove all of this instance's backup files (rows cascade via the FK).
    await _deleteDir('${pgBackupDir()}/$instanceId');
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

  Future<void> _ensureMonitor(int instanceId) async {
    final instance = await _findInstance(instanceId);
    if (instance == null) return;
    final password = instance.monitorPassword;
    if (password == null || password.isEmpty) {
      logger.w('postgres_worker: ensure_monitor with no password — skipping');
      return;
    }
    try {
      await _runAgent([
        'postgres',
        'ensure-monitor',
        '--version',
        '${instance.version}',
        '--port',
        '${instance.port}',
        '--password',
        password,
      ]);
    } catch (e) {
      logger.w('postgres_worker: ensure-monitor failed (will retry): $e');
    }
  }

  Future<void> _configureInstance(int instanceId, Object? settings) async {
    final instance = await _findInstance(instanceId);
    if (instance == null) return;
    try {
      final json = jsonEncode(settings is Map ? settings : <String, Object?>{});
      await _runAgent([
        'postgres',
        'configure',
        '--version',
        '${instance.version}',
        '--port',
        '${instance.port}',
        '--settings',
        json,
      ]);
      await _patchInstance(instanceId, {
        'status': 'running',
        'errorMessage': null,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
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

    // Best-effort removal of this database's backup files (rows cascade away
    // with the database record via the FK).
    await _deleteDir('${pgBackupDir()}/$instanceId/${db.dbName}');
  }

  // ── Backups ───────────────────────────────────────────────────────────────

  Future<void> _backupDatabase(
      int instanceId, int databaseId, int backupId) async {
    await _patchBackup(backupId, {
      'status': 'running',
      'startedAt': DateTime.now().toUtc().toIso8601String(),
    });
    try {
      final instance = await _findInstance(instanceId);
      final db = await _findDatabase(databaseId);
      final backup = await _findBackup(backupId);
      if (instance == null || db == null || backup == null) return;

      final scope = backup.scope ?? 'full';
      final fileName = '${db.dbName}-${_stamp(DateTime.now().toUtc())}'
          '-$scope.sql.gz';
      final path = '${pgBackupDir()}/$instanceId/${db.dbName}/$fileName';

      await _runAgent([
        'postgres',
        'backup',
        '--version',
        '${instance.version}',
        '--db',
        db.dbName,
        '--output',
        path,
        '--scope',
        scope,
      ]);

      int? size;
      if (hostConfig.agentMode == 'dev') {
        // Dev mode stubs the agent — drop a placeholder so the row completes
        // and the download endpoint has something to serve.
        try {
          final f = File(path);
          await f.parent.create(recursive: true);
          await f.writeAsString(
              '-- gisila dev backup placeholder: ${db.dbName} ($scope)\n');
          size = await f.length();
        } catch (_) {}
      } else {
        try {
          size = await File(path).length();
        } catch (_) {}
      }

      await _patchBackup(backupId, {
        'status': 'completed',
        'filePath': path,
        'fileName': fileName,
        if (size != null) 'sizeBytes': size,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
        'errorMessage': null,
      });

      await _pruneBackups(databaseId);
    } catch (e) {
      await _patchBackup(backupId, {
        'status': 'failed',
        'errorMessage': e.toString(),
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
      rethrow;
    }
  }

  Future<void> _restoreDatabase(
      int instanceId, int databaseId, String inputPath) async {
    final instance = await _findInstance(instanceId);
    final db = await _findDatabase(databaseId);
    if (instance == null || db == null) return;
    try {
      await _runAgent([
        'postgres',
        'restore',
        '--version',
        '${instance.version}',
        '--db',
        db.dbName,
        '--input',
        inputPath,
      ]);
    } finally {
      // Staged uploads are single-use — remove them whatever the outcome.
      if (inputPath.contains('/uploads/')) {
        try {
          final f = File(inputPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Enforce the schedule's keep-last-N retention for a database.
  Future<void> _pruneBackups(int databaseId) async {
    final sched =
        await Query<PostgresBackupSchedule>(PostgresBackupScheduleTable.metadata)
            .where(PostgresBackupScheduleTable.databaseId.eq(databaseId))
            .first(database.context());
    final keep = sched?.keepCount ?? 7;

    final all = await Query<PostgresBackup>(PostgresBackupTable.metadata)
        .where(PostgresBackupTable.databaseId.eq(databaseId))
        .orderBy(PostgresBackupTable.createdAt, desc: true)
        .all(database.context());
    final completed = all.where((b) => b.status == 'completed').toList();
    if (completed.length <= keep) return;

    for (final old in completed.skip(keep)) {
      final p = old.filePath;
      if (p != null && p.isNotEmpty) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      await Query<PostgresBackup>(PostgresBackupTable.metadata)
          .where(PostgresBackupTable.id.eq(old.id))
          .delete()
          .run(database.context());
    }
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

  Future<PostgresBackup?> _findBackup(int id) =>
      Query<PostgresBackup>(PostgresBackupTable.metadata)
          .where(PostgresBackupTable.id.eq(id))
          .first(database.context());

  Future<void> _patchBackup(int id, Map<String, Object?> data) =>
      Query<PostgresBackup>(PostgresBackupTable.metadata)
          .where(PostgresBackupTable.id.eq(id))
          .update(data)
          .run(database.context());

  /// Compact UTC timestamp `yyyymmdd-HHMMSS` for backup file names.
  String _stamp(DateTime t) {
    String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return '${p(t.year, 4)}${p(t.month)}${p(t.day)}-'
        '${p(t.hour)}${p(t.minute)}${p(t.second)}';
  }

  /// Best-effort recursive directory removal (used to clean up backup files).
  Future<void> _deleteDir(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      logger.w('postgres_worker: could not remove $path: $e');
    }
  }

  Future<void> _runAgent(List<String> args) async {
    if (hostConfig.agentMode == 'dev') {
      logger.i('postgres_worker (dev): agent ${args.join(' ')}');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return;
    }

    final cmd = buildAgentCmd(args);
    logger.i('postgres_worker: ${cmd.join(' ')}');
    final result = await Process.run(cmd.first, cmd.skip(1).toList());
    if (result.exitCode != 0) {
      throw Exception(
        'Agent exited ${result.exitCode}: ${result.stderr}'.trim(),
      );
    }
  }
}
