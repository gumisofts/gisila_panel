import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';

/// The outcome of the agent's post-restart readiness probe.
class _HealthVerdict {
  const _HealthVerdict(this.healthy, this.detail, {this.logTail = const []});

  /// `null` when the probe could not be run at all — "we don't know", which is
  /// deliberately distinct from "it is down".
  final bool? healthy;

  /// A sentence naming what was observed, shown as the deployment's failure
  /// reason and published to the build log.
  final String detail;

  /// The tail of the unit's journal when the app was found down, so the panel
  /// shows why rather than only that.
  final List<String> logTail;
}

/// Bridge between the Dart worker and the privileged `gisila-agent` CLI.
///
/// Tasks are routed by queue name to specialised handlers. Everything
/// happens through `gisila-agent` so the worker itself never needs root.
class DeploymentWorker {
  DeploymentWorker(this.database);

  final Database database;

  // ── Queue handlers ─────────────────────────────────────────────────

  Future<void> onDeployment(Map<String, Object?> payload) async {
    final deploymentId = _asInt(payload['deploymentId']);
    final appId = _asInt(payload['appId']);
    if (deploymentId == null || appId == null) {
      logger.w(
        'worker: deployment job missing ids '
        '(deploymentId=${payload['deploymentId']} appId=${payload['appId']})',
      );
      return;
    }

    final existing = await Query<Deployment>(DeploymentTable.metadata)
        .where(DeploymentTable.id.eq(deploymentId))
        .first(database.context());
    if (existing == null) {
      logger.w('worker: deployment #$deploymentId not found — skipping');
      return;
    }
    // BLPOP is at-most-once: a crash, a silent return, or a lost Redis
    // message leaves the row in `queued` while the list is empty. Recovery
    // re-enqueues it, so the same id can show up twice. A finished or
    // already-running row must not start a second build.
    final status = existing.status ?? '';
    if (status == 'succeeded' ||
        status == 'failed' ||
        status == 'rolled_back') {
      logger.i('worker: deployment #$deploymentId is $status — skipping');
      return;
    }

    final app = await _findApp(appId);
    if (app == null) {
      await _markStatus(
        deploymentId,
        'failed',
        reason: 'App #$appId not found.',
      );
      return;
    }

    await _markStatus(deploymentId, 'building');
    await _publishBuildLog(
      deploymentId,
      stream: 'system',
      line: payload['requeued'] == true
          ? 'Deployment #$deploymentId re-queued and started for app ${app.name}.'
          : 'Deployment #$deploymentId started for app ${app.name}.',
    );

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
        // Names the directory this build publishes to (releases/<id>), which
        // current/src is then repointed at. Using the deployment id keeps the
        // releases on disk traceable back to a row in the deployments table.
        '--release-id', '$deploymentId',
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
        if ((app.runtime == 'node' || app.runtime == 'static') &&
            app.nodeVersion != null) ...[
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
        // tcp/internal apps bind their port directly and terminate every
        // client socket themselves (no nginx multiplexing) — the agent uses
        // this to raise the unit's file-descriptor ceiling accordingly.
        '--expose-mode', app.exposeMode ?? 'web',
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

      // Non-web exposure (tcp/internal) has no Nginx vhost or Domain at all —
      // reconcile the firewall instead (tcp) or leave the app reachable only
      // via 127.0.0.1 (internal). Either way, skip apply-vhost entirely.
      if (app.exposeMode != null && app.exposeMode != 'web') {
        if (app.exposeMode == 'tcp' && app.internalPort != null) {
          await _runAgent([
            app.publiclyReachable == true ? 'expose-port' : 'unexpose-port',
            '--port', '${app.internalPort}',
          ], deploymentId: deploymentId);
        }
        await _runAgent(
            ['restart', '--user', app.linuxUser!, '--runtime', app.runtime],
            deploymentId: deploymentId);
        await _finishDeployment(deploymentId, app);
        return;
      }

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

      // 4. Start / restart the service (runtime-aware), then confirm it is
      //    actually serving before calling the deployment a success.
      await _runAgent(
          ['restart', '--user', app.linuxUser!, '--runtime', app.runtime],
          deploymentId: deploymentId);

      await _finishDeployment(deploymentId, app);
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
    final appId = _asInt(payload['appId']);
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

    // A tcp app's firewall hole must always be closed on teardown, even if
    // it was never explicitly toggled off — otherwise the port stays open on
    // the host after the app (and its record of ever having existed) is gone.
    if (app.exposeMode == 'tcp' && app.internalPort != null) {
      await _runAgent(['unexpose-port', '--port', '${app.internalPort}']);
    }

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
    final id = _asInt(payload['id']);
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

  /// Reconcile a `tcp` app's firewall exposure without a full redeploy —
  /// enqueued by `AppsService.setNetworkExposure` whenever the
  /// `publiclyReachable` toggle changes.
  Future<void> onNetworkExposure(Map<String, Object?> payload) async {
    final appId = _asInt(payload['appId']);
    if (appId == null) return;
    final app = await _findApp(appId);
    if (app == null || app.exposeMode != 'tcp' || app.internalPort == null) {
      return;
    }
    await _runAgent([
      app.publiclyReachable == true ? 'expose-port' : 'unexpose-port',
      '--port', '${app.internalPort}',
    ]);
  }

  Future<void> onVhost(Map<String, Object?> payload) async {
    final appId = _asInt(payload['appId']);
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
    final domainId = _asInt(payload['domainId']);
    final hostname = payload['hostname'] as String?;
    final appId = _asInt(payload['appId']);
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
      // Re-render the vhost so the new cert is wired into a dedicated 443
      // server block for this hostname (and siblings keep theirs).
      if (appId != null) {
        await onVhost(<String, Object?>{
          'appId': appId,
          'reason': 'ssl_issued',
        });
      }
    } catch (e) {
      await Query<Domain>(DomainTable.metadata)
          .where(DomainTable.id.eq(domainId))
          .update(<String, Object?>{
        'sslStatus': 'failed',
      }).run(database.context());
      rethrow;
    }
  }

  // ── Stuck-queue recovery ───────────────────────────────────────────

  /// Re-enqueue DB rows that never left `queued` (or died mid-build).
  ///
  /// `BLPOP` deletes the Redis message before the handler runs. A worker
  /// restart, a dead BLPOP socket, or a silent return leaves the row sitting
  /// in `queued` with an empty list — the panel shows queued until the
  /// operator clicks Deploy again (which is why a second deployment appears
  /// to "unstick" the first). Sweep on boot and periodically so the original
  /// row starts on its own.
  void startStuckSweep({
    Duration interval = const Duration(seconds: 20),
  }) {
    unawaited(recoverStuck(startup: true));
    Timer.periodic(interval, (_) => unawaited(recoverStuck()));
  }

  final Map<int, DateTime> _lastRequeue = {};

  Future<void> recoverStuck({bool startup = false}) async {
    try {
      final now = DateTime.now().toUtc();
      final queued = await Query<Deployment>(DeploymentTable.metadata)
          .where(DeploymentTable.status.eq('queued'))
          .all(database.context());
      final inFlight = startup
          ? await Query<Deployment>(DeploymentTable.metadata)
              .where(DeploymentTable.status.inList(['building', 'deploying']))
              .all(database.context())
          : <Deployment>[];

      if (startup) {
        for (final d in inFlight) {
          if (d.id == null) continue;
          await Query<Deployment>(DeploymentTable.metadata)
              .where(DeploymentTable.id.eq(d.id!))
              .update(<String, Object?>{'status': 'queued'}).run(
                  database.context());
        }
      }

      var n = 0;
      for (final d in [...queued, ...inFlight]) {
        final id = d.id;
        if (id == null) continue;
        if (!startup) {
          final age = now.difference(d.createdAt.toUtc());
          if (age < const Duration(seconds: 20)) continue;
          final last = _lastRequeue[id];
          if (last != null &&
              now.difference(last) < const Duration(minutes: 2)) {
            continue;
          }
        }
        _lastRequeue[id] = now;
        await RedisClient.instance.rpush(
          'gisila:queue:deployments',
          jsonEncode(<String, Object?>{
            'deploymentId': id,
            'appId': d.appId,
            'sourceType': d.sourceType,
            'gitCommitSha': d.gitCommitSha,
            'artifactPath': d.artifactPath,
            'queuedAt': d.createdAt.toUtc().toIso8601String(),
            'requeued': true,
          }),
        );
        n++;
      }
      if (n > 0) {
        logger.i(
          'worker: re-queued $n stuck deployment${n == 1 ? '' : 's'}'
          '${startup ? ' (startup)' : ''}',
        );
      }
      _lastRequeue.removeWhere((id, _) =>
          queued.every((d) => d.id != id) &&
          inFlight.every((d) => d.id != id));
    } catch (e, st) {
      logger.w('worker: stuck-deployment sweep failed', error: e, stackTrace: st);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

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

  // ── Post-restart verification ──────────────────────────────────────

  /// Close out a deployment: confirm the app is actually serving, and only
  /// then mark it succeeded and the app running.
  ///
  /// The agent's `restart` returns as soon as systemd has forked the process.
  /// The units are `Type=simple`, so `active` says nothing about whether
  /// gunicorn ever imported the application, and this step used to mark the
  /// deployment succeeded on the strength of nothing at all. Every deploy that
  /// left an app crash-looping was still recorded here as `succeeded` — one of
  /// them at the exact second a 97-restart loop began, while nginx was already
  /// answering real users with 502s. The operator saw a green panel and a dead
  /// site.
  ///
  /// See the agent's `app-health` for what is probed, and why `is-active` is
  /// never the only signal.
  Future<void> _finishDeployment(int deploymentId, App app) async {
    await _publishBuildLog(deploymentId,
        stream: 'system', line: 'Verifying the service is up…');
    final verdict = await _verifyServing(app);

    if (verdict.healthy != false) {
      // `null` means the probe could not run at all (dev mode, or the agent
      // call itself failed) — which is not evidence that the app is down.
      // Succeed, but say in the build log that nothing was verified, so a host
      // where the check is silently broken is visible rather than a return to
      // the old always-green behaviour.
      await _markStatus(deploymentId, 'succeeded', activate: true, app: app);
      await _publishBuildLog(deploymentId,
          stream: 'system', line: 'Deployment succeeded. ${verdict.detail}');
      return;
    }

    final now = DateTime.now().toUtc();
    await _markStatus(deploymentId, 'failed', reason: verdict.detail);
    // The deploy is on disk and the units are written, but nothing is serving.
    // `crashed` is what the panel's app badge and the alert worker already use
    // for exactly this state.
    await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(app.id!))
        .update(<String, Object?>{
      'status': 'crashed',
      'updatedAt': now.toIso8601String(),
    }).run(database.context());

    await _publishBuildLog(deploymentId,
        stream: 'stderr', line: 'FAILED: ${verdict.detail}');
    for (final line in verdict.logTail) {
      await _publishBuildLog(deploymentId, stream: 'stderr', line: line);
    }
  }

  /// Ask the agent whether [app] is serving. Never throws — a probe that cannot
  /// run reports "unknown" rather than taking the deployment down with it.
  Future<_HealthVerdict> _verifyServing(App app) async {
    if (hostConfig.agentMode == 'dev') {
      return const _HealthVerdict(
          null, 'Health was not verified: the agent is in dev mode.');
    }
    final args = <String>[
      'app-health',
      '--user', app.linuxUser!,
      '--runtime', app.runtime,
      if (app.internalPort != null) ...['--port', '${app.internalPort}'],
      '--expose-mode', app.exposeMode ?? 'web',
      // The strongest probe available, when the operator has configured one.
      if ((app.healthCheckPath ?? '').trim().isNotEmpty) ...[
        '--health-path',
        app.healthCheckPath!.trim(),
      ],
    ];
    try {
      final cmd = buildAgentCmd(args);
      final result = await Process.run(cmd.first, cmd.skip(1).toList());
      final report = _findJsonWith(result.stdout as String? ?? '', 'healthy');
      if (report == null) {
        return _HealthVerdict(
          null,
          'Health could not be verified: the agent returned no report '
          '(exit ${result.exitCode}). Update gisila-agent on this host.',
        );
      }
      return _HealthVerdict(
        report['healthy'] == true,
        (report['detail'] as String?)?.trim().isNotEmpty == true
            ? report['detail'] as String
            : 'The service did not pass its post-restart health check.',
        logTail: [
          for (final line in (report['logTail'] as List?) ?? const [])
            if (line is String) line,
        ],
      );
    } catch (e) {
      return _HealthVerdict(null, 'Health could not be verified: $e');
    }
  }

  /// Pull the JSON line carrying [key] out of an agent's stdout.
  ///
  /// The agent's `main()` prints a trailing `{"ok":true,…}` wrapper after a
  /// command's real output, so a naive last-line parse would return that
  /// instead — scan bottom-up for the line that actually has the field.
  Map<String, Object?>? _findJsonWith(String text, String key) {
    final lines = text.trim().split('\n');
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (!line.startsWith('{') || !line.contains('"$key"')) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, Object?> && decoded.containsKey(key)) {
          return decoded;
        }
      } catch (_) {
        // Not the line we want — keep scanning upward.
      }
    }
    return null;
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
    final payload = jsonEncode({'stream': stream, 'line': line});
    try {
      // Cap a Redis replay buffer so reconnecting clients (leave tab / come
      // back mid-build) see lines published while they were away.
      final historyKey = 'gisila:logs:build:$deploymentId:history';
      await RedisClient.instance.rpush(historyKey, payload);
      await RedisClient.instance.ltrim(historyKey, -2000, -1);
      await RedisClient.instance.expire(historyKey, 86400);
      await RedisClient.instance.publish(
        'gisila:logs:build:$deploymentId',
        payload,
      );
    } catch (e) {
      logger.w('deployment_worker: failed to publish build log: $e');
    }
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

    // Collect lines and persist them concurrently, but wait for every insert
    // to finish before treating the agent run as done — otherwise leaving the
    // Deployments tab mid-build and coming back shows a truncated DB log.
    final pending = <Future<void>>[];
    final outputs = await Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
        if (deploymentId != null) {
          pending.add(
            _publishBuildLog(deploymentId, stream: 'stdout', line: line),
          );
        }
        return line;
      }).toList(),
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
        if (deploymentId != null) {
          pending.add(
            _publishBuildLog(deploymentId, stream: 'stderr', line: line),
          );
        }
        return line;
      }).toList(),
    ]);
    if (pending.isNotEmpty) await Future.wait(pending);

    final exit = await process.exitCode;
    if (exit != 0) {
      throw StateError(
        'agent exited with $exit: ${outputs[1].join("\\n")}',
      );
    }
  }
}
