import 'dart:convert';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/slugs.dart';

class ProjectsService extends Service {
  Database get _db => db<Database>();

  Future<List<Project>> listForUser(User user, {int? teamId}) async {
    final memberships = await Query<TeamMember>(TeamMemberTable.metadata)
        .where(TeamMemberTable.userId.eq(user.id!))
        .all(_db.context());
    final teamIds = memberships.map((m) => m.teamId).whereType<int>().toList();
    if (teamIds.isEmpty) return <Project>[];
    var q = Query<Project>(ProjectTable.metadata)
        .where(ProjectTable.teamId.inList(teamIds));
    if (teamId != null) q = q.where(ProjectTable.teamId.eq(teamId));
    return q.all(_db.context());
  }

  Future<Project> create(
    User actor, {
    required int teamId,
    required String name,
    String? description,
  }) async {
    // Creating projects is a developer-level action.
    await requireTeamRole(_db, actor, teamId, TeamRole.developer);
    return Query<Project>(ProjectTable.metadata).insert(<String, Object?>{
      'teamId': teamId,
      'name': name,
      'slug': Slug.make(name),
      'description': description,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
  }

  Future<Project> findForUser(User user, int projectId) async {
    final project = await Query<Project>(ProjectTable.metadata)
        .where(ProjectTable.id.eq(projectId))
        .first(_db.context());
    if (project == null) throw NotFound('Project not found.');
    await _ensureTeamAccess(user, project.teamId);
    return project;
  }

  Future<Project> update(
    User actor,
    int projectId, {
    String? name,
    String? description,
  }) async {
    final project = await findForUser(actor, projectId);
    await requireTeamRole(_db, actor, project.teamId, TeamRole.developer);
    final payload = <String, Object?>{
      if (name != null) 'name': name,
      if (description != null) 'description': description,
    };
    if (payload.isEmpty) {
      throw BadRequest('No updatable fields provided.');
    }
    final rows = await Query<Project>(ProjectTable.metadata)
        .where(ProjectTable.id.eq(project.id!))
        .update(payload)
        .run(_db.context());
    return rows.first;
  }

  /// Remove a project and every app it contains.
  ///
  /// Deleting the project row would cascade to its apps, orphaning their
  /// host-side resources (systemd units, Linux users, work dirs, …). Instead we
  /// mark the child apps `deleting` for immediate UI feedback and hand off to
  /// the worker, which tears down each app's host resources before dropping the
  /// project (and its cascaded rows).
  Future<void> delete(User actor, int projectId) async {
    final project = await findForUser(actor, projectId);
    // Deleting a project (and all its apps) is an admin-level action.
    await requireTeamRole(_db, actor, project.teamId, TeamRole.admin);
    await Query<App>(AppTable.metadata)
        .where(AppTable.projectId.eq(project.id!))
        .update(<String, Object?>{
      'status': 'deleting',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }).run(_db.context());
    await RedisClient.instance.rpush(
      'gisila:queue:teardown',
      jsonEncode(<String, Object?>{
        'scope': 'project',
        'id': project.id,
        'requestedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> _ensureTeamAccess(User user, int teamId) async {
    // Match [requireTeamRole]: platform superusers bypass team membership.
    if (user.isSuperuser == true) return;
    final member = await Query<TeamMember>(TeamMemberTable.metadata)
        .where(TeamMemberTable.teamId.eq(teamId))
        .where(TeamMemberTable.userId.eq(user.id!))
        .first(_db.context());
    if (member == null) {
      throw Forbidden('You do not have access to this team.');
    }
  }
}
