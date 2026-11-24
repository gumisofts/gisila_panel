import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/forms/app_forms.dart';
import 'package:gisila_panel/forms/stack_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/stacks_service.dart';

part 'stacks.g.dart';

Map<String, Object?> _envJson(StackEnvVar e) =>
    e.toJson(exclude: e.isSecret == true ? ['value'] : []);

/// Stacks group the apps of a project and hold env vars those apps share.
/// An app in a stack is deployed with the stack's vars plus its own, and its
/// own value wins when both define the same name.
@Controller('/stacks', ['Stacks'])
@RequireAuth()
class StacksApi {
  @Get('/', summary: 'List stacks, optionally for one project')
  Future<Map<String, Object?>> list(
    StacksService stacks,
    RequestContext ctx,
    int? projectId,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await stacks.listForUser(user, projectId: projectId);
    return <String, Object?>{
      'results': result.map((s) => s.toJson()).toList(),
    };
  }

  @Post('/', summary: 'Create a stack in a project')
  Future<Map<String, Object?>> create(
    CreateStackForm form,
    StacksService stacks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final stack = await stacks.create(
      user,
      projectId: form.projectId.value!,
      name: form.name.value!,
      description: form.description.value,
    );
    return stack.toJson();
  }

  @Get('/{id}', summary: 'Get a stack')
  Future<Map<String, Object?>> retrieve(
    int id,
    StacksService stacks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    return (await stacks.findForUser(user, id)).toJson();
  }

  @Patch('/{id}', summary: 'Rename or describe a stack')
  Future<Map<String, Object?>> update(
    int id,
    UpdateStackForm form,
    StacksService stacks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final stack = await stacks.update(
      user,
      id,
      name: form.name.value,
      description: form.description.value,
    );
    return stack.toJson();
  }

  @Delete('/{id}',
      summary: 'Delete a stack and its env vars; its apps are kept, ungrouped')
  Future<Map<String, Object?>> delete(
    int id,
    StacksService stacks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await stacks.delete(user, id);
    return <String, Object?>{'detail': 'Stack deleted.'};
  }

  @Get('/{id}/apps', summary: 'List the apps in a stack')
  Future<Map<String, Object?>> apps(
    int id,
    StacksService stacks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await stacks.apps(user, id);
    return <String, Object?>{
      'results': result.map((a) => a.toJson()).toList(),
    };
  }

  // ── Env vars ─────────────────────────────────────────────────────────

  @Get('/{id}/envs', summary: 'List the env vars a stack shares with its apps')
  Future<Map<String, Object?>> listEnvs(
    int id,
    StacksService stacks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await stacks.listEnvs(user, id);
    return <String, Object?>{'results': result.map(_envJson).toList()};
  }

  @Post('/{id}/envs', summary: 'Set a stack env var')
  Future<Map<String, Object?>> setEnv(
    int id,
    EnvVarForm form,
    StacksService stacks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final env = await stacks.upsertEnv(
      user,
      id,
      name: form.name.value!,
      value: form.value.value,
      isSecret: form.isSecret.value ?? false,
    );
    return _envJson(env);
  }

  /// Body: `{ "entries": [{"name": "KEY", "value": "val", "isSecret": false}, …] }`
  @Post('/{id}/envs/bulk',
      summary: 'Bulk-upsert stack env vars from a .env file')
  Future<Map<String, Object?>> bulkEnvs(
    int id,
    BulkEnvVarForm form,
    StacksService stacks,
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
      if (name.isEmpty) continue;
      await stacks.upsertEnv(user, id,
          name: name,
          value: item['value']?.toString() ?? '',
          isSecret: item['isSecret'] == true);
      count++;
    }
    return <String, Object?>{'imported': count};
  }

  @Delete('/{id}/envs/{envId}', summary: 'Delete a stack env var')
  Future<Map<String, Object?>> deleteEnv(
    int id,
    int envId,
    StacksService stacks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await stacks.deleteEnv(user, id, envId);
    return <String, Object?>{'detail': 'Env var deleted.'};
  }
}
