import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/cron_service.dart';

/// Runs one-off commands inside an app's environment (queue `gisila:queue:exec`).
///
/// Output is streamed live to a per-execution Redis channel
/// (`gisila:logs:exec:<execId>`) and buffered into a capped history list, exactly
/// like the service-install logs, so the panel's Console can replay + tail it.
/// Completion is a frame of its own, `{"stream":"system","exit":<code>}`, so
/// nothing the command prints can fake it.
class ExecWorker {
  ExecWorker(this.database);

  final Database database;

  Future<void> onExecJob(Map<String, Object?> payload) async {
    final appId = payload['appId'] as int?;
    final execId = payload['execId'] as String?;
    final command = payload['command'] as String?;
    if (appId == null || execId == null || command == null) return;
    // Set for runs of a cron job (see CronService.startRun).
    final cronRunId = payload['cronRunId'] as int?;
    final timeoutSeconds = payload['timeoutSeconds'] as int?;
    final output = cronRunId == null ? null : <String>[];

    final app = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(appId))
        .first(database.context());

    await _log(execId, 'system', '\$ $command');

    if (app == null || app.linuxUser == null) {
      await _log(execId, 'stderr',
          'App is not provisioned yet — deploy it before running commands.');
      await _exit(execId, 1);
      if (cronRunId != null) {
        await _finishCron(cronRunId, 1, ['App is not deployed yet.']);
      }
      return;
    }

    try {
      final exit = await _runAgent([
        'exec',
        '--user', app.linuxUser!,
        '--work-dir', app.workDir,
        '--runtime', app.runtime,
        if (app.sourceSubdir != null && app.sourceSubdir!.isNotEmpty) ...[
          '--source-subdir',
          app.sourceSubdir!,
        ],
        if (app.runtime == 'dart' && app.dartVersion != null) ...[
          '--dart-version',
          app.dartVersion!,
        ],
        if (app.runtime == 'go' && app.goVersion != null) ...[
          '--go-version',
          app.goVersion!,
        ],
        if (app.runtime == 'node' && app.nodeVersion != null) ...[
          '--node-version',
          app.nodeVersion!,
        ],
        if (app.runtime == 'bun' && app.bunVersion != null) ...[
          '--bun-version',
          app.bunVersion!,
        ],
        if ((app.runtime == 'python' || app.runtime == 'celery') &&
            app.pythonVersion != null) ...[
          '--python-version',
          app.pythonVersion!,
        ],
        if (timeoutSeconds != null) ...['--timeout', '$timeoutSeconds'],
        '--command', command,
      ], execId, output);
      await _exit(execId, exit);
      if (cronRunId != null) await _finishCron(cronRunId, exit, output!);
    } catch (e) {
      await _log(execId, 'stderr', 'Execution failed: $e');
      await _exit(execId, 1);
      if (cronRunId != null) {
        await _finishCron(cronRunId, 1, [...?output, 'Execution failed: $e']);
      }
    }
  }

  /// Lines of output kept with a cron run once the live log expires.
  static const _cronOutputLines = 200;

  Future<void> _finishCron(int runId, int exit, List<String> output) async {
    final timedOut =
        output.any((l) => l.startsWith('[exec] command timed out'));
    try {
      await CronService.finishRun(
        database,
        runId,
        status: timedOut ? 'timed_out' : (exit == 0 ? 'succeeded' : 'failed'),
        exitCode: exit,
        output: output.join('\n'),
      );
    } catch (e) {
      logger.w('exec_worker: could not record cron run #$runId: $e');
    }
  }

  /// Run the agent, streaming each output line to the exec log channel.
  /// Returns the agent's exit code.
  Future<int> _runAgent(
      List<String> args, String execId, List<String>? output) async {
    void keep(String line) {
      if (output == null) return;
      output.add(line);
      if (output.length > _cronOutputLines) output.removeAt(0);
    }

    if (hostConfig.agentMode == 'dev') {
      final line = '(dev mode) would run: gisila-agent ${args.join(' ')}';
      keep(line);
      await _log(execId, 'stdout', line);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return 0;
    }

    final cmd = buildAgentCmd(args);
    logger.i('exec_worker: ${cmd.join(' ')}');
    final process = await Process.start(cmd.first, cmd.skip(1).toList(),
        environment: agentEnvironment, includeParentEnvironment: false);

    await Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        keep(line);
        unawaited(_log(execId, 'stdout', line));
      }),
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
        keep(line);
        unawaited(_log(execId, 'stderr', line));
      }),
    ]);

    return process.exitCode;
  }

  // ── Live log streaming (mirrors ServiceWorker) ──────────────────────────────

  String _historyKey(String execId) => 'gisila:logs:exec:$execId:history';
  String _channel(String execId) => 'gisila:logs:exec:$execId';

  Future<void> _exit(String execId, int code) =>
      _publish(execId, jsonEncode({'stream': 'system', 'exit': code}));

  Future<void> _log(String execId, String stream, String line) =>
      _publish(execId, jsonEncode({'stream': stream, 'line': line}));

  Future<void> _publish(String execId, String payload) async {
    try {
      await RedisClient.instance.rpush(_historyKey(execId), payload);
      await RedisClient.instance.ltrim(_historyKey(execId), -2000, -1);
      await RedisClient.instance.expire(_historyKey(execId), 3600);
      await RedisClient.instance.publish(_channel(execId), payload);
    } catch (e) {
      logger.w('exec_worker: failed to publish log line: $e');
    }
  }
}
