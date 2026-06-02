import 'dart:convert';

import 'package:gisila_doc/gisila_doc.dart';
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
      runtime: form.runtime.value!,
      sourceType: form.sourceType.value!,
      gitUrl: form.gitUrl.value,
      gitBranch: form.gitBranch.value,
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
      deployKeyId: form.deployKeyId.value,
    );
    return app.toJson();
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
      if (form.deployKeyId.value != null) 'deployKeyId': form.deployKeyId.value,
    };
    final app = await apps.update(user, id, patch);
    return app.toJson();
  }

  @Delete('/{id}', summary: 'Delete an app')
  Future<Map<String, Object?>> delete(
    int id,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await apps.delete(user, id);
    return <String, Object?>{'detail': 'App deleted.'};
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
  /// Linux user, with the Python virtualenv activated for python apps).
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
    final app = await apps.findForUser(user, id);
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
