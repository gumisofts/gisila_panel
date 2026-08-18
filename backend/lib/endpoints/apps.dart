import 'dart:convert';
import 'dart:io';

import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/forms/app_forms.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';
import 'package:gisila_panel/services/envs_service.dart';
import 'package:gisila_panel/services/lifecycle_service.dart';
import 'package:uuid/uuid.dart';

part 'apps.g.dart';

@Controller('/apps', ['Apps'])
@RequireAuth()
class AppsApi {
  @Get('/', summary: 'List apps')
  Future<Map<String, Object?>> list(
    AppsService apps,
    RequestContext ctx,
    int? projectId,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await apps.listForUser(user, projectId: projectId);
    return <String, Object?>{
      'results': result.map((a) => a.toJson()).toList(),
    };
  }

  @Post('/', summary: 'Create an app')
  Future<Map<String, Object?>> create(
    CreateAppForm form,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final app = await apps.create(
      user,
      projectId: form.projectId.value!,
      name: form.name.value!,
      applicationId: form.applicationId.value,
      runtime: form.runtime.value,
      deploymentMode: form.deploymentMode.value,
      sourceType: form.sourceType.value!,
      port: form.internalPort.value,
      gitUrl: form.gitUrl.value,
      gitBranch: form.gitBranch.value,
      sourceSubdir: form.sourceSubdir.value,
      buildCommand: form.buildCommand.value,
      startCommand: form.startCommand.value,
      healthCheckPath: form.healthCheckPath.value,
      memoryMbLimit: form.memoryMbLimit.value,
      cpuQuotaPercent: form.cpuQuotaPercent.value,
      tasksLimit: form.tasksLimit.value,
      pythonVersion: form.pythonVersion.value,
      pythonMode: form.pythonMode.value,
      wsgiApp: form.wsgiApp.value,
      gunicornWorkers: form.gunicornWorkers.value,
      gunicornThreads: form.gunicornThreads.value,
      gunicornTimeout: form.gunicornTimeout.value,
      gunicornBind: form.gunicornBind.value,
      gunicornExtraArgs: form.gunicornExtraArgs.value,
      nodeVersion: form.nodeVersion.value,
      dartVersion: form.dartVersion.value,
      goVersion: form.goVersion.value,
      rustVersion: form.rustVersion.value,
      bunVersion: form.bunVersion.value,
      celeryApp: form.celeryApp.value,
      celeryWorkerCount: form.celeryWorkerCount.value,
      celeryConcurrency: form.celeryConcurrency.value,
      celeryQueues: form.celeryQueues.value,
      celeryBeatEnabled: form.celeryBeatEnabled.value,
      celeryExtraArgs: form.celeryExtraArgs.value,
      staticRoot: form.staticRoot.value,
      staticSpa: form.staticSpa.value,
      mediaEnabled: form.mediaEnabled.value,
      mediaMaxUploadMb: form.mediaMaxUploadMb.value,
      deployKeyId: form.deployKeyId.value,
      exposeMode: form.exposeMode.value,
      publiclyReachable: form.publiclyReachable.value,
    );
    return app.toJson();
  }

  // Registered ahead of `/{id}` — shelf_router matches routes in
  // registration order, and `{id}` (an `int` param) would otherwise swallow
  // this literal segment before it ever reaches its handler.
  @Get('/metrics-summary', summary: 'Latest CPU/memory usage per running app')
  Future<Map<String, Object?>> metricsSummary(
    AppsService apps,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final visible = await apps.listForUser(user);
    final db = ctx.db<Database>().context();

    final results = <Map<String, Object?>>[];
    for (final app in visible) {
      if (app.id == null || app.status != 'running') continue;
      final sample = await Query<MetricSample>(MetricSampleTable.metadata)
          .where(MetricSampleTable.appId.eq(app.id!))
          .orderBy(MetricSampleTable.sampledAt, desc: true)
          .first(db);
      if (sample == null) continue;

      // Stale samples (worker restarted, app just started) aren't a useful
      // "current usage" — same 5 minute cutoff the alert evaluator uses.
      if (DateTime.now().toUtc().difference(sample.sampledAt) >
          const Duration(minutes: 5)) {
        continue;
      }

      results.add(<String, Object?>{
        'appId': app.id,
        'name': app.name,
        'status': app.status,
        'cpuPercent': sample.cpuPercent,
        'memBytes': sample.memBytes,
        'memoryMbLimit': app.memoryMbLimit,
        'cpuQuotaPercent': app.cpuQuotaPercent,
        'sampledAt': sample.sampledAt.toIso8601String(),
      });
    }
    return <String, Object?>{'results': results};
  }

