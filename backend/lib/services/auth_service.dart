import 'dart:convert';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/infra/client_ip.dart';
import 'package:gisila_panel/infra/login_throttle.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/jwt.dart';
import 'package:gisila_panel/utils/passwords.dart';
import 'package:gisila_panel/utils/slugs.dart';
import 'package:gisila_panel/utils/totp.dart';

/// Outcome of a correct email + password: either a session, or — for an
/// account with a second factor — a challenge to complete with a code.
sealed class LoginResult {}

final class LoginSession extends LoginResult {
  LoginSession(this.user, this.accessToken);
  final User user;
  final String accessToken;
}

final class LoginMfaRequired extends LoginResult {
  LoginMfaRequired(this.challenge);
  final String challenge;
}

/// Authentication + bootstrap business logic.
class AuthService extends Service {
  Database get _db => db<Database>();

  // ── Login ─────────────────────────────────────────────────────────────────

  final _throttle = LoginThrottle();

  Future<LoginResult> login({
    required String email,
    required String password,
    String? ip,
  }) async {
    await _throttle.check(email, ip);

    final user = await Query<User>(UserTable.metadata)
        .where(UserTable.email.eq(email))
        .first(_db.context());

    final stored = user?.password;
    var ok = false;
    if (stored == null) {
      // Spend the same time as a real check so the response time doesn't
      // tell an attacker which emails have accounts.
      await PasswordHasher.dummyVerifyAsync(password);
    } else {
      ok = await PasswordHasher.verifyAsync(password, stored);
    }
    if (!ok) {
      await _throttle.recordFailure(email, ip);
      throw Unauthorized('Invalid email or password.');
    }
    if (user!.isActive == false) {
      throw Forbidden('This account is inactive.');
    }
    await _throttle.recordSuccess(email, ip);

    // Upgrade a legacy (single SHA-256) or weaker hash now that we have the
    // plaintext — the only moment that's possible.
    if (PasswordHasher.needsRehash(stored!)) {
      await Query<User>(UserTable.metadata)
          .where(UserTable.id.eq(user.id!))
          .update({'password': await PasswordHasher.hashAsync(password)})
          .run(_db.context());
    }

    if (await _confirmedTotp(user.id!) != null) {
      return LoginMfaRequired(JWTAuth.signMfaChallenge(user));
    }
    return LoginSession(user, JWTAuth.sign(user));
  }

  /// Exchange an MFA [challenge] plus a TOTP or recovery [code] for a session.
  Future<LoginSession> completeMfaLogin({
    required String challenge,
    required String code,
    String? ip,
  }) async {
    final payload = JWTAuth.decodeMfaChallenge(challenge);
    final userId = payload?['id'];
    if (payload == null || userId is! int) {
      throw Unauthorized('This sign-in has expired. Start again.');
    }
    final account = 'mfa:$userId';
    await _throttle.check(account, ip);

    final user = await Query<User>(UserTable.metadata)
        .where(UserTable.id.eq(userId))
        .first(_db.context());
    // A password change since the challenge was issued voids it as well.
    if (user == null ||
        user.isActive == false ||
        JWTAuth.isRevoked(payload, user)) {
      throw Unauthorized('This sign-in has expired. Start again.');
    }
    final totp = await _confirmedTotp(userId);
    if (totp == null) {
      // 2FA was turned off between the two steps: the password was right.
      return LoginSession(user, JWTAuth.sign(user));
    }
    if (!await _consumeSecondFactor(totp, code)) {
      await _throttle.recordFailure(account, ip);
      throw Unauthorized('Invalid authentication code.');
    }
    await _throttle.recordSuccess(account, ip);
    return LoginSession(user, JWTAuth.sign(user));
  }

  // ── Audit ───────────────────────────────────────────────────────────────

  /// Record a security event in the audit log. The audit middleware skips
  /// `/auth/*` (it would log every login attempt as an anonymous mutation), so
  /// the events worth keeping are written here explicitly.
  Future<void> recordEvent(
    int actorId,
    String action, {
    int? targetUserId,
  }) async {
    try {
      final request = ctx.request;
      await Query<AuditLog>(AuditLogTable.metadata).insert(<String, Object?>{
        'actorId': actorId,
        'action': action,
        'targetType': 'user',
        'targetId': '${targetUserId ?? actorId}',
        'ipAddress': clientIp(request),
        'userAgent': request.headers['user-agent'],
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }).run(_db.context());
    } catch (_) {
      // Auditing must never fail the action it describes.
    }
  }

