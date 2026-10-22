import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/jwt.dart';
import 'package:test/test.dart';

const _secret = 'test-secret-0123456789abcdefghijklmnopqrstuvwxyz';

User _user({DateTime? sessionsValidAfter}) => User(
      id: 7,
      email: 'a@b.c',
      isSuperuser: true,
      createdAt: DateTime.utc(2026),
      sessionsValidAfter: sessionsValidAfter,
    );

void main() {
  setUpAll(() => env.addAll({'JWT_SECRET': _secret}));

  test('session tokens round-trip', () {
    final payload = JWTAuth.decodeSession(JWTAuth.sign(_user()));
    expect(payload?['id'], 7);
    expect(payload?['iat'], isA<int>());
  });

  test('an MFA challenge is not a session, and vice versa', () {
    final challenge = JWTAuth.signMfaChallenge(_user());
    expect(JWTAuth.decodeSession(challenge), isNull);
    expect(JWTAuth.decodeMfaChallenge(challenge)?['id'], 7);
    expect(JWTAuth.decodeMfaChallenge(JWTAuth.sign(_user())), isNull);
  });

  test('tokens signed with another secret, or not HS256, are rejected', () {
    final forged = JWT({'id': 7}).sign(SecretKey('change-me-to-a-random-secret-please'));
    expect(JWTAuth.decodeSession(forged), isNull);

    final hs512 = JWT({'id': 7}).sign(SecretKey(_secret), algorithm: JWTAlgorithm.HS512);
    expect(JWTAuth.decodeSession(hs512), isNull);

    String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final none = '${b64({'alg': 'none', 'typ': 'JWT'})}.${b64({'id': 7})}.';
    expect(JWTAuth.decodeSession(none), isNull);
    final badAlg = '${b64({'alg': 7, 'typ': 'JWT'})}.${b64({'id': 7})}.x';
    expect(JWTAuth.decodeSession(badAlg), isNull);
    expect(JWTAuth.decodeSession('garbage'), isNull);
  });

  test('revocation rejects tokens issued before sessionsValidAfter', () {
    final payload = JWTAuth.decodeSession(JWTAuth.sign(_user()))!;
    final issued = DateTime.fromMillisecondsSinceEpoch(payload['iatMs'] as int,
        isUtc: true);

    expect(JWTAuth.isRevoked(payload, _user()), isFalse);
    expect(JWTAuth.isRevoked(payload, _user(sessionsValidAfter: issued)), isFalse);
    expect(
        JWTAuth.isRevoked(payload,
            _user(sessionsValidAfter: issued.add(const Duration(milliseconds: 1)))),
        isTrue);
  });

  test('a token signed right after revoking is valid; one right before is not',
      () async {
    final before = JWTAuth.decodeSession(JWTAuth.sign(_user()))!;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final revokedAt = JWTAuth.revocationInstant();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final after = JWTAuth.decodeSession(JWTAuth.sign(_user()))!;
    final user = _user(sessionsValidAfter: revokedAt);
    expect(JWTAuth.isRevoked(before, user), isTrue);
    expect(JWTAuth.isRevoked(after, user), isFalse);
  });

  test('legacy tokens: iat rounds down, and no iat at all is revoked', () {
    final revokedAt = DateTime.utc(2026, 1, 1, 0, 0, 0, 500);
    final user = _user(sessionsValidAfter: revokedAt);
    final sameSecond = revokedAt.millisecondsSinceEpoch ~/ 1000;
    expect(JWTAuth.isRevoked({'id': 7, 'iat': sameSecond}, user), isTrue);
    expect(JWTAuth.isRevoked({'id': 7, 'iat': sameSecond + 1}, user), isFalse);
    expect(JWTAuth.isRevoked({'id': 7}, user), isTrue);
  });

  test('derived secrets differ from the panel secret and by label', () {
    final studio = JWTAuth.derivedSecret('studio');
    expect(studio, isNot(_secret));
    expect(studio, isNot(JWTAuth.derivedSecret('other')));
  });
}
