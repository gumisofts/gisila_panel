import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/infra/secret_box.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';
import 'package:gisila_panel/services/projects_service.dart';
import 'package:gisila_panel/utils/slugs.dart';

/// The env an app in a stack is deployed with: the stack's vars as the base,
/// with the app's own vars on top. The app's value wins on a name clash.
Map<String, String> mergeStackEnv(
  Map<String, String> stackEnv,
  Map<String, String> appEnv,
) =>
    <String, String>{...stackEnv, ...appEnv};

/// The decrypted env vars of [stackId], by name. Used by the deploy worker,
/// which has no request context.
Future<Map<String, String>> loadStackEnv(Database db, int stackId) async {
  final rows = await Query<StackEnvVar>(StackEnvVarTable.metadata)
      .where(StackEnvVarTable.stackId.eq(stackId))
      .all(db.context());
  return {for (final e in rows) e.name: e.opened().value ?? ''};
}

/// Stacks group the apps of one project and give them a shared set of env
/// vars. Reading takes team membership; every change takes the developer role,
/// the same as editing an app's own env vars.
class StacksService extends Service {
  Database get _db => db<Database>();

  Future<List<Stack>> listForUser(User user, {int? projectId}) async {
    var q = Query<Stack>(StackTable.metadata);
    if (user.isSuperuser != true) {
      final projectsSvc = ProjectsService()..attach(ctx);
      final projects = await projectsSvc.listForUser(user);
      final ids = projects.map((p) => p.id).whereType<int>().toList();
      if (ids.isEmpty) return <Stack>[];
      q = q.where(StackTable.projectId.inList(ids));
    }
    if (projectId != null) q = q.where(StackTable.projectId.eq(projectId));
    return q.orderBy(StackTable.name).all(_db.context());
  }

  Future<Stack> findForUser(User user, int stackId) async {
    final stack = await Query<Stack>(StackTable.metadata)
        .where(StackTable.id.eq(stackId))
        .first(_db.context());
    if (stack == null) throw NotFound('Stack not found.');
    final projectsSvc = ProjectsService()..attach(ctx);
    try {
      await projectsSvc.findForUser(user, stack.projectId);
    } on Forbidden {
      // Don't confirm a stack id exists in a team the caller can't see.
      throw NotFound('Stack not found.');
    }
    return stack;
  }

  Future<Stack> _requireRole(User user, int stackId, TeamRole min) async {
    final stack = await findForUser(user, stackId);
    final project = await Query<Project>(ProjectTable.metadata)
        .where(ProjectTable.id.eq(stack.projectId))
        .first(_db.context());
    if (project == null) throw NotFound('Stack not found.');
    await requireTeamRole(_db, user, project.teamId, min);
    return stack;
  }

  Future<Stack> create(
    User actor, {
    required int projectId,
    required String name,
    String? description,
  }) async {
    final projectsSvc = ProjectsService()..attach(ctx);
    final project = await projectsSvc.findForUser(actor, projectId);
    await requireTeamRole(_db, actor, project.teamId, TeamRole.developer);
    return Query<Stack>(StackTable.metadata).insert(<String, Object?>{
      'projectId': project.id,
      'name': name,
      'slug': Slug.make(name),
      'description': description,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
  }

  Future<Stack> update(
    User actor,
    int stackId, {
    String? name,
    String? description,
  }) async {
    final stack = await _requireRole(actor, stackId, TeamRole.developer);
    if (name == null && description == null) {
      throw BadRequest('No updatable fields provided.');
    }
    final rows = await Query<Stack>(StackTable.metadata)
        .where(StackTable.id.eq(stack.id!))
        .update(<String, Object?>{
      if (name != null) ...{'name': name, 'slug': Slug.make(name)},
      if (description != null) 'description': description,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }).run(_db.context());
    return rows.first;
  }

  /// Removes the stack and its env vars. Its apps are kept and become
  /// ungrouped. They keep running with the env they were last deployed with,
  /// and lose the stack's vars on their next deployment.
  Future<void> delete(User actor, int stackId) async {
    final stack = await _requireRole(actor, stackId, TeamRole.developer);
    await Query<Stack>(StackTable.metadata)
        .where(StackTable.id.eq(stack.id!))
        .delete()
        .run(_db.context());
  }

  Future<List<App>> apps(User user, int stackId) async {
    final stack = await findForUser(user, stackId);
    return Query<App>(AppTable.metadata)
        .where(AppTable.stackId.eq(stack.id!))
        .orderBy(AppTable.name)
        .all(_db.context());
  }

  // ── Env vars ─────────────────────────────────────────────────────────

  Future<List<StackEnvVar>> listEnvs(User actor, int stackId) async {
    final stack = await findForUser(actor, stackId);
    return _envs(stack.id!);
  }

  Future<List<StackEnvVar>> _envs(int stackId) async {
    final rows = await Query<StackEnvVar>(StackEnvVarTable.metadata)
        .where(StackEnvVarTable.stackId.eq(stackId))
        .orderBy(StackEnvVarTable.name)
        .all(_db.context());
    return [for (final e in rows) e.opened()];
  }

  Future<StackEnvVar> upsertEnv(
    User actor,
    int stackId, {
    required String name,
    String? value,
    bool isSecret = false,
  }) async {
    final stack = await _requireRole(actor, stackId, TeamRole.developer);
    final existing = await Query<StackEnvVar>(StackEnvVarTable.metadata)
        .where(StackEnvVarTable.stackId.eq(stack.id!))
        .where(StackEnvVarTable.name.eq(name))
        .first(_db.context());

    final now = DateTime.now().toUtc().toIso8601String();
    final sealed =
        SecretBox.instance.sealOrNull(value, SecretBox.stackEnvVarValue);
    if (existing == null) {
      final row = await Query<StackEnvVar>(StackEnvVarTable.metadata)
          .insert(<String, Object?>{
        'stackId': stack.id,
        'name': name,
        'value': sealed,
        'isSecret': isSecret,
        'updatedAt': now,
      }).one(_db.context());
      return row.opened();
    }
    final rows = await Query<StackEnvVar>(StackEnvVarTable.metadata)
        .where(StackEnvVarTable.id.eq(existing.id!))
        .update(<String, Object?>{
      // An omitted value keeps the stored one, as for an app's env vars.
      if (value != null) 'value': sealed,
      'isSecret': isSecret,
      'updatedAt': now,
    }).run(_db.context());
    return rows.first.opened();
  }

  Future<void> deleteEnv(User actor, int stackId, int envId) async {
    final stack = await _requireRole(actor, stackId, TeamRole.developer);
    await Query<StackEnvVar>(StackEnvVarTable.metadata)
        .where(StackEnvVarTable.id.eq(envId))
        .where(StackEnvVarTable.stackId.eq(stack.id!))
        .delete()
        .run(_db.context());
  }

  /// The stack vars app [appId] inherits, or null when it is in no stack.
  /// Each var says whether the app's own env overrides it.
  Future<({Stack stack, List<StackEnvVar> vars, Set<String> overridden})?>
      inheritedForApp(User actor, int appId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.findForUser(actor, appId);
    final stackId = app.stackId;
    if (stackId == null) return null;
    final stack = await Query<Stack>(StackTable.metadata)
        .where(StackTable.id.eq(stackId))
        .first(_db.context());
    if (stack == null) return null;
    final own = await Query<EnvVar>(EnvVarTable.metadata)
        .where(EnvVarTable.appId.eq(app.id!))
        .all(_db.context());
    return (
      stack: stack,
      vars: await _envs(stackId),
      overridden: {for (final e in own) e.name},
    );
  }
}
