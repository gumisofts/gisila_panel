import 'dart:convert';
import 'dart:typed_data';

import 'package:gisila_panel/utils/totp.dart';
import 'package:test/test.dart';

void main() {
  // RFC 6238 appendix B, SHA-1 seed "12345678901234567890". The RFC lists 8
  // digits; a 6-digit code is the low 6 of the same truncated value.
  final secret =
      base32Encode(Uint8List.fromList(utf8.encode('12345678901234567890')));

  test('base32 round-trips', () {
    expect(secret, 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
    expect(utf8.decode(base32Decode(secret)), '12345678901234567890');
    expect(base32Decode('mzxw6==='), utf8.encode('foo'));
  });

  test('RFC 6238 SHA-1 vectors', () {
    const vectors = {
      59: '94287082',
      1111111109: '07081804',
      1111111111: '14050471',
      1234567890: '89005924',
      2000000000: '69279037',
    };
    vectors.forEach((seconds, rfc8) {
      final step = seconds ~/ Totp.period;
      expect(Totp.codeAt(secret, step), rfc8.substring(2), reason: '$seconds');
    });
  });

  test('verify accepts ±1 step and rejects replays', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1111111111 * 1000, isUtc: true);
    final step = Totp.stepAt(now);
    final code = Totp.codeAt(secret, step);
    expect(Totp.verify(secret, code, now: now), step);
    expect(Totp.verify(secret, Totp.codeAt(secret, step - 1), now: now), step - 1);
    expect(Totp.verify(secret, Totp.codeAt(secret, step + 2), now: now), isNull);
    expect(Totp.verify(secret, code, now: now, lastUsedStep: step), isNull);
    expect(Totp.verify(secret, '12 34', now: now), isNull);
    expect(Totp.verify(secret, '${code.substring(0, 3)} ${code.substring(3)}', now: now), step);
  });

  test('provisioning URI', () {
    final uri = Totp.provisioningUri(secret: 'ABC', account: 'a@b.c');
    expect(uri, startsWith('otpauth://totp/Gisila%3Aa%40b.c?secret=ABC&issuer=Gisila'));
  });

  test('recovery codes are unique and digest case-insensitively', () {
    final codes = RecoveryCodes.generate();
    expect(codes.toSet().length, RecoveryCodes.count);
    expect(codes.first, matches(RegExp(r'^[a-z2-9]{5}-[a-z2-9]{5}$')));
    expect(RecoveryCodes.digest(codes.first.toUpperCase()),
        RecoveryCodes.digest(' ${codes.first} '));
  });
}
