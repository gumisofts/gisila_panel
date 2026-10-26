import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart'
    show Argon2BytesGenerator, Argon2Parameters;

/// Argon2id password hashing (pointycastle's pure-Dart implementation).
///
/// New hashes use the PHC string format:
/// `$argon2id$v=19$m=<KiB>,t=<iterations>,p=<lanes>$<salt-b64>$<hash-b64>`.
/// Hashes from before Argon2 (`sha256$<salt-hex>$<digest-hex>`, a single
/// salted SHA-256) still verify, and [needsRehash] reports them so a login can
/// upgrade them in place.
///
/// One hash costs ~0.4s of CPU and 19 MiB, so request handlers use
/// [hashAsync] / [verifyAsync], which run it on a short-lived isolate rather
/// than stalling every other request on this one.
class PasswordHasher {
  // OWASP's minimum Argon2id configuration: 19 MiB, 2 iterations, 1 lane.
  static const _memoryKiB = 19456;
  static const _iterations = 2;
  static const _lanes = 1;
  static const _hashLength = 32;
  static const _saltLength = 16;

  static const _legacyTag = 'sha256';
  static final _rng = Random.secure();

  static String hash(String plain) {
    final salt = Uint8List.fromList(
        List<int>.generate(_saltLength, (_) => _rng.nextInt(256)));
    final digest = _argon2id(plain, salt,
        memoryKiB: _memoryKiB, iterations: _iterations, lanes: _lanes,
        length: _hashLength);
    return '\$argon2id\$v=19\$m=$_memoryKiB,t=$_iterations,p=$_lanes'
        '\$${_b64(salt)}\$${_b64(digest)}';
  }

  static bool verify(String plain, String stored) {
    if (stored.startsWith('\$argon2id\$')) return _verifyArgon2(plain, stored);
    if (stored.startsWith('$_legacyTag\$')) return _verifyLegacy(plain, stored);
    return false;
  }

  /// Whether [stored] should be replaced by a fresh [hash] of the password,
  /// i.e. it is a legacy SHA-256 hash or uses weaker Argon2 parameters.
  static bool needsRehash(String stored) {
    final params = _parseArgon2(stored)?.params;
    if (params == null) return true;
    return params.memoryKiB < _memoryKiB ||
        params.iterations < _iterations ||
        params.length < _hashLength;
  }

  static Future<String> hashAsync(String plain) =>
      Isolate.run(() => hash(plain));

  static Future<bool> verifyAsync(String plain, String stored) =>
      Isolate.run(() => verify(plain, stored));

  /// Burn the same time as a real verification. Used when there is no stored
  /// hash to check against, so the response time doesn't reveal whether an
  /// account exists.
  static Future<void> dummyVerifyAsync(String plain) =>
      Isolate.run(() => verify(plain, dummyHash));

  /// A fixed, well-formed Argon2id hash that no password matches.
  static const dummyHash = '\$argon2id\$v=19\$m=19456,t=2,p=1'
      '\$Z2lzaWxhLWR1bW15LXNhbHQ'
      '\$4n5hJ0v9mY2rW7z8bq3cX1kL6pT0sD4fG8hJ2kL5mN0';

  // ── Argon2id ──────────────────────────────────────────────────────────────

  static bool _verifyArgon2(String plain, String stored) {
    final parsed = _parseArgon2(stored);
    if (parsed == null) return false;
    final p = parsed.params;
    final actual = _argon2id(plain, parsed.salt,
        memoryKiB: p.memoryKiB, iterations: p.iterations, lanes: p.lanes,
        length: p.length);
    return _constantTimeEquals(parsed.hash, actual);
  }

  static ({
    ({int memoryKiB, int iterations, int lanes, int length}) params,
    Uint8List salt,
    Uint8List hash,
  })? _parseArgon2(String stored) {
    // ['', 'argon2id', 'v=19', 'm=..,t=..,p=..', salt, hash]
    final parts = stored.split('\$');
    if (parts.length != 6 || parts[1] != 'argon2id' || parts[2] != 'v=19') {
      return null;
    }
    final kv = <String, int>{};
    for (final pair in parts[3].split(',')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) return null;
      final value = int.tryParse(pair.substring(eq + 1));
      if (value == null) return null;
      kv[pair.substring(0, eq)] = value;
    }
    final m = kv['m'], t = kv['t'], p = kv['p'];
    // Bound the parameters a stored hash can ask for: a tampered row must not
    // be able to make verification allocate gigabytes or spin for minutes.
    if (m == null || t == null || p == null) return null;
    if (m < 8 * p || m > 1 << 20 || t < 1 || t > 16 || p < 1 || p > 16) {
      return null;
    }
    try {
      final salt = _unb64(parts[4]);
      final hash = _unb64(parts[5]);
      if (salt.length < 8 || hash.length < 16 || hash.length > 64) return null;
      return (
        params: (memoryKiB: m, iterations: t, lanes: p, length: hash.length),
        salt: salt,
        hash: hash,
      );
    } on FormatException {
      return null;
    }
  }

  static Uint8List _argon2id(
    String plain,
    Uint8List salt, {
    required int memoryKiB,
    required int iterations,
    required int lanes,
    required int length,
  }) {
    final generator = Argon2BytesGenerator()
      ..init(Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: length,
        iterations: iterations,
        memory: memoryKiB,
        lanes: lanes,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ));
    return generator.process(Uint8List.fromList(utf8.encode(plain)));
  }

  // PHC strings use unpadded standard base64.
  static String _b64(List<int> bytes) =>
      base64.encode(bytes).replaceAll('=', '');

  static Uint8List _unb64(String s) =>
      base64.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));

  // ── Legacy salted SHA-256 ─────────────────────────────────────────────────

  static bool _verifyLegacy(String plain, String stored) {
    final parts = stored.split('\$');
    if (parts.length != 3) return false;
    final salt = parts[1];
    final expected = utf8.encode(parts[2]);
    final actual = utf8.encode(_hex(
        sha256.convert(utf8.encode('$salt:$plain')).bytes));
    return _constantTimeEquals(expected, actual);
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
