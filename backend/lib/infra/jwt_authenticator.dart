import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/jwt.dart';
import 'package:gisila_panel/utils/api_tokens.dart';

/// JWT + API-token [Authenticator] for the gisila panel.
///
/// Resolution order:
/// 1. `Authorization: Bearer <jwt>`   → JWT signed by [JWTAuth].
/// 2. `Authorization: Bearer gsl_<…>` → static API token (`ApiToken` table).
/// 3. `X-API-Token: gsl_<…>`          → same as above, for CLI usage.
///
/// The matched [User] is exposed on `ctx.principal!.claims['user']`.
class JwtAuthenticator extends Authenticator {
  const JwtAuthenticator({required this.database});

  final Database database;

  @override
  Future<Principal?> authenticate(Request request) async {
    final raw = _extractToken(request);
    if (raw == null) return null;

    User? user;
    if (raw.startsWith('gsl_')) {
      user = await _userForApiToken(raw);
    } else {
      user = await _userForJwt(raw);
    }

    if (user == null || user.isActive == false) return null;

    return Principal(
      id: user.id!.toString(),
      roles: <String>{
        if (user.isStaff == true) 'staff',
        if (user.isSuperuser == true) 'superuser',
      },
      claims: <String, Object?>{'user': user},
    );
  }

  String? _extractToken(Request request) {
    final auth = request.headers['authorization'];
    if (auth != null) {
      final parts = auth.split(RegExp(r'\s+'));
      if (parts.length == 2 && parts.first.toLowerCase() == 'bearer') {
        return parts.last;
      }
    }
    final apiHeader = request.headers['x-api-token'];
    if (apiHeader != null && apiHeader.isNotEmpty) return apiHeader;
    return null;
  }

  Future<User?> _userForJwt(String token) => userForSessionJwt(database, token);

  Future<User?> _userForApiToken(String token) async {
    final hash = ApiTokenCodec.hash(token);
    final apiToken = await Query<ApiToken>(ApiTokenTable.metadata)
        .where(ApiTokenTable.tokenHash.eq(hash))
        .first(database.context());
    if (apiToken == null) return null;
    if (apiToken.expiresAt != null &&
        apiToken.expiresAt!.isBefore(DateTime.now().toUtc())) {
      return null;
    }
    // Fire-and-forget last_used_at update.
    Query<ApiToken>(ApiTokenTable.metadata)
        .where(ApiTokenTable.id.eq(apiToken.id!))
        .update({'lastUsedAt': DateTime.now().toUtc().toIso8601String()})
        .run(database.context())
        .ignore();

    return Query<User>(UserTable.metadata)
        .where(UserTable.id.eq(apiToken.userId))
        .first(database.context());
  }
}

/// The active [User] a session JWT belongs to, or null when the token is
/// invalid, expired, an MFA challenge, revoked by the user's
/// `sessionsValidAfter`, or the account is gone or deactivated.
///
/// Shared by the REST authenticator and the log WebSockets so both accept
/// exactly the same tokens.
Future<User?> userForSessionJwt(Database database, String token) async {
  final payload = JWTAuth.decodeSession(token);
  final userId = payload?['id'];
  if (payload == null || userId is! int) return null;
  final user = await Query<User>(UserTable.metadata)
      .where(UserTable.id.eq(userId))
      .first(database.context());
  if (user == null || user.isActive == false) return null;
  if (JWTAuth.isRevoked(payload, user)) return null;
  return user;
}
