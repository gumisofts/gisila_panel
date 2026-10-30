import 'dart:convert';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';
import 'package:gisila_panel/utils/cron.dart';
import 'package:uuid/uuid.dart';

/// Scheduled commands per app. Jobs run through the same exec path as the
/// app console (as the app's Linux user, with its env and toolchain), so
/// managing them needs the same `developer` role. Team members with a lower
/// role can see the jobs but not the commands' output.
class CronService extends Service {
  Database get _db => db<Database>();

  /// Jobs one app may have.
  static const maxJobsPerApp = 20;

  /// Runs kept per job; older ones are deleted as new ones finish.
  static const runsKept = 50;

  Future<List<Map<String, Object?>>> list(User actor, int appId) async {
    final app = await (AppsService()..attach(ctx)).findForUser(actor, appId);
    final rows = await _db.context().execute(
      'SELECT * FROM app_cron_jobs WHERE app_id = \$1 ORDER BY id',
      parameters: [app.id],
    );
    return [for (final r in rows) _jobJson(r.toColumnMap())];
  }

  Future<Map<String, Object?>> create(
    User actor,
    int appId, {
    required String name,
    required String schedule,
    required String command,
    int? timeoutSeconds,
    bool? enabled,
  }) async {
    final app = await _requireDeveloper(actor, appId);
    final parsed = _parse(schedule);
    final count = (await _db.context().execute(
      'SELECT count(*)::int AS n FROM app_cron_jobs WHERE app_id = \$1',
      parameters: [app.id],
    ))
        .first
        .toColumnMap()['n'] as int;
    if (count >= maxJobsPerApp) {
      throw BadRequest('An app can have at most $maxJobsPerApp cron jobs.');
    }
    final on = enabled ?? true;
    final rows = await _db.context().execute(
      'INSERT INTO app_cron_jobs (app_id, name, schedule, command, '
      'timeout_seconds, enabled, next_run_at) '
      'VALUES (\$1, \$2, \$3, \$4, \$5, \$6, \$7) RETURNING *',
      parameters: [
        app.id,
        _required(name, 'name'),
        parsed.expression,
        _required(command, 'command'),
        timeoutSeconds ?? 300,
        on,
        on ? parsed.next(DateTime.now().toUtc()) : null,
      ],
    );
    return _jobJson(rows.first.toColumnMap());
  }

  Future<Map<String, Object?>> update(
    User actor,
    int appId,
    int jobId, {
    String? name,
    String? schedule,
    String? command,
    int? timeoutSeconds,
    bool? enabled,
  }) async {
    final app = await _requireDeveloper(actor, appId);
    final job = await _job(app.id!, jobId);
    final parsed = _parse(schedule ?? job['schedule'] as String);
    final on = enabled ?? job['enabled'] as bool;
    // Recompute the next run whenever the schedule or the switch changes.
    final rows = await _db.context().execute(
      'UPDATE app_cron_jobs SET name = \$3, schedule = \$4, command = \$5, '
      'timeout_seconds = \$6, enabled = \$7, next_run_at = \$8, '
      'updated_at = now() WHERE id = \$1 AND app_id = \$2 RETURNING *',
      parameters: [
        jobId,
        app.id,
        name == null ? job['name'] : _required(name, 'name'),
        parsed.expression,
        command == null ? job['command'] : _required(command, 'command'),
        timeoutSeconds ?? job['timeout_seconds'],
        on,
        on ? parsed.next(DateTime.now().toUtc()) : null,
      ],
    );
    return _jobJson(rows.first.toColumnMap());
  }

  Future<void> delete(User actor, int appId, int jobId) async {
    final app = await _requireDeveloper(actor, appId);
    await _job(app.id!, jobId);
    await _db.context().execute(
      'DELETE FROM app_cron_jobs WHERE id = \$1 AND app_id = \$2',
      parameters: [jobId, app.id],
    );
  }

  /// Runs the job now, outside its schedule. Returns the run, whose
  /// `execId` streams live output like a console command.
  Future<Map<String, Object?>> runNow(User actor, int appId, int jobId) async {
    final app = await _requireDeveloper(actor, appId);
    final job = await _job(app.id!, jobId);
    if (app.linuxUser == null) {
      throw BadRequest('Deploy the app before running its cron jobs.');
    }
    final busy = await _db.context().execute(
      "SELECT 1 FROM app_cron_runs WHERE job_id = \$1 AND status = 'running'",
      parameters: [jobId],
    );
    if (busy.isNotEmpty) throw Conflict('This job is already running.');
    return startRun(_db, app, job, trigger: 'manual');
  }

