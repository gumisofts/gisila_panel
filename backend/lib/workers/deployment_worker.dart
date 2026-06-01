import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';

/// Bridge between the Dart worker and the privileged `gisila-agent` CLI.
///
/// Tasks are routed by queue name to specialised handlers. Everything
/// happens through `gisila-agent` so the worker itself never needs root.
class DeploymentWorker {
  DeploymentWorker(this.database);

  final Database database;

  // ── Queue handlers ─────────────────────────────────────────────────

  Future<void> onDeployment(Map<String, Object?> payload) async {
    final deploymentId = payload['deploymentId'] as int?;
    final appId = payload['appId'] as int?;
    if (deploymentId == null || appId == null) return;

    final app = await _findApp(appId);
    if (app == null) return;

    await _publishBuildLog(
      deploymentId,
      stream: 'system',
      line: 'Deployment #$deploymentId started for app ${app.name}.',
    );
    await _markStatus(deploymentId, 'building');

    // Resolve the deploy key private key (if any) to a temp file.
    File? keyFile;
    try {
      if (app.deployKeyId != null) {
        final key = await Query<SshKey>(SshKeyTable.metadata)
            .where(SshKeyTable.id.eq(app.deployKeyId!))
            .first(database.context());
        if (key?.privateKey != null) {
          final tmp = await Directory.systemTemp.createTemp('gisila_dk_');
          keyFile = File('${tmp.path}/id');
          await keyFile.writeAsString(key!.privateKey!);
          await Process.run('chmod', ['600', keyFile.path]);
        }
      }
    } catch (e) {
      logger.w('worker: could not write deploy key to tmp file: $e');
    }

    try {
      // 1. Provision (idempotent).
      await _runAgent([
        'provision',
        '--app-id',
        '${app.id}',
        '--user',
        app.linuxUser!,
        '--work-dir',
        app.workDir,
        '--port',
        '${app.internalPort}',
      ], deploymentId: deploymentId);

      // 2. Build / fetch artifact.
      await _runAgent([
        'build',
        '--app-id', '${app.id}',
        '--user', app.linuxUser!,
        '--work-dir', app.workDir,
        '--runtime', app.runtime,
        '--source-type', app.sourceType,
        if (app.gitUrl != null) ...['--git-url', app.gitUrl!],
        if (app.gitBranch != null) ...['--git-branch', app.gitBranch!],
        if (app.buildCommand != null && app.buildCommand!.isNotEmpty) ...[
          '--build-command',
          app.buildCommand!
        ],
        // SSH deploy key for authenticated git clone.
        if (keyFile != null) ...['--deploy-key-path', keyFile.path],
        // Python-specific build options.
        if (app.runtime == 'python' && app.pythonVersion != null) ...[
          '--python-version',
          app.pythonVersion!
        ],
      ], deploymentId: deploymentId);

      // 3. Generate systemd + AppArmor + nginx vhost (idempotent).
      await _runAgent([
        'apply-unit',
        '--app-id', '${app.id}',
        '--user', app.linuxUser!,
        '--work-dir', app.workDir,
        '--port', '${app.internalPort}',
        '--runtime', app.runtime,
        if (app.startCommand != null) ...['--start-command', app.startCommand!],
        '--memory-mb', '${app.memoryMbLimit ?? 256}',
        '--cpu-quota', '${app.cpuQuotaPercent ?? 50}',
        '--tasks-max', '${app.tasksLimit ?? 100}',
        // Python-specific unit options.
        if (app.runtime == 'python') ...[
          '--python-mode',
          app.pythonMode ?? 'wsgi',
          if (app.wsgiApp != null) ...['--wsgi-app', app.wsgiApp!],
          if (app.gunicornWorkers != null) ...[
            '--workers',
            '${app.gunicornWorkers}',
          ],
          if (app.gunicornThreads != null) ...[
            '--gunicorn-threads',
            '${app.gunicornThreads}',
          ],
          if (app.gunicornTimeout != null) ...[
            '--gunicorn-timeout',
            '${app.gunicornTimeout}',
          ],
          if (app.gunicornBind != null && app.gunicornBind!.isNotEmpty) ...[
            '--gunicorn-bind',
            app.gunicornBind!,
          ],
          if (app.gunicornExtraArgs != null &&
              app.gunicornExtraArgs!.isNotEmpty) ...[
            '--gunicorn-extra-args',
            app.gunicornExtraArgs!,
          ],
        ],
      ], deploymentId: deploymentId);

      await _runAgent([
        'apply-vhost',
        '--app-id',
        '${app.id}',
        '--port',
        '${app.internalPort}',
      ], deploymentId: deploymentId);

      // 4. Start / restart the service.
      await _runAgent(['restart', '--user', app.linuxUser!],
          deploymentId: deploymentId);

      await _markStatus(deploymentId, 'succeeded', activate: true, app: app);
      await _publishBuildLog(deploymentId,
          stream: 'system', line: 'Deployment succeeded.');
    } catch (e, st) {
      logger.e('worker: deployment failed', error: e, stackTrace: st);
      await _markStatus(deploymentId, 'failed', reason: e.toString());
      await _publishBuildLog(deploymentId,
          stream: 'stderr', line: 'FAILED: $e');
    } finally {
      // Clean up temporary deploy key file.
      if (keyFile != null) {
        try {
          await keyFile.parent.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> onLifecycle(Map<String, Object?> payload) async {
    final appId = payload['appId'] as int?;
    final action = payload['action'] as String?;
    if (appId == null || action == null) return;

    final app = await _findApp(appId);
    if (app == null) return;

    final agentAction = switch (action) {
      'start' => 'start',
      'stop' => 'stop',
      'restart' => 'restart',
      _ => null,
    };
    if (agentAction == null) return;

    await _runAgent([agentAction, '--user', app.linuxUser!]);
    await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(app.id!))
        .update(<String, Object?>{
      'status': action == 'stop' ? 'stopped' : 'running',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }).run(database.context());
  }

  Future<void> onVhost(Map<String, Object?> payload) async {
    final appId = payload['appId'] as int?;
    if (appId == null) return;
    final app = await _findApp(appId);
    if (app == null) return;
    await _runAgent([
      'apply-vhost',
      '--app-id',
      '${app.id}',
      '--port',
      '${app.internalPort}',
    ]);
  }

  Future<void> onSsl(Map<String, Object?> payload) async {
    final domainId = payload['domainId'] as int?;
    final hostname = payload['hostname'] as String?;
    if (domainId == null || hostname == null) return;

    try {
      await _runAgent(['issue-cert', '--hostname', hostname]);
      await Query<Domain>(DomainTable.metadata)
          .where(DomainTable.id.eq(domainId))
          .update(<String, Object?>{
        'sslStatus': 'issued',
        'sslIssuer': 'Let\'s Encrypt',
        'sslExpiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(days: 90))
            .toIso8601String(),
      }).run(database.context());
    } catch (e) {
      await Query<Domain>(DomainTable.metadata)
          .where(DomainTable.id.eq(domainId))
          .update(<String, Object?>{
        'sslStatus': 'failed',
      }).run(database.context());
      rethrow;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  Future<App?> _findApp(int appId) => Query<App>(AppTable.metadata)
      .where(AppTable.id.eq(appId))
      .first(database.context());

  Future<void> _markStatus(
    int deploymentId,
    String status, {
    String? reason,
    bool activate = false,
    App? app,
  }) async {
    final now = DateTime.now().toUtc();
    final patch = <String, Object?>{
      'status': status,
      if (status == 'building' || status == 'deploying')
        'startedAt': now.toIso8601String(),
      if (status == 'succeeded' || status == 'failed')
        'finishedAt': now.toIso8601String(),
      if (reason != null) 'failureReason': reason,
      if (activate) 'isActive': true,
    };
    await Query<Deployment>(DeploymentTable.metadata)
        .where(DeploymentTable.id.eq(deploymentId))
        .update(patch)
        .run(database.context());

    if (activate && app != null) {
      await Query<Deployment>(DeploymentTable.metadata)
          .where(DeploymentTable.appId.eq(app.id!))
          .where(DeploymentTable.id.neq(deploymentId))
          .update(<String, Object?>{'isActive': false}).run(database.context());
      await Query<App>(AppTable.metadata)
          .where(AppTable.id.eq(app.id!))
          .update(<String, Object?>{
        'status': 'running',
        'lastDeployedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      }).run(database.context());
    }
  }

  Future<void> _publishBuildLog(
    int deploymentId, {
    required String stream,
    required String line,
  }) async {
    await Query<BuildLog>(BuildLogTable.metadata).insert(<String, Object?>{
      'deploymentId': deploymentId,
      'line': line,
      'stream': stream,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).run(database.context());
    await RedisClient.instance.publish(
      'gisila:logs:build:$deploymentId',
      jsonEncode({'stream': stream, 'line': line}),
    );
  }

  Future<void> _runAgent(
    List<String> args, {
    int? deploymentId,
  }) async {
    // Dev-only simulation: log what would be called, do nothing real.
    if (hostConfig.agentMode == 'dev') {
      final line = 'agent (dev) ${args.join(' ')}';
      logger.i('worker: $line');
      if (deploymentId != null) {
        await _publishBuildLog(deploymentId, stream: 'system', line: line);
      }
      return;
    }

    final cmd = buildAgentCmd(args);
    logger.i('worker: agent ${cmd.join(' ')}');
    final process = await Process.start(cmd.first, cmd.skip(1).toList());

    final outputs = await Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
        if (deploymentId != null) {
          _publishBuildLog(deploymentId, stream: 'stdout', line: line);
        }
        return line;
      }).toList(),
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
        if (deploymentId != null) {
          _publishBuildLog(deploymentId, stream: 'stderr', line: line);
        }
        return line;
      }).toList(),
    ]);

    final exit = await process.exitCode;
    if (exit != 0) {
      throw StateError(
        'agent exited with $exit: ${outputs[1].join("\\n")}',
      );
    }
  }
}
