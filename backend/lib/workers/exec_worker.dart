import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';

/// Runs one-off commands inside an app's environment (queue `gisila:queue:exec`).
///
/// Output is streamed live to a per-execution Redis channel
/// (`gisila:logs:exec:<execId>`) and buffered into a capped history list, exactly
/// like the service-install logs, so the panel's Console can replay + tail it.
/// A trailing `__EXIT__:<code>` system line signals completion to the client.
class ExecWorker {
  ExecWorker(this.database);

  final Database database;

  Future<void> onExecJob(Map<String, Object?> payload) async {
    final appId = payload['appId'] as int?;
    final execId = payload['execId'] as String?;
    final command = payload['command'] as String?;
    if (appId == null || execId == null || command == null) return;

    final app = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(appId))
        .first(database.context());

    await _log(execId, 'system', '\$ $command');

    if (app == null || app.linuxUser == null) {
      await _log(execId, 'stderr',
          'App is not provisioned yet — deploy it before running commands.');
      await _log(execId, 'system', '__EXIT__:1');
      return;
    }

    try {
      final exit = await _runAgent([
        'exec',
        '--user', app.linuxUser!,
        '--work-dir', app.workDir,
        '--runtime', app.runtime,
        '--command', command,
      ], execId);
      await _log(execId, 'system', '__EXIT__:$exit');
    } catch (e) {
      await _log(execId, 'stderr', 'Execution failed: $e');
      await _log(execId, 'system', '__EXIT__:1');
    }
  }

  /// Run the agent, streaming each output line to the exec log channel.
  /// Returns the agent's exit code.
  Future<int> _runAgent(List<String> args, String execId) async {
    if (hostConfig.agentMode == 'dev') {
      await _log(execId, 'stdout',
          '(dev mode) would run: gisila-agent ${args.join(' ')}');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return 0;
    }

    final cmd = buildAgentCmd(args);
    logger.i('exec_worker: ${cmd.join(' ')}');
    final process = await Process.start(cmd.first, cmd.skip(1).toList());

    await Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) => _log(execId, 'stdout', line)),
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) => _log(execId, 'stderr', line)),
    ]);

    return process.exitCode;
  }

  // ── Live log streaming (mirrors ServiceWorker) ──────────────────────────────

  String _historyKey(String execId) => 'gisila:logs:exec:$execId:history';
  String _channel(String execId) => 'gisila:logs:exec:$execId';

  Future<void> _log(String execId, String stream, String line) async {
    final payload = jsonEncode({'stream': stream, 'line': line});
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
