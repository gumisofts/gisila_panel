import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
        // Static apps have no port; only service runtimes get one.
        if (app.internalPort != null) ...['--port', '${app.internalPort}'],
      ], deploymentId: deploymentId);

      // App env vars are needed both by the build (Django migrate/collectstatic
      // must hit the same DB/config as the runtime unit) and by apply-unit
      // below, so fetch them once up front.
      final appEnvVars = await Query<EnvVar>(EnvVarTable.metadata)
          .where(EnvVarTable.appId.eq(app.id!))
          .all(database.context());
      final envMap = {for (final e in appEnvVars) e.name: e.value ?? ''};

      // Model A: when local disk media is enabled, expose the upload root and
      // URL so the app (and a developer sourcing .env for console commands) can
      // read/write uploads. Written to .env at build + apply-unit; not persisted
      // as user-editable EnvVars. nginx serves this dir at /media/ (see the
      // apply-vhost step below). User-set values win, so we don't clobber them.
      if (app.mediaEnabled == true) {
        envMap.putIfAbsent('MEDIA_ROOT', () => '${app.workDir}/shared/media');
        envMap.putIfAbsent('MEDIA_URL', () => '/media/');
      }

      // Celery deploys always ship a Flower monitoring UI that the agent
      // reverse-proxies at the app's domain. Flower has no authentication of
      // its own, so an un-guarded deploy exposes worker internals — and the
      // ability to revoke/terminate tasks — to anyone who reaches the domain.
      // Guarantee HTTP basic-auth: honour a user-set FLOWER_BASIC_AUTH
      // ("user:password"), and otherwise generate one once and persist it so it
      // survives redeploys. It is stored NON-secret on purpose: the env-list API
      // strips `value` from secret vars, so a secret credential would be
      // enforced by Flower yet impossible to retrieve from the panel — leaving
      // Flower permanently locked out. (Apps from earlier builds that stored it
      // as secret are un-hidden below.) The agent passes it to Flower via
      // `--basic-auth` (see CeleryFlowerUnit / CeleryWorkerSupervisorConf).
      if (app.runtime == 'celery') {
        EnvVar? flowerAuth;
        for (final e in appEnvVars) {
          if (e.name == 'FLOWER_BASIC_AUTH') {
            flowerAuth = e;
            break;
          }
        }
        if (flowerAuth == null || (flowerAuth.value ?? '').isEmpty) {
          final creds = _generateFlowerBasicAuth();
          final now = DateTime.now().toUtc().toIso8601String();
          if (flowerAuth == null) {
            await Query<EnvVar>(EnvVarTable.metadata).insert(<String, Object?>{
              'appId': app.id,
              'name': 'FLOWER_BASIC_AUTH',
              'value': creds,
              'isSecret': false,
              'updatedAt': now,
            }).one(database.context());
          } else {
            await Query<EnvVar>(EnvVarTable.metadata)
                .where(EnvVarTable.id.eq(flowerAuth.id!))
                .update(<String, Object?>{
              'value': creds,
              'isSecret': false,
              'updatedAt': now,
            }).run(database.context());
          }
          envMap['FLOWER_BASIC_AUTH'] = creds;
          await _publishBuildLog(
            deploymentId,
            stream: 'system',
            line: 'Flower UI secured with auto-generated basic-auth '
                'credentials. View or change them via the FLOWER_BASIC_AUTH '
                'environment variable.',
          );
        } else if (flowerAuth.isSecret == true) {
          // Older deploys stored this credential as secret, so the env API hid
          // its value and the operator could never read it. Un-hide it (value
          // unchanged) so the existing Flower login becomes retrievable.
          await Query<EnvVar>(EnvVarTable.metadata)
              .where(EnvVarTable.id.eq(flowerAuth.id!))
              .update(<String, Object?>{
            'isSecret': false,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          }).run(database.context());
          await _publishBuildLog(
            deploymentId,
            stream: 'system',
            line: 'Flower basic-auth credentials are now viewable via the '
                'FLOWER_BASIC_AUTH environment variable.',
          );
        }
      }

      // 2. Build / fetch artifact. A force-rebuild deployment bypasses the
      //    agent's dependency/build cache so everything is reinstalled clean.
      final forceRebuild = payload['forceRebuild'] == true;
      await _runAgent([
        'build',
        '--app-id', '${app.id}',
        '--user', app.linuxUser!,
        '--work-dir', app.workDir,
        '--runtime', app.runtime,
        '--source-type', app.sourceType,
        if (forceRebuild) '--no-cache',
        // Which of the Application's supported deploy_modes this app uses —
        // lets a plugin branch between compiling and a dependency-only
        // prepare when its Application supports both.
        if (app.deploymentMode != null && app.deploymentMode!.isNotEmpty) ...[
          '--deploy-mode',
          app.deploymentMode!,
        ],
        // App env vars are needed at build time across runtimes:
        //  - Django (python/celery): migrate/collectstatic must reach the same
        //    DB/config as the runtime unit.
        //  - static/node/bun: client-side frameworks bake VITE_*/REACT_APP_*/
        //    NEXT_PUBLIC_* into the bundle at build time, so a missing env here
        //    leaves the build on its compiled-in defaults (e.g. backend URL).
        // It is harmless for runtimes that don't consult it, so always pass it.
        '--env-json', jsonEncode(envMap),
        if (app.gitUrl != null) ...['--git-url', app.gitUrl!],
        if (app.gitBranch != null) ...['--git-branch', app.gitBranch!],
        // Monorepo support: build/run from a subdirectory of the cloned repo
        // instead of its root.
        if (app.sourceSubdir != null && app.sourceSubdir!.isNotEmpty) ...[
          '--source-subdir',
          app.sourceSubdir!,
        ],
        if (app.buildCommand != null && app.buildCommand!.isNotEmpty) ...[
          '--build-command',
          app.buildCommand!
        ],
        // SSH deploy key for authenticated git clone.
        if (keyFile != null) ...['--deploy-key-path', keyFile.path],
        // Python / Celery: shared Python version selection.
        if ((app.runtime == 'python' || app.runtime == 'celery') &&
            app.pythonVersion != null) ...[
          '--python-version',
          app.pythonVersion!
        ],
        // Runtime version pins for other runtimes.
        if (app.runtime == 'node' && app.nodeVersion != null) ...[
          '--node-version', app.nodeVersion!
        ],
        if (app.runtime == 'bun' && app.bunVersion != null) ...[
          '--bun-version', app.bunVersion!
        ],
        if (app.runtime == 'dart' && app.dartVersion != null) ...[
          '--dart-version', app.dartVersion!
        ],
        if (app.runtime == 'go' && app.goVersion != null) ...[
          '--go-version', app.goVersion!
        ],
        if (app.runtime == 'rust' && app.rustVersion != null) ...[
          '--rust-version', app.rustVersion!
        ],
      ], deploymentId: deploymentId);

      // 3. Generate systemd + AppArmor + nginx vhost (idempotent).
      //    Env vars (fetched above) are written by apply-unit to <workDir>/.env
      //    and pulled into each unit via EnvironmentFile=. The same file can be
      //    sourced (set -a; source .env) to run management commands by hand.
      await _runAgent([
        'apply-unit',
        '--app-id', '${app.id}',
        '--user', app.linuxUser!,
        '--work-dir', app.workDir,
        if (app.internalPort != null) ...['--port', '${app.internalPort}'],
        '--runtime', app.runtime,
        '--env-json', jsonEncode(envMap),
        if (app.sourceSubdir != null && app.sourceSubdir!.isNotEmpty) ...[
          '--source-subdir',
          app.sourceSubdir!,
        ],
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
        // Node.js / Bun: pass the runtime bin dir so the unit's PATH is correct.
        // The build step has already created the symlink at .runtime.
        if (app.runtime == 'node' && app.nodeVersion != null)
          ...['--runtime-bin-dir', '${app.workDir}/current/.runtime/bin'],
        if (app.runtime == 'bun' && app.bunVersion != null)
          // Bun is a single binary — its "bin dir" is the parent of .runtime.
          ...['--runtime-bin-dir', '${app.workDir}/current'],
        // Celery-specific unit options.
        if (app.runtime == 'celery') ...[
          if (app.celeryApp != null) ...['--celery-app', app.celeryApp!],
          '--celery-worker-count',
          '${app.celeryWorkerCount ?? 2}',
          '--celery-concurrency',
          '${app.celeryConcurrency ?? 4}',
          if (app.celeryQueues != null && app.celeryQueues!.isNotEmpty) ...[
            '--celery-queues',
            app.celeryQueues!,
          ],
          if (app.celeryExtraArgs != null &&
              app.celeryExtraArgs!.isNotEmpty) ...[
            '--celery-extra-args',
            app.celeryExtraArgs!,
          ],
          if (app.celeryBeatEnabled == true) '--celery-beat',
        ],
      ], deploymentId: deploymentId);

      final appDomains = await Query<Domain>(DomainTable.metadata)
          .where(DomainTable.appId.eq(app.id!))
          .all(database.context());
      final hostnames = appDomains
          .where((d) => d.hostname != null)
          .map((d) => d.hostname!)
          .toList();

      if (app.runtime == 'static') {
        // Static sites are served by Nginx from the stable symlink
        // <workDir>/current/web. The agent publishes the freshly-built output
        // into releases/web/<deploymentId> and atomically repoints that symlink,
        // so nginx never serves a half-built or deleted root (the old
        // "works then 404" bug). Pass the build output as --publish-from.
        final staticRoot =
            (app.staticRoot != null && app.staticRoot!.isNotEmpty)
                ? app.staticRoot!
                : '';
        // Monorepo support: the cloned repo root stays at current_build, but
        // the actual project (and therefore its build output) may live in a
        // subdirectory of it.
        final sourceRoot =
            (app.sourceSubdir != null && app.sourceSubdir!.isNotEmpty)
                ? '${app.workDir}/releases/current_build/${app.sourceSubdir}'
                : '${app.workDir}/releases/current_build';
        final buildOutput = staticRoot.isNotEmpty
            ? '$sourceRoot/$staticRoot'
            : sourceRoot;
        await _runAgent([
          'apply-vhost',
          '--app-id', '${app.id}',
          '--runtime', 'static',
          '--work-dir', app.workDir,
          '--user', app.linuxUser!,
          '--publish-from', buildOutput,
          '--release-id', '$deploymentId',
          if (app.staticSpa == true) '--static-spa',
          for (final h in hostnames) ...['--hostname', h],
        ], deploymentId: deploymentId);
      } else {
        await _runAgent([
          'apply-vhost',
          '--app-id', '${app.id}',
          if (app.internalPort != null) ...['--port', '${app.internalPort}'],
          // Django apps collect static under shared/static; let nginx serve it
          // directly at /static/. The agent ignores roots that don't exist, so
          // non-Django Python apps proxy as before.
          if (app.runtime == 'python')
            ...['--static-root', '${app.workDir}/shared/static'],
          // Model A: any runtime that opted into local disk media gets nginx
          // serving shared/media at /media/, an internal /_protected/ location
          // for X-Accel-Redirect handoff, and a per-app upload size. Python apps
          // historically served /media/ regardless; preserve that.
          if (app.mediaEnabled == true || app.runtime == 'python') ...[
            '--media-root', '${app.workDir}/shared/media',
            '--protected-media',
            '--max-upload-mb', '${app.mediaMaxUploadMb ?? 25}',
          ],
          for (final h in hostnames) ...['--hostname', h],
        ], deploymentId: deploymentId);
      }

      // 4. Start / restart the service (runtime-aware).
      await _runAgent(
          ['restart', '--user', app.linuxUser!, '--runtime', app.runtime],
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

    // Removal tears down every host resource, then drops the DB row.
    if (action == 'delete') {
      await _destroyApp(app);
      return;
    }

    final agentAction = switch (action) {
      'start' => 'start',
      'stop' => 'stop',
      'restart' => 'restart',
      _ => null,
    };
    if (agentAction == null) return;

    await _runAgent([agentAction, '--user', app.linuxUser!, '--runtime', app.runtime]);
    await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(app.id!))
        .update(<String, Object?>{
      'status': action == 'stop' ? 'stopped' : 'running',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }).run(database.context());
  }

  /// Tear down all host-side resources for [app], then delete its DB row.
  ///
  /// The agent removes the systemd/supervisor units, AppArmor profile, nginx
  /// vhost, TLS certs, work dir and Linux user. Deleting the [App] row cascades
  /// to its env vars, domains, deployments, metrics and events, so nothing is
  /// left behind on disk or in the database.
  Future<void> _destroyApp(App app) async {
    final domains = await Query<Domain>(DomainTable.metadata)
        .where(DomainTable.appId.eq(app.id!))
        .all(database.context());
    final hostnames = domains
        .where((d) => d.hostname != null)
        .map((d) => d.hostname!)
        .toList();

    await _runAgent([
      'uninstall',
      '--app-id', '${app.id}',
      '--user', app.linuxUser!,
      '--runtime', app.runtime,
      '--work-dir', app.workDir,
      for (final h in hostnames) ...['--hostname', h],
    ]);

    await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(app.id!))
        .delete()
        .run(database.context());
  }

  /// Cascade-remove a project or team and everything beneath it.
  ///
  /// The DB schema cascades `team → projects → apps`, so naively deleting the
  /// top row would drop the app records and orphan their host resources. We
  /// instead tear down every child app's host side first (via [_destroyApp],
  /// which also deletes the app row), then delete the project/team row.
  Future<void> onTeardown(Map<String, Object?> payload) async {
    final scope = payload['scope'] as String?;
    final id = payload['id'] as int?;
    if (scope == null || id == null) return;

    switch (scope) {
      case 'project':
        await _destroyProject(id);
        break;
      case 'team':
        final projects = await Query<Project>(ProjectTable.metadata)
            .where(ProjectTable.teamId.eq(id))
            .all(database.context());
        for (final project in projects) {
          await _destroyProject(project.id!);
        }
        await Query<Team>(TeamTable.metadata)
            .where(TeamTable.id.eq(id))
            .delete()
            .run(database.context());
        break;
    }
  }

  Future<void> _destroyProject(int projectId) async {
    final apps = await Query<App>(AppTable.metadata)
        .where(AppTable.projectId.eq(projectId))
        .all(database.context());
    for (final app in apps) {
      await _destroyApp(app);
    }
    await Query<Project>(ProjectTable.metadata)
        .where(ProjectTable.id.eq(projectId))
        .delete()
        .run(database.context());
  }

  Future<void> onVhost(Map<String, Object?> payload) async {
    final appId = payload['appId'] as int?;
    if (appId == null) return;
    final app = await _findApp(appId);
    if (app == null) return;
    final domains = await Query<Domain>(DomainTable.metadata)
        .where(DomainTable.appId.eq(app.id!))
        .all(database.context());
    final hostnames = domains
        .where((d) => d.hostname != null)
        .map((d) => d.hostname!)
        .toList();

    if (app.runtime == 'static') {
      // A vhost-only change (e.g. adding/removing a domain) must NOT republish
      // or rebuild — re-render the vhost against the existing live release at
      // <workDir>/current/web, leaving the served files untouched.
      await _runAgent([
        'apply-vhost',
        '--app-id', '${app.id}',
        '--runtime', 'static',
        '--work-dir', app.workDir,
        '--user', app.linuxUser!,
        if (app.staticSpa == true) '--static-spa',
        for (final h in hostnames) ...['--hostname', h],
      ]);
      return;
    }

    await _runAgent([
      'apply-vhost',
      '--app-id',
      '${app.id}',
      if (app.internalPort != null) ...['--port', '${app.internalPort}'],
      if (app.runtime == 'python')
        ...['--static-root', '${app.workDir}/shared/static'],
      // Keep media serving in sync on a vhost-only re-render (domain add/remove
      // or a media-settings toggle from the API).
      if (app.mediaEnabled == true || app.runtime == 'python') ...[
        '--media-root', '${app.workDir}/shared/media',
        '--protected-media',
        '--max-upload-mb', '${app.mediaMaxUploadMb ?? 25}',
      ],
      for (final h in hostnames) ...['--hostname', h],
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

  /// Generate `user:password` credentials for Flower's `--basic-auth`.
  ///
  /// The alphabet is restricted to URL/shell-safe characters (no `:`, `%`,
  /// quotes or whitespace) so the value can be embedded verbatim in the
  /// generated systemd/supervisor process command without escaping, and
  /// ambiguous look-alikes (0/O, 1/l/I) are dropped so a human can retype it.
  static String _generateFlowerBasicAuth() {
    const alphabet =
        'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final pw = List.generate(
        24, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
    return 'flower:$pw';
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
