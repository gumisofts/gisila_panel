import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/slugs.dart';

class TeamsService extends Service {
  Database get _db => db<Database>();

  Future<List<Team>> listForUser(User user) async {
    final memberships = await Query<TeamMember>(TeamMemberTable.metadata)
        .where(TeamMemberTable.userId.eq(user.id!))
        .all(_db.context());
    if (memberships.isEmpty) return <Team>[];
    final teamIds = memberships.map((m) => m.teamId).whereType<int>().toList();
    return Query<Team>(TeamTable.metadata)
        .where(TeamTable.id.inList(teamIds))
        .all(_db.context());
  }

  Future<Team> create(User owner, {required String name, String? slug}) async {
    final now = DateTime.now().toUtc();
    final team = await Query<Team>(TeamTable.metadata).insert(<String, Object?>{
      'name': name,
      'slug': Slug.make(slug ?? name),
      'ownerId': owner.id,
      'plan': 'free',
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await Query<TeamMember>(TeamMemberTable.metadata).insert(<String, Object?>{
      'teamId': team.id,
      'userId': owner.id,
      'role': 'owner',
      'invitedAt': now.toIso8601String(),
      'acceptedAt': now.toIso8601String(),
    }).run(_db.context());

    return team;
  }

  Future<Team> findForUser(User user, int teamId) async {
    final team = await Query<Team>(TeamTable.metadata)
        .where(TeamTable.id.eq(teamId))
        .first(_db.context());
    if (team == null) throw NotFound('Team not found.');
    final isMember = await Query<TeamMember>(TeamMemberTable.metadata)
        .where(TeamMemberTable.teamId.eq(teamId))
        .where(TeamMemberTable.userId.eq(user.id!))
        .first(_db.context());
    if (isMember == null) {
      throw Forbidden('You are not a member of this team.');
    }
    return team;
  }

  Future<List<TeamMember>> members(int teamId) =>
      Query<TeamMember>(TeamMemberTable.metadata)
          .where(TeamMemberTable.teamId.eq(teamId))
          .all(_db.context());

  Future<TeamMember> invite(
    Team team, {
    required String email,
    String role = 'developer',
  }) async {
    final user = await Query<User>(UserTable.metadata)
        .where(UserTable.email.eq(email))
        .first(_db.context());
    if (user == null) {
      throw NotFound(
        'No registered user with that email yet — ask them to sign up first.',
      );
    }
    final existing = await Query<TeamMember>(TeamMemberTable.metadata)
        .where(TeamMemberTable.teamId.eq(team.id!))
        .where(TeamMemberTable.userId.eq(user.id!))
        .first(_db.context());
    if (existing != null) {
      throw Conflict('User is already a member of this team.');
    }
    return Query<TeamMember>(TeamMemberTable.metadata).insert(<String, Object?>{
      'teamId': team.id,
      'userId': user.id,
      'role': role,
      'invitedAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
  }
}
