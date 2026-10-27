import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';

/// JWT helper. Secret + lifetime come from the environment.
///
/// Two kinds of token share the secret but never each other's role:
/// - a **session** token (no `purpose` claim — every token issued before
///   purposes existed is one), accepted as a Bearer credential;
/// - an **MFA challenge** (`purpose: mfa`), issued by a correct password for
///   an account with a second factor and only good for completing that login.
class JWTAuth {
  static const _mfaPurpose = 'mfa';
  static const _mfaChallengeLifetime = Duration(minutes: 5);

  // Placeholders from .env.example and old code defaults. A panel signing with
  // one of these would accept tokens anyone can forge.
  static const _knownPlaceholders = {
    'change-me-to-a-random-secret-please',
    'secret',
    'change-me',
    'changeme',
  };

  static String? _cachedSecret;

  /// The signing secret. Throws [StateError] if `JWT_SECRET` is unset or a
  /// known placeholder: there is no safe default to fall back to.
  static String get secret => _cachedSecret ??= _resolveSecret();

  /// Fail fast at startup instead of on the first login.
  static void ensureConfigured() {
    final value = secret;
    if (value.length < 32) {
      logger.w('JWT_SECRET is shorter than 32 characters. Generate a new one '
          'with `head -c 32 /dev/urandom | base64`.');
    }
  }

  static String _resolveSecret() {
    final value = env['JWT_SECRET']?.trim() ?? '';
    if (value.isEmpty) {
      throw StateError('JWT_SECRET is not set. Refusing to sign or accept '
          'tokens without a secret: set it in /etc/gisila/.env '
          '(`head -c 32 /dev/urandom | base64`).');
    }
    if (_knownPlaceholders.contains(value)) {
      throw StateError('JWT_SECRET is still the placeholder value. Replace it '
          'with a random secret (`head -c 32 /dev/urandom | base64`).');
    }
    return value;
  }

  /// A key for another HMAC consumer (e.g. GisilaStudio) derived from the
  /// panel secret, so its tokens and the panel's can't be swapped.
  static String derivedSecret(String label) => sha256
      .convert(utf8.encode('gisila:$label\u0000$secret'))
      .toString();

  static Duration _expiry() => Duration(
        days: int.parse(env.getOrElse('JWT_EXPIRE_DAYS', () => '14')),
      );

  /// Signs a session JWT for [user] and returns the token string.
  ///
  /// `iatMs` is the issue time in milliseconds. The standard `iat` has whole
  /// seconds only, which can't order a token against a revocation made in the
  /// same second.
  static String sign(User user) => JWT(
        <String, Object?>{
          'id': user.id,
          'email': user.email ?? '',
          'isStaff': user.isStaff,
          'isSuperuser': user.isSuperuser,
          'iatMs': DateTime.now().millisecondsSinceEpoch,
        },
      ).sign(SecretKey(secret), expiresIn: _expiry());

  /// Signs a short-lived MFA challenge for [user]: proof the password was
  /// right, to be exchanged for a session along with a second-factor code.
  static String signMfaChallenge(User user) => JWT(
        <String, Object?>{
          'id': user.id,
          'purpose': _mfaPurpose,
          'iatMs': DateTime.now().millisecondsSinceEpoch,
        },
      ).sign(SecretKey(secret), expiresIn: _mfaChallengeLifetime);

  /// The payload of a valid session token, or null.
  /// Key for a signed-out session token in `revoked_sessions`.
  static String sessionTokenHash(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  static Map<String, dynamic>? decodeSession(String token) {
    final payload = _verified(token);
    if (payload == null || payload.containsKey('purpose')) return null;
    return payload;
  }

  /// The payload of a valid MFA challenge, or null.
  static Map<String, dynamic>? decodeMfaChallenge(String token) {
    final payload = _verified(token);
    if (payload == null || payload['purpose'] != _mfaPurpose) return null;
    return payload;
  }

  /// Whether a token [payload] was issued before [user] revoked their
  /// sessions (`sessionsValidAfter`). Tokens from before `iatMs` existed fall
  /// back to `iat`, rounded down — so one issued in the same second as a
  /// revocation counts as revoked — and one with neither is treated as
  /// revoked once revocation has been used.
  static bool isRevoked(Map<String, dynamic> payload, User user) {
    final validAfter = user.sessionsValidAfter;
    if (validAfter == null) return false;
    final iatMs = payload['iatMs'];
    final iat = payload['iat'];
    final issuedMs = iatMs is int
        ? iatMs
        : iat is num
            ? (iat * 1000).toInt()
            : null;
    if (issuedMs == null) return true;
    return issuedMs < validAfter.millisecondsSinceEpoch;
  }

  /// The instant to store as `sessionsValidAfter` when revoking now. Tokens
  /// signed after it — like the replacement handed to the caller — stay valid.
  static DateTime revocationInstant() => DateTime.now().toUtc();

  static Map<String, dynamic>? _verified(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(secret));
      // Only ever HS256 is issued; don't let the header pick another scheme.
      if (jwt.header?['alg'] != 'HS256') return null;
      final payload = jwt.payload;
      return payload is Map<String, dynamic> ? payload : null;
    } catch (_) {
      // Bad signature, expired, or a malformed header (a non-string `alg`
      // surfaces as a TypeError rather than a JWTException).
      return null;
    }
  }
}
