import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:gisila_panel/utils/passwords.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

void main() {
  test('pointycastle Argon2id matches the reference implementation', () {
    // phc-winner-argon2 test.c: argon2id v=0x13, t=2, m=2^16, p=1,
    // pwd "password", salt "somesalt".
    final gen = Argon2BytesGenerator()
      ..init(Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        Uint8List.fromList(utf8.encode('somesalt')),
        desiredKeyLength: 32,
        iterations: 2,
        memory: 1 << 16,
        lanes: 1,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ));
    final out = gen.process(Uint8List.fromList(utf8.encode('password')));
    expect(
      out.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      '09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7',
    );
  });

  test('hash round-trips and rejects a wrong password', () {
    final stored = PasswordHasher.hash('correct horse');
    expect(stored, startsWith(r'$argon2id$v=19$m=19456,t=2,p=1$'));
    expect(PasswordHasher.verify('correct horse', stored), isTrue);
    expect(PasswordHasher.verify('correct horsf', stored), isFalse);
    expect(PasswordHasher.needsRehash(stored), isFalse);
  });

  test('salts differ between hashes of the same password', () {
    expect(PasswordHasher.hash('x' * 12), isNot(PasswordHasher.hash('x' * 12)));
  });

  test('legacy salted SHA-256 hashes verify and need a rehash', () {
    const salt = '00112233445566778899aabbccddeeff';
    final digest = sha256.convert(utf8.encode('$salt:hunter22')).toString();
    final legacy = 'sha256\$$salt\$$digest';
    expect(PasswordHasher.verify('hunter22', legacy), isTrue);
    expect(PasswordHasher.verify('hunter23', legacy), isFalse);
    expect(PasswordHasher.needsRehash(legacy), isTrue);
  });

  test('weaker Argon2 parameters need a rehash', () {
    final weak = PasswordHasher.hash('pw').replaceFirst('t=2', 't=1');
    expect(PasswordHasher.needsRehash(weak), isTrue);
  });

  test('malformed or hostile hashes are rejected without throwing', () {
    for (final bad in [
      '',
      'plaintext',
      r'$argon2id$v=19$m=19456,t=2,p=1$!!!$!!!',
      r'$argon2id$v=19$m=99999999,t=2,p=1$c29tZXNhbHQ$CTFhFdXPJO1aFaMaO6Mm5c8y7cJHAph8ArZWb2GRPPc',
      r'$argon2id$v=19$m=19456,t=999,p=1$c29tZXNhbHQ$CTFhFdXPJO1aFaMaO6Mm5c8y7cJHAph8ArZWb2GRPPc',
      r'$argon2i$v=19$m=19456,t=2,p=1$c29tZXNhbHQ$CTFhFdXPJO1aFaMaO6Mm5c8y7cJHAph8ArZWb2GRPPc',
    ]) {
      expect(PasswordHasher.verify('password', bad), isFalse, reason: bad);
    }
  });

  test('a PHC string from the reference CLI verifies', () {
    // `echo -n password | argon2 somesalt -id -t 2 -m 16 -p 1`
    expect(
      PasswordHasher.verify('password',
          r'$argon2id$v=19$m=65536,t=2,p=1$c29tZXNhbHQ$CTFhFdXPJO1aFaMaO6Mm5c8y7cJHAph8ArZWb2GRPPc'),
      isTrue,
    );
  });

  test('async variants and the dummy verifier work off-isolate', () async {
    final stored = await PasswordHasher.hashAsync('pw-async');
    expect(await PasswordHasher.verifyAsync('pw-async', stored), isTrue);
    await PasswordHasher.dummyVerifyAsync('anything');
  });

  test('the dummy hash is well-formed, so dummy verification costs a full hash',
      () {
    expect(PasswordHasher.needsRehash(PasswordHasher.dummyHash), isFalse);
  });
}
