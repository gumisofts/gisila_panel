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

  Future<User?> _userForJwt(String token) async {
    final payload = JWTAuth.decodeAndVerify(token);
    if (payload == null) return null;
    final userId = payload['id'] as int?;
    if (userId == null) return null;
    return Query<User>(UserTable.metadata)
        .where(UserTable.id.eq(userId))
        .first(database.context());
  }

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
