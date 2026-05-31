import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted SHA-256 password hashing.
///
/// Format: `sha256$<salt-hex>$<digest-hex>`. Constant-time comparison via
/// digest equality. Replace with Argon2id once we have a portable pure-Dart
/// implementation; the API below is intentionally stable so callers don't
/// need to change.
class PasswordHasher {
  static const _algoTag = 'sha256';
  static final _rng = Random.secure();

  static String hash(String plain) {
    final saltBytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    final salt = _hex(saltBytes);
    final digest = _digestOf(plain, salt);
    return '$_algoTag\$$salt\$$digest';
  }

  static bool verify(String plain, String stored) {
    final parts = stored.split('\$');
    if (parts.length != 3 || parts[0] != _algoTag) return false;
    final salt = parts[1];
    final expected = parts[2];
    final actual = _digestOf(plain, salt);
    return _constantTimeEquals(expected, actual);
  }

  static String _digestOf(String plain, String saltHex) {
    final bytes = sha256.convert(utf8.encode('$saltHex:$plain')).bytes;
    return _hex(bytes);
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
