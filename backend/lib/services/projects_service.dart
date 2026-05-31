import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
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
    await _ensureTeamAccess(actor, teamId);
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

  Future<void> delete(User actor, int projectId) async {
    final project = await findForUser(actor, projectId);
    await Query<Project>(ProjectTable.metadata)
        .where(ProjectTable.id.eq(project.id!))
        .delete()
        .run(_db.context());
  }

  Future<void> _ensureTeamAccess(User user, int teamId) async {
    final member = await Query<TeamMember>(TeamMemberTable.metadata)
        .where(TeamMemberTable.teamId.eq(teamId))
        .where(TeamMemberTable.userId.eq(user.id!))
        .first(_db.context());
    if (member == null) {
      throw Forbidden('You do not have access to this team.');
    }
  }
}