  // ── Sessions ──────────────────────────────────────────────────────────────

  /// Invalidate every session token [user] holds and return a fresh one for
  /// the caller, so "sign out other sessions" keeps this one signed in.
  Future<String> revokeSessions(User user) async {
    final updated = await _revokeSessionsOf(user.id!);
    return JWTAuth.sign(updated);
  }

  Future<User> _revokeSessionsOf(int userId) async {
    final rows = await Query<User>(UserTable.metadata)
        .where(UserTable.id.eq(userId))
        .update({
      'sessionsValidAfter': JWTAuth.revocationInstant().toIso8601String(),
    }).run(_db.context());
    return rows.first;
  }

  // ── Two-factor authentication (TOTP) ──────────────────────────────────────

  Future<UserTotp?> _totpRow(int userId) => Query<UserTotp>(UserTotpTable.metadata)
      .where(UserTotpTable.userId.eq(userId))
      .first(_db.context());

  Future<UserTotp?> _confirmedTotp(int userId) async {
    final row = await _totpRow(userId);
    return row?.confirmedAt == null ? null : row;
  }

  /// Ids of users with 2FA turned on (for the superuser's user list).
  Future<Set<int>> userIdsWithTotp() async {
    final rows = await Query<UserTotp>(UserTotpTable.metadata)
        .where(UserTotpTable.confirmedAt.isNotNull)
        .all(_db.context());
    return rows.map((r) => r.userId).toSet();
  }

  Future<({bool enabled, int recoveryCodesRemaining})> totpStatus(
      User user) async {
    final row = await _confirmedTotp(user.id!);
    return (
      enabled: row != null,
      recoveryCodesRemaining: row == null ? 0 : _recoveryDigests(row).length,
    );
  }

