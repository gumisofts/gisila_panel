import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/jwt.dart';
import 'package:gisila_panel/utils/passwords.dart';
import 'package:gisila_panel/utils/slugs.dart';

/// Authentication + bootstrap business logic.
class AuthService extends Service {
  Database get _db => db<Database>();

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<({User user, String accessToken})> login({
    required String email,
    required String password,
  }) async {
    final user = await Query<User>(UserTable.metadata)
        .where(UserTable.email.eq(email))
        .first(_db.context());

    if (user == null ||
        user.password == null ||
        !PasswordHasher.verify(password, user.password!)) {
      throw Unauthorized('Invalid email or password.');
    }
    if (user.isActive == false) {
      throw Forbidden('This account is inactive.');
    }

    return (user: user, accessToken: JWTAuth.sign(user));
  }

  // ── User management (superuser only) ─────────────────────────────────────

  Future<List<User>> listUsers() async {
    return Query<User>(UserTable.metadata)
        .orderBy(UserTable.createdAt)
        .all(_db.context());
  }

  Future<({User user, Team team})> createUser({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    bool isSuperuser = false,
  }) async {
    final existing = await Query<User>(UserTable.metadata)
        .where(UserTable.email.eq(email))
        .first(_db.context());
    if (existing != null) {
      throw Conflict(
        'An account with this email already exists.',
        code: 'email_taken',
      );
    }

    final now = DateTime.now().toUtc();

    final user = await Query<User>(UserTable.metadata).insert(<String, Object?>{
      'email': email,
      'password': PasswordHasher.hash(password),
      'firstName': firstName,
      'lastName': lastName,
      'isActive': true,
      'isStaff': false,
      'isSuperuser': isSuperuser,
      'isEmailVerified': false,
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    final teamSlug = Slug.make('${firstName ?? ''}-${user.id}-team');
    final team = await Query<Team>(TeamTable.metadata).insert(<String, Object?>{
      'name': '${firstName ?? email.split('@').first}\'s Team',
      'slug': teamSlug,
      'ownerId': user.id,
      'plan': 'free',
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await Query<TeamMember>(TeamMemberTable.metadata).insert(<String, Object?>{
      'teamId': team.id,
      'userId': user.id,
      'role': 'owner',
      'invitedAt': now.toIso8601String(),
      'acceptedAt': now.toIso8601String(),
    }).run(_db.context());

    return (user: user, team: team);
  }

  Future<User> updateUser(
    int id, {
    String? firstName,
    String? lastName,
    bool? isActive,
    bool? isSuperuser,
  }) async {
    final updates = <String, Object?>{
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (isActive != null) 'isActive': isActive,
      if (isSuperuser != null) 'isSuperuser': isSuperuser,
    };
    final rows = await Query<User>(UserTable.metadata)
        .where(UserTable.id.eq(id))
        .update(updates)
        .run(_db.context());
    return rows.first;
  }

  Future<void> deleteUser(int id) async {
    await Query<User>(UserTable.metadata)
        .where(UserTable.id.eq(id))
        .delete()
        .run(_db.context());
  }

  // ── Password ──────────────────────────────────────────────────────────────

  Future<void> changePassword(
    User current, {
    required String oldPassword,
    required String newPassword,
  }) async {
    if (current.password == null ||
        !PasswordHasher.verify(oldPassword, current.password!)) {
      throw BadRequest('Old password is incorrect.', code: 'invalid_password');
    }
    await Query<User>(UserTable.metadata)
        .where(UserTable.id.eq(current.id!))
        .update(<String, Object?>{
      'password': PasswordHasher.hash(newPassword),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }).run(_db.context());
  }
}
