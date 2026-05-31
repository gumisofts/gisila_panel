import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';

/// Stateless JWT helper. Secret + lifetime come from the environment.
class JWTAuth {
  static String _secret() =>
      env.getOrElse('JWT_SECRET', () => 'change-me-to-a-random-secret-please');
  static Duration _expiry() => Duration(
        days: int.parse(env.getOrElse('JWT_EXPIRE_DAYS', () => '14')),
      );

  /// Signs a JWT for [user] and returns the token string.
  static String sign(User user) => JWT(
        <String, Object?>{
          'id': user.id,
          'email': user.email ?? '',
          'isStaff': user.isStaff,
          'isSuperuser': user.isSuperuser,
        },
      ).sign(SecretKey(_secret()), expiresIn: _expiry());

  static bool verify(String token) {
    try {
      JWT.verify(token, SecretKey(_secret()));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> decode(String token) =>
      JWT.decode(token).payload as Map<String, dynamic>;

  static Map<String, dynamic>? decodeAndVerify(String token) =>
      verify(token) ? decode(token) : null;
}
