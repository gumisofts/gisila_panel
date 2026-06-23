import 'dart:async';
import 'dart:convert';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/postgres_service.dart' show computeNextRun;

/// Self-driven [Timer] loop that fires due database-backup schedules.
///
/// Every [interval] it looks for enabled [PostgresBackupSchedule]s whose
/// `next_run_at` has fallen due, enqueues a `backup_database` job for each
/// (the [PostgresWorker] does the actual dump + retention), and advances
/// `next_run_at` to the following slot. Mirrors the MetricsCollector pattern.
class BackupScheduler {
  BackupScheduler(
    this.database, {
    this.interval = const Duration(seconds: 60),
  });

  final Database database;
  final Duration interval;

  Timer? _timer;
  var _ticking = false;

  void start() {
    logger.i('backup_scheduler: started (every ${interval.inSeconds}s)');
    _timer = Timer.periodic(interval, (_) => _safeTick());
    _safeTick();
  }

  void stop() => _timer?.cancel();

  Future<void> _safeTick() async {
    if (_ticking) return; // never overlap ticks
    _ticking = true;
    try {
      await _tick();
    } catch (e, st) {
      logger.w('backup_scheduler: tick failed: $e', stackTrace: st);
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tick() async {
    final now = DateTime.now().toUtc();

    final pgSchedules =
        await Query<PostgresBackupSchedule>(PostgresBackupScheduleTable.metadata)
            .where(PostgresBackupScheduleTable.enabled.eq(true))
            .all(database.context());
    for (final s in pgSchedules) {
      final due = s.nextRunAt;
      if (due == null || due.toUtc().isAfter(now)) continue;
      try {
        await _fire(s, now);
      } catch (e) {
        logger.w('backup_scheduler: firing pg schedule #${s.id} failed: $e');
      }
    }

    final mongoSchedules =
        await Query<MongoBackupSchedule>(MongoBackupScheduleTable.metadata)
            .where(MongoBackupScheduleTable.enabled.eq(true))
            .all(database.context());
    for (final s in mongoSchedules) {
      final due = s.nextRunAt;
      if (due == null || due.toUtc().isAfter(now)) continue;
      try {
        await _fireMongo(s, now);
      } catch (e) {
        logger.w('backup_scheduler: firing mongo schedule #${s.id} failed: $e');
      }
    }
  }

  Future<void> _fire(PostgresBackupSchedule s, DateTime now) async {
    final db = await Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
        .where(PostgresDatabaseTable.id.eq(s.databaseId))
        .first(database.context());

    // Always advance next_run_at first so a transient skip doesn't wedge the
    // schedule on a past timestamp (which would fire every tick).
    final next = computeNextRun(
      s.frequency ?? 'daily',
      s.hour ?? 2,
      s.minute ?? 0,
      s.weekday,
      now,
    );
    await Query<PostgresBackupSchedule>(PostgresBackupScheduleTable.metadata)
        .where(PostgresBackupScheduleTable.id.eq(s.id))
        .update({'nextRunAt': next.toIso8601String()}).run(database.context());

    // Skip the dump when the database isn't ready, but keep the schedule live.
    if (db == null || db.status != 'active') {
      logger.i('backup_scheduler: db #${s.databaseId} not active — skipping run');
      return;
    }

    final scope = s.scope ?? 'full';
    final backup = await Query<PostgresBackup>(PostgresBackupTable.metadata)
        .insert(<String, Object?>{
      'databaseId': s.databaseId,
      'scope': scope,
      'status': 'pending',
      'trigger': 'scheduled',
      'createdAt': now.toIso8601String(),
    }).one(database.context());

    await RedisClient.instance.rpush(
      'gisila:queue:postgres',
      jsonEncode({
        'action': 'backup_database',
        'instanceId': db.instanceId,
        'databaseId': s.databaseId,
        'backupId': backup.id,
      }),
    );
    logger.i('backup_scheduler: queued $scope backup for db #${s.databaseId}');
  }

  Future<void> _fireMongo(MongoBackupSchedule s, DateTime now) async {
    final db = await Query<MongoDatabase>(MongoDatabaseTable.metadata)
        .where(MongoDatabaseTable.id.eq(s.databaseId))
        .first(database.context());

    // Advance next_run_at first so a transient skip doesn't wedge the schedule.
    final next = computeNextRun(
      s.frequency ?? 'daily',
      s.hour ?? 2,
      s.minute ?? 0,
      s.weekday,
      now,
    );
    await Query<MongoBackupSchedule>(MongoBackupScheduleTable.metadata)
        .where(MongoBackupScheduleTable.id.eq(s.id))
        .update({'nextRunAt': next.toIso8601String()}).run(database.context());

    if (db == null || db.status != 'active') {
      logger.i(
          'backup_scheduler: mongo db #${s.databaseId} not active — skipping run');
      return;
    }

    final scope = s.scope ?? 'full';
    final backup = await Query<MongoBackup>(MongoBackupTable.metadata)
        .insert(<String, Object?>{
      'databaseId': s.databaseId,
      'scope': scope,
      'status': 'pending',
      'trigger': 'scheduled',
      'createdAt': now.toIso8601String(),
    }).one(database.context());

    await RedisClient.instance.rpush(
      'gisila:queue:mongo',
      jsonEncode({
        'action': 'backup_database',
        'instanceId': db.instanceId,
        'databaseId': s.databaseId,
        'backupId': backup.id,
      }),
    );
    logger.i(
        'backup_scheduler: queued mongo backup for db #${s.databaseId}');
  }
}