  // Also ahead of `/{id}` for the same reason as `/metrics-summary` above.
  @Get('/limits', summary: 'Host resource limits apps can be configured up to')
  Future<Map<String, Object?>> limits(RequestContext ctx) async {
    // "Percent of one core" is what cpuQuotaPercent/systemd's CPUQuota mean —
    // above the host's actual core count the setting just can never be
    // reached, so that's the real ceiling worth showing/enforcing.
    final cores = Platform.numberOfProcessors;
    return <String, Object?>{
      'cpuCores': cores,
      'maxCpuQuotaPercent': cores * 100,
    };
  }

  @Get('/{id}', summary: 'Get an app')
  Future<Map<String, Object?>> retrieve(
    int id,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final app = await apps.findForUser(user, id);
    return app.toJson();
  }

  @Patch('/{id}', summary: 'Update an app')
  Future<Map<String, Object?>> update(
    int id,
    UpdateAppForm form,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final patch = <String, Object?>{
      if (form.name.value != null) 'name': form.name.value,
      if (form.gitUrl.value != null) 'gitUrl': form.gitUrl.value,
      if (form.gitBranch.value != null) 'gitBranch': form.gitBranch.value,
      if (form.sourceSubdir.value != null)
        'sourceSubdir': form.sourceSubdir.value,
      if (form.buildCommand.value != null)
        'buildCommand': form.buildCommand.value,
      if (form.startCommand.value != null)
        'startCommand': form.startCommand.value,
      if (form.healthCheckPath.value != null)
        'healthCheckPath': form.healthCheckPath.value,
      if (form.memoryMbLimit.value != null)
        'memoryMbLimit': form.memoryMbLimit.value,
      if (form.cpuQuotaPercent.value != null)
        'cpuQuotaPercent': form.cpuQuotaPercent.value,
      if (form.tasksLimit.value != null) 'tasksLimit': form.tasksLimit.value,
      if (form.pythonVersion.value != null)
        'pythonVersion': form.pythonVersion.value,
      if (form.pythonMode.value != null) 'pythonMode': form.pythonMode.value,
      if (form.wsgiApp.value != null) 'wsgiApp': form.wsgiApp.value,
      if (form.gunicornWorkers.value != null)
        'gunicornWorkers': form.gunicornWorkers.value,
      if (form.gunicornThreads.value != null)
        'gunicornThreads': form.gunicornThreads.value,
      if (form.gunicornTimeout.value != null)
        'gunicornTimeout': form.gunicornTimeout.value,
      if (form.gunicornBind.value != null)
        'gunicornBind': form.gunicornBind.value,
      if (form.gunicornExtraArgs.value != null)
        'gunicornExtraArgs': form.gunicornExtraArgs.value,
      if (form.nodeVersion.value != null) 'nodeVersion': form.nodeVersion.value,
      if (form.dartVersion.value != null) 'dartVersion': form.dartVersion.value,
      if (form.goVersion.value != null) 'goVersion': form.goVersion.value,
      if (form.rustVersion.value != null) 'rustVersion': form.rustVersion.value,
      if (form.bunVersion.value != null) 'bunVersion': form.bunVersion.value,
      if (form.deployKeyId.value != null) 'deployKeyId': form.deployKeyId.value,
      if (form.internalPort.value != null) 'internalPort': form.internalPort.value,
      // Static settings are always sent together from the panel. Empty
      // staticRoot binds as null (clear). Gate on staticSpa so a clear still
      // persists — `value != null` alone would skip an emptied directory.
      if (form.staticSpa.value != null) ...{
        'staticSpa': form.staticSpa.value,
        'staticRoot': form.staticRoot.value,
      } else if (form.staticRoot.value != null) ...{
        'staticRoot': form.staticRoot.value,
      },
      if (form.mediaEnabled.value != null)
        'mediaEnabled': form.mediaEnabled.value,
      if (form.mediaMaxUploadMb.value != null)
        'mediaMaxUploadMb': form.mediaMaxUploadMb.value,
    };
    final app = await apps.update(user, id, patch);

    // Static serving behaviour (SPA fallback / served root) is baked into the
    // nginx vhost at render time, so persisting the flag alone changes nothing
    // live. Re-render the vhost against the current release — no rebuild — so
    // the change (e.g. enabling SPA mode to stop deep-link refreshes 404ing)
    // takes effect immediately.
    if (app.runtime == 'static' && form.staticSpa.value != null) {
      await RedisClient.instance.rpush(
        'gisila:queue:vhosts',
        jsonEncode(<String, Object?>{
          'appId': app.id,
          'reason': 'static_settings',
        }),
      );
    }

    // Media serving (the nginx /media/ + /_protected/ blocks and the upload
    // size) is rendered into the vhost, so changing it re-renders against the
    // current release with no rebuild. MEDIA_ROOT is written to the app's .env
    // on the next deploy. Static apps serve files differently and are excluded.
    if (app.runtime != 'static' &&
        (form.mediaEnabled.value != null ||
            form.mediaMaxUploadMb.value != null)) {
      await RedisClient.instance.rpush(
        'gisila:queue:vhosts',
        jsonEncode(<String, Object?>{
          'appId': app.id,
          'reason': 'media_settings',
        }),
      );
    }
    return app.toJson();
  }

