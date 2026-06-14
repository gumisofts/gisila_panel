import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/models/models.dart';

/// Team roles, ordered lowest → highest privilege. The integer [TeamRole.index]
/// is the rank used for comparisons.
///
///  * viewer    — read-only access to the team's apps/projects.
///  * developer — deploy, start/restart, edit env vars & domains, create apps
///                and projects.
///  * admin     — everything a developer can, plus stop apps, delete apps and
///                projects, and manage team members.
///  * owner     — full control, including deleting the team.
enum TeamRole { viewer, developer, admin, owner }

TeamRole? _parseRole(String? role) => switch (role) {
      'viewer' => TeamRole.viewer,
      'developer' => TeamRole.developer,
      'admin' => TeamRole.admin,
      'owner' => TeamRole.owner,
      _ => null,
    };

/// The acting [User] resolved from the request principal.
User currentUser(RequestContext ctx) => ctx.principal!.claims['user'] as User;

/// Throw [Forbidden] unless the caller is a platform superuser. Used to gate
/// node-global infrastructure (managed services, Postgres instances, mail)
/// that isn't owned by any single team.
void requireSuperuser(RequestContext ctx) {
  if (currentUser(ctx).isSuperuser != true) {
    throw Forbidden('Superuser access required for this action.');
  }
}

/// Resolve [userId]'s [TeamRole] within [teamId], or `null` if not a member.
Future<TeamRole?> resolveTeamRole(Database db, int userId, int teamId) async {
  final member = await Query<TeamMember>(TeamMemberTable.metadata)
      .where(TeamMemberTable.teamId.eq(teamId))
      .where(TeamMemberTable.userId.eq(userId))
      .first(db.context());
  return _parseRole(member?.role);
}

/// Throw [Forbidden] unless [user] holds at least the [min] role in [teamId].
///
/// Platform superusers bypass team RBAC entirely. A non-member is rejected the
/// same way an under-privileged member is, so team membership is never leaked.
Future<void> requireTeamRole(
  Database db,
  User user,
  int teamId,
  TeamRole min,
) async {
  if (user.isSuperuser == true) return;
  final role = await resolveTeamRole(db, user.id!, teamId);
  if (role == null) {
    throw Forbidden('You do not have access to this team.');
  }
  if (role.index < min.index) {
    throw Forbidden(
      'This action requires the "${min.name}" role or higher; '
      'your role is "${role.name}".',
    );
  }
}