  Future<List<Map<String, Object?>>> runs(
      User actor, int appId, int jobId) async {
    final app = await _requireDeveloper(actor, appId);
    await _job(app.id!, jobId);
    final rows = await _db.context().execute(
      'SELECT * FROM app_cron_runs WHERE job_id = \$1 ORDER BY id DESC '
      'LIMIT $runsKept',
      parameters: [jobId],
    );
    return [for (final r in rows) runJson(r.toColumnMap())];
  }

  /// The next [count] times [schedule] fires, to check it before saving.
  static Map<String, Object?> preview(String schedule, {int count = 5}) {
    final parsed = _parse(schedule);
    return {
      'schedule': parsed.expression,
      'next': [
        for (final t in parsed.upcoming(DateTime.now().toUtc(), count: count))
          t.toIso8601String(),
      ],
    };
  }

  /// Records a `running` run and queues it on the exec queue. Used by
  /// [runNow] and by the worker's CronScheduler.
  static Future<Map<String, Object?>> startRun(
    Database db,
    App app,
    Map<String, Object?> job, {
    required String trigger,
  }) async {
    final execId = const Uuid().v4();
    final rows = await db.context().execute(
      "INSERT INTO app_cron_runs (job_id, exec_id, trigger, status) "
      "VALUES (\$1, \$2, \$3, 'running') RETURNING *",
      parameters: [job['id'], execId, trigger],
    );
    final run = rows.first.toColumnMap();
    try {
      await RedisClient.instance.enqueueJob(
        'gisila:queue:exec',
        jsonEncode({
          'appId': app.id,
          'execId': execId,
          'command': job['command'],
          'timeoutSeconds': job['timeout_seconds'],
          'cronRunId': run['id'],
        }),
      );
    } catch (e) {
      await finishRun(db, run['id'] as int,
          status: 'failed', output: 'Could not queue the run: $e');
      rethrow;
    }
    return runJson(run);
  }

  /// Records how a run ended, updates its job and drops runs beyond
  /// [runsKept].
  static Future<void> finishRun(
    Database db,
    int runId, {
    required String status,
    int? exitCode,
    String? output,
  }) async {
    final c = db.context();
    final rows = await c.execute(
      'UPDATE app_cron_runs SET status = \$2, exit_code = \$3, '
      'output_tail = \$4, finished_at = now() WHERE id = \$1 RETURNING job_id',
      parameters: [runId, status, exitCode, output],
    );
    if (rows.isEmpty) return;
    final jobId = rows.first.toColumnMap()['job_id'];
    await c.execute(
      'UPDATE app_cron_jobs SET last_run_at = now(), last_status = \$2 '
      'WHERE id = \$1',
      parameters: [jobId, status],
    );
    await c.execute(
      'DELETE FROM app_cron_runs WHERE job_id = \$1 AND id NOT IN '
      '(SELECT id FROM app_cron_runs WHERE job_id = \$1 '
      'ORDER BY id DESC LIMIT $runsKept)',
      parameters: [jobId],
    );
  }

  static Map<String, Object?> runJson(Map<String, Object?> r) => {
        'id': r['id'],
        'jobId': r['job_id'],
        'execId': r['exec_id'],
        'trigger': r['trigger'],
        'status': r['status'],
        'exitCode': r['exit_code'],
        'output': r['output_tail'],
        'startedAt': _iso(r['started_at']),
        'finishedAt': _iso(r['finished_at']),
      };

  static Map<String, Object?> _jobJson(Map<String, Object?> r) => {
        'id': r['id'],
        'appId': r['app_id'],
        'name': r['name'],
        'schedule': r['schedule'],
        'command': r['command'],
        'timeoutSeconds': r['timeout_seconds'],
        'enabled': r['enabled'],
        'nextRunAt': _iso(r['next_run_at']),
        'lastRunAt': _iso(r['last_run_at']),
        'lastStatus': r['last_status'],
        'createdAt': _iso(r['created_at']),
      };

  static String? _iso(Object? v) =>
      v is DateTime ? v.toUtc().toIso8601String() : null;

  Future<App> _requireDeveloper(User actor, int appId) =>
      (AppsService()..attach(ctx))
          .requireAppRole(actor, appId, TeamRole.developer);

  Future<Map<String, Object?>> _job(int appId, int jobId) async {
    final rows = await _db.context().execute(
      'SELECT * FROM app_cron_jobs WHERE id = \$1 AND app_id = \$2',
      parameters: [jobId, appId],
    );
    if (rows.isEmpty) throw NotFound('Cron job not found.');
    return rows.first.toColumnMap();
  }

  static CronSchedule _parse(String schedule) {
    try {
      return CronSchedule.parse(schedule);
    } on FormatException catch (e) {
      throw BadRequest(e.message, code: 'invalid_schedule');
    }
  }

  static String _required(String value, String field) {
    final v = value.trim();
    if (v.isEmpty) throw BadRequest('$field must not be empty.');
    return v;
  }
}