  // ── Network exposure (tcp apps) ─────────────────────────────────────

  /// Toggle whether a `tcp`-exposed app's port is opened on the host
  /// firewall. Reconciled by the worker via `expose-port`/`unexpose-port` —
  /// see `DeploymentWorker.onNetworkExposure`.
  @Post('/{id}/network', summary: 'Toggle public reachability for a tcp app')
  Future<Map<String, Object?>> network(
    int id,
    NetworkExposureForm form,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final app = await apps.setNetworkExposure(
      user,
      id,
      publiclyReachable: form.publiclyReachable.value!,
    );
    return app.toJson();
  }

  @Delete('/{id}', summary: 'Remove an app and all of its resources')
  Future<Map<String, Object?>> delete(
    int id,
    LifecycleService lifecycle,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await lifecycle.destroy(user, id);
    return <String, Object?>{'detail': 'App removal requested.'};
  }

  // ── Lifecycle ────────────────────────────────────────────────────────

  @Post('/{id}/start', summary: 'Start an app')
  Future<Map<String, Object?>> start(
    int id,
    LifecycleService lifecycle,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await lifecycle.start(user, id);
    return <String, Object?>{'detail': 'Start requested.'};
  }

  @Post('/{id}/stop', summary: 'Stop an app')
  Future<Map<String, Object?>> stop(
    int id,
    LifecycleService lifecycle,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await lifecycle.stop(user, id);
    return <String, Object?>{'detail': 'Stop requested.'};
  }

  @Post('/{id}/restart', summary: 'Restart an app')
  Future<Map<String, Object?>> restart(
    int id,
    LifecycleService lifecycle,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await lifecycle.restart(user, id);
    return <String, Object?>{'detail': 'Restart requested.'};
  }

  // ── Command execution ────────────────────────────────────────────────

  /// Queue a one-off command to run inside the app's environment (as the app's
  /// Linux user, with the Python virtualenv activated for python/celery apps).
  ///
  /// Returns an `execId`; the caller then opens the WebSocket
  /// `/ws/apps/{id}/exec/{execId}` to stream stdout/stderr live.
  @Post('/{id}/exec', summary: 'Run a one-off command in the app environment')
  Future<Map<String, Object?>> exec(
    int id,
    ExecCommandForm form,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    // Running an arbitrary command inside the app is a developer-level action.
    final app = await apps.requireAppRole(user, id, TeamRole.developer);
    final command = form.command.value!.trim();
    if (command.isEmpty) {
      throw HttpException(422, 'command is required');
    }
    final execId = const Uuid().v4();
    await RedisClient.instance.rpush(
      'gisila:queue:exec',
      jsonEncode({
        'appId': app.id,
        'execId': execId,
        'command': command,
      }),
    );
    return <String, Object?>{'execId': execId};
  }

  // ── Env vars ─────────────────────────────────────────────────────────

  @Get('/{id}/envs', summary: 'List env vars')
  Future<Map<String, Object?>> listEnvs(
    int id,
    EnvsService envs,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await envs.list(user, id);
    return <String, Object?>{
      'results': result
          .map((e) => e.toJson(exclude: e.isSecret == true ? ['value'] : []))
          .toList(),
    };
  }

  @Post('/{id}/envs', summary: 'Set an env var')
  Future<Map<String, Object?>> setEnv(
    int id,
    EnvVarForm form,
    EnvsService envs,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final env = await envs.upsert(
      user,
      id,
      name: form.name.value!,
      value: form.value.value,
      isSecret: form.isSecret.value ?? false,
    );
    return env.toJson(exclude: env.isSecret == true ? ['value'] : []);
  }

  /// Bulk-upsert env vars from a parsed .env payload.
  ///
  /// Body: `{ "entries": [{"name": "KEY", "value": "val", "isSecret": false}, …] }`
  ///
  /// Existing vars with the same name are overwritten; others are left intact.
  @Post('/{id}/envs/bulk', summary: 'Bulk-upsert env vars from a .env file')
  Future<Map<String, Object?>> bulkEnvs(
    int id,
    BulkEnvVarForm form,
    EnvsService envs,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final raw = form.entries.value;
    if (raw is! List) {
      throw HttpException(422, '"entries" must be a JSON array.');
    }
    int count = 0;
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim() ?? '';
      final value = item['value']?.toString() ?? '';
      final secret = item['isSecret'] == true;
      if (name.isEmpty) continue;
      await envs.upsert(user, id, name: name, value: value, isSecret: secret);
      count++;
    }
    return <String, Object?>{'imported': count};
  }

  @Delete('/{id}/envs/{envId}', summary: 'Delete an env var')
  Future<Map<String, Object?>> deleteEnv(
    int id,
    int envId,
    EnvsService envs,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await envs.delete(user, id, envId);
    return <String, Object?>{'detail': 'Env var deleted.'};
  }
}
