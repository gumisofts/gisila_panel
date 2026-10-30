import 'dart:async';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/cron_service.dart';
import 'package:gisila_panel/utils/cron.dart';

/// Self-driven [Timer] loop that fires due app cron jobs (see [CronService]).
///
/// Each tick claims every enabled job whose `next_run_at` has passed by
/// moving `next_run_at` to the following slot in one conditional UPDATE, so
/// two workers never fire the same slot. A slot missed while the worker was
/// down runs once, not once per missed slot. A job whose previous run is
/// still going is skipped for that slot rather than run twice at once.
class CronScheduler {
  CronScheduler(
    this.database, {
    this.interval = const Duration(seconds: 30),
  });

  final Database database;
  final Duration interval;

  Timer? _timer;
  var _ticking = false;

  /// Runs still `running` this long past their timeout were lost (a worker
  /// restart drops queued exec jobs on purpose) and are marked failed.
  static const _lostAfter = Duration(minutes: 5);

  void start() {
    logger.i('cron_scheduler: started (every ${interval.inSeconds}s)');
    _timer = Timer.periodic(interval, (_) => _safeTick());
    _safeTick();
  }

  void stop() => _timer?.cancel();

  Future<void> _safeTick() async {
    if (_ticking) return; // never overlap ticks
    _ticking = true;
    try {
      await tick();
    } catch (e, st) {
      logger.w('cron_scheduler: tick failed: $e', stackTrace: st);
    } finally {
      _ticking = false;
    }
  }

  Future<void> tick() async {
    final c = database.context();
    final now = DateTime.now().toUtc();

    await c.execute(
      "UPDATE app_cron_runs r SET status = 'failed', finished_at = now(), "
      "output_tail = coalesce(output_tail, '') || "
      "'The run was lost (the worker restarted while it was queued or "
      "running).' "
      'FROM app_cron_jobs j WHERE r.job_id = j.id '
      "AND r.status = 'running' AND r.started_at < now() - "
      "make_interval(secs => j.timeout_seconds + \$1)",
      parameters: [_lostAfter.inSeconds],
    );

    final due = await c.execute(
      'SELECT * FROM app_cron_jobs WHERE enabled AND next_run_at <= \$1',
      parameters: [now],
    );
    for (final row in due) {
      final job = row.toColumnMap();
      try {
        await _fire(job, now);
      } catch (e) {
        logger.w('cron_scheduler: job #${job['id']} failed to fire: $e');
      }
    }
  }

  Future<void> _fire(Map<String, Object?> job, DateTime now) async {
    final c = database.context();
    DateTime? next;
    try {
      next = CronSchedule.parse(job['schedule'] as String).next(now);
    } on FormatException {
      next = null; // stored before a parser change: stop rather than spin
    }
    final claimed = await c.execute(
      'UPDATE app_cron_jobs SET next_run_at = \$3, enabled = \$4 '
      'WHERE id = \$1 AND next_run_at = \$2 RETURNING id',
      parameters: [job['id'], job['next_run_at'], next, next != null],
    );
    if (claimed.isEmpty) return; // another worker took this slot

    final app = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(job['app_id'] as int))
        .first(c);
    if (app == null) return;

    Future<void> skip(String why) async {
      final rows = await c.execute(
        "INSERT INTO app_cron_runs (job_id, status, finished_at) "
        "VALUES (\$1, 'skipped', now()) RETURNING id",
        parameters: [job['id']],
      );
      await CronService.finishRun(database, rows.first.toColumnMap()['id'] as int,
          status: 'skipped', output: why);
    }

    if (app.linuxUser == null) {
      await skip('The app is not deployed yet.');
      return;
    }
    final running = await c.execute(
      "SELECT 1 FROM app_cron_runs WHERE job_id = \$1 AND status = 'running'",
      parameters: [job['id']],
    );
    if (running.isNotEmpty) {
      await skip('The previous run was still going.');
      return;
    }
    await CronService.startRun(database, app, job, trigger: 'schedule');
    logger.i('cron_scheduler: started job #${job['id']} for app #${app.id}');
  }
}