  /// Start (or restart) 2FA setup: store a new, unconfirmed secret and return
  /// it with the `otpauth://` URI for the authenticator app.
  Future<({String secret, String otpauthUri})> beginTotpSetup(
    User user, {
    required String password,
  }) async {
    await _requirePassword(user, password);
    if (await _confirmedTotp(user.id!) != null) {
      throw Conflict('Two-factor authentication is already on.',
          code: 'totp_enabled');
    }
    final secret = Totp.generateSecret();
    await Query<UserTotp>(UserTotpTable.metadata)
        .where(UserTotpTable.userId.eq(user.id!))
        .delete()
        .run(_db.context());
    await Query<UserTotp>(UserTotpTable.metadata).insert(<String, Object?>{
      'userId': user.id,
      'secret': secret,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).run(_db.context());
    return (
      secret: secret,
      otpauthUri: Totp.provisioningUri(secret: secret, account: user.email ?? ''),
    );
  }

  /// Confirm setup with a first [code] from the app. Turns 2FA on, signs out
  /// every other session (none of them passed the second factor), and returns
  /// the recovery codes — shown this once — plus a fresh token for the caller.
  Future<({List<String> recoveryCodes, String accessToken})> enableTotp(
    User user, {
    required String code,
  }) async {
    final row = await _totpRow(user.id!);
    if (row == null || row.confirmedAt != null) {
      throw BadRequest('Start two-factor setup first.', code: 'totp_not_pending');
    }
    final step = Totp.verify(row.secret, code);
    if (step == null) {
      throw BadRequest('That code is not valid. Check the time on your device.',
          code: 'invalid_code');
    }
    final codes = RecoveryCodes.generate();
    await Query<UserTotp>(UserTotpTable.metadata)
        .where(UserTotpTable.id.eq(row.id!))
        .update(<String, Object?>{
      'confirmedAt': DateTime.now().toUtc().toIso8601String(),
      'lastUsedStep': step,
      'recoveryCodes': jsonEncode(codes.map(RecoveryCodes.digest).toList()),
    }).run(_db.context());
    return (recoveryCodes: codes, accessToken: await revokeSessions(user));
  }

  /// Turn 2FA off. Needs the password and a current code (or recovery code),
  /// so a hijacked session alone can't strip the second factor.
  Future<void> disableTotp(
    User user, {
    required String password,
    required String code,
  }) async {
    await _requirePassword(user, password);
    final row = await _confirmedTotp(user.id!);
    if (row == null) return;
    if (!await _consumeSecondFactor(row, code)) {
      throw BadRequest('Invalid authentication code.', code: 'invalid_code');
    }
    await _deleteTotp(user.id!);
  }

  /// Replace the recovery codes (all old ones stop working).
  Future<List<String>> regenerateRecoveryCodes(
    User user, {
    required String code,
  }) async {
    final row = await _confirmedTotp(user.id!);
    if (row == null) {
      throw BadRequest('Two-factor authentication is off.', code: 'totp_disabled');
    }
    if (!await _consumeSecondFactor(row, code, allowRecovery: false)) {
      throw BadRequest('Invalid authentication code.', code: 'invalid_code');
    }
    final codes = RecoveryCodes.generate();
    await Query<UserTotp>(UserTotpTable.metadata)
        .where(UserTotpTable.id.eq(row.id!))
        .update(<String, Object?>{
      'recoveryCodes': jsonEncode(codes.map(RecoveryCodes.digest).toList()),
    }).run(_db.context());
    return codes;
  }

  /// Superuser escape hatch for a user who lost both their device and their
  /// recovery codes. Also signs that user out everywhere.
  Future<void> resetTotp(int userId) async {
    await _deleteTotp(userId);
    await _revokeSessionsOf(userId);
  }

  Future<void> _deleteTotp(int userId) => Query<UserTotp>(UserTotpTable.metadata)
      .where(UserTotpTable.userId.eq(userId))
      .delete()
      .run(_db.context());

  /// Check [code] as a TOTP code, then (if [allowRecovery]) as a recovery
  /// code, and burn whichever matched so it can't be used again.
  Future<bool> _consumeSecondFactor(
    UserTotp row,
    String code, {
    bool allowRecovery = true,
  }) async {
    // Both updates are compare-and-swap: of two concurrent requests carrying
    // the same code, only the one whose update matches a row gets in.
    final step = Totp.verify(row.secret, code, lastUsedStep: row.lastUsedStep);
    if (step != null) {
      final rows = await Query<UserTotp>(UserTotpTable.metadata)
          .where(UserTotpTable.id.eq(row.id!))
          .where(UserTotpTable.lastUsedStep.isNull
              .or(UserTotpTable.lastUsedStep.lt(step)))
          .update(<String, Object?>{'lastUsedStep': step}).run(_db.context());
      return rows.isNotEmpty;
    }
    if (!allowRecovery || row.recoveryCodes == null) return false;
    final digests = _recoveryDigests(row);
    if (!digests.remove(RecoveryCodes.digest(code))) return false;
    final rows = await Query<UserTotp>(UserTotpTable.metadata)
        .where(UserTotpTable.id.eq(row.id!))
        .where(UserTotpTable.recoveryCodes.eq(row.recoveryCodes!))
        .update(<String, Object?>{'recoveryCodes': jsonEncode(digests)})
        .run(_db.context());
    return rows.isNotEmpty;
  }

  List<String> _recoveryDigests(UserTotp row) {
    final raw = row.recoveryCodes;
    if (raw == null || raw.isEmpty) return <String>[];
    return (jsonDecode(raw) as List).cast<String>().toList();
  }

  Future<void> _requirePassword(User user, String password) async {
    final stored = user.password;
    if (stored == null || !await PasswordHasher.verifyAsync(password, stored)) {
      throw BadRequest('Password is incorrect.', code: 'invalid_password');
    }
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
      'password': await PasswordHasher.hashAsync(password),
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
    // Deactivating signs the account out everywhere, so reactivating it later
    // doesn't bring old tokens back to life.
    if (isActive == false) {
      updates['sessionsValidAfter'] =
          JWTAuth.revocationInstant().toIso8601String();
    }
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

  /// Change [current]'s password, sign out all their other sessions, and
  /// return a fresh token for this one.
  Future<String> changePassword(
    User current, {
    required String oldPassword,
    required String newPassword,
  }) async {
    final stored = current.password;
    if (stored == null ||
        !await PasswordHasher.verifyAsync(oldPassword, stored)) {
      throw BadRequest('Old password is incorrect.', code: 'invalid_password');
    }
    final rows = await Query<User>(UserTable.metadata)
        .where(UserTable.id.eq(current.id!))
        .update(<String, Object?>{
      'password': await PasswordHasher.hashAsync(newPassword),
      'sessionsValidAfter': JWTAuth.revocationInstant().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }).run(_db.context());
    return JWTAuth.sign(rows.first);
  }
}
