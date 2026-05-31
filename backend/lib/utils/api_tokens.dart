import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Generation + verification helpers for API tokens (`gsl_…`).
///
/// The plain token is shown to the user **only once**. The database stores:
///   - `prefix`: first 12 chars of the plain token (used to find candidate
///     records on lookup before hashing).
///   - `token_hash`: SHA-256 of the plain token, hex-encoded.
class ApiTokenCodec {
  static const _prefix = 'gsl_';
  static final _rng = Random.secure();

  /// Generate a brand new token. Returns the plain string (shown once) and
  /// the values to persist.
  static IssuedApiToken issue() {
    final bytes = List<int>.generate(24, (_) => _rng.nextInt(256));
    final body = base64Url.encode(bytes).replaceAll('=', '').toLowerCase();
    final plain = '$_prefix$body';
    return IssuedApiToken(
      plain: plain,
      prefix: plain.substring(0, 12),
      hash: hash(plain),
    );
  }

  /// Hash a token for storage / lookup.
  static String hash(String plain) =>
      sha256.convert(utf8.encode(plain)).bytes.map((b) {
        return b.toRadixString(16).padLeft(2, '0');
      }).join();
}

class IssuedApiToken {
  IssuedApiToken({
    required this.plain,
    required this.prefix,
    required this.hash,
  });

  final String plain;
  final String prefix;
  final String hash;
}
