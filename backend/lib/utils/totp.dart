import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RFC 6238 time-based one-time passwords: HMAC-SHA1, 6 digits, 30s steps —
/// the parameters every authenticator app defaults to.
class Totp {
  static const digits = 6;
  static const period = 30;
  static final _rng = Random.secure();

  /// A fresh 160-bit secret, base32-encoded (the form authenticator apps take).
  static String generateSecret() => base32Encode(Uint8List.fromList(
      List<int>.generate(20, (_) => _rng.nextInt(256))));

  /// The `otpauth://` URI an authenticator app scans as a QR code.
  static String provisioningUri({
    required String secret,
    required String account,
    String issuer = 'Gisila',
  }) {
    final label = Uri.encodeComponent('$issuer:$account');
    final query = Uri(queryParameters: {
      'secret': secret,
      'issuer': issuer,
      'algorithm': 'SHA1',
      'digits': '$digits',
      'period': '$period',
    }).query;
    return 'otpauth://totp/$label?$query';
  }

  static int stepAt(DateTime time) =>
      time.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ period;

  static String codeAt(String secret, int step) {
    final counter = ByteData(8)..setUint64(0, step);
    final mac = Hmac(sha1, base32Decode(secret))
        .convert(counter.buffer.asUint8List())
        .bytes;
    final offset = mac.last & 0x0f;
    final binary = ((mac[offset] & 0x7f) << 24) |
        (mac[offset + 1] << 16) |
        (mac[offset + 2] << 8) |
        mac[offset + 3];
    return (binary % pow(10, digits)).toString().padLeft(digits, '0');
  }

  /// The time step [code] is valid for, or null. Accepts one step of clock
  /// drift either way, and never a step at or before [lastUsedStep], so a
  /// code that was already accepted can't be replayed.
  static int? verify(
    String secret,
    String code, {
    int? lastUsedStep,
    DateTime? now,
  }) {
    final normalized = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp('^[0-9]{$digits}\$').hasMatch(normalized)) return null;
    final current = stepAt(now ?? DateTime.now());
    for (final step in [current - 1, current, current + 1]) {
      if (lastUsedStep != null && step <= lastUsedStep) continue;
      if (_constantTimeEquals(codeAt(secret, step), normalized)) return step;
    }
    return null;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Single-use recovery codes for when the authenticator is lost. Only their
/// SHA-256 digests are stored.
class RecoveryCodes {
  static const count = 10;
  static final _rng = Random.secure();
  static const _alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';

  /// [count] fresh codes, `xxxxx-xxxxx`.
  static List<String> generate() => List.generate(count, (_) {
        String chunk() => List.generate(
            5, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join();
        return '${chunk()}-${chunk()}';
      });

  static String digest(String code) => sha256
      .convert(utf8.encode(code.trim().toLowerCase().replaceAll(' ', '')))
      .toString();
}

const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String base32Encode(Uint8List bytes) {
  final out = StringBuffer();
  var buffer = 0, bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(_base32Alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_base32Alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List base32Decode(String input) {
  final clean = input.toUpperCase().replaceAll(RegExp(r'[\s=]'), '');
  final out = <int>[];
  var buffer = 0, bits = 0;
  for (final char in clean.split('')) {
    final value = _base32Alphabet.indexOf(char);
    if (value < 0) throw FormatException('Invalid base32 character: $char');
    buffer = ((buffer << 5) | value) & 0xffff;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Uint8List.fromList(out);
}
