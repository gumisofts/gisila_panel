import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/api_tokens.dart';

/// Manages personal API tokens and SSH keys.
class SecurityService extends Service {
  Database get _db => db<Database>();

  Future<List<ApiToken>> listTokens(User user) =>
      Query<ApiToken>(ApiTokenTable.metadata)
          .where(ApiTokenTable.userId.eq(user.id!))
          .all(_db.context());

  Future<({ApiToken token, String plain})> issueToken(
    User user, {
    required String name,
    int? expiresInDays,
  }) async {
    final issued = ApiTokenCodec.issue();
    final expiresAt = expiresInDays == null
        ? null
        : DateTime.now().toUtc().add(Duration(days: expiresInDays));
    final token =
        await Query<ApiToken>(ApiTokenTable.metadata).insert(<String, Object?>{
      'userId': user.id,
      'name': name,
      'tokenHash': issued.hash,
      'prefix': issued.prefix,
      'expiresAt': expiresAt?.toIso8601String(),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
    return (token: token, plain: issued.plain);
  }

  Future<void> revokeToken(User user, int tokenId) async {
    final token = await Query<ApiToken>(ApiTokenTable.metadata)
        .where(ApiTokenTable.id.eq(tokenId))
        .first(_db.context());
    if (token == null) throw NotFound('Token not found.');
    if (token.userId != user.id) {
      throw Forbidden('You can only revoke your own tokens.');
    }
    await Query<ApiToken>(ApiTokenTable.metadata)
        .where(ApiTokenTable.id.eq(tokenId))
        .delete()
        .run(_db.context());
  }

  // ── SSH keys ──────────────────────────────────────────────────────────

  Future<List<SshKey>> listSshKeys(User user) =>
      Query<SshKey>(SshKeyTable.metadata)
          .where(SshKeyTable.userId.eq(user.id!))
          .all(_db.context());

  Future<SshKey> addSshKey(
    User user, {
    required String name,
    required String publicKey,
    String? algorithm,
  }) async {
    final trimmed = publicKey.trim();
    if (!RegExp(r'^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-\S+)\s+')
        .hasMatch(trimmed)) {
      throw BadRequest('Invalid OpenSSH public key.', code: 'invalid_ssh_key');
    }
    final fingerprint = _fingerprint(trimmed);
    return Query<SshKey>(SshKeyTable.metadata).insert(<String, Object?>{
      'userId': user.id,
      'name': name,
      'algorithm': algorithm,
      'publicKey': trimmed,
      'fingerprint': fingerprint,
      'isDeployKey': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
  }

  /// Generate a new SSH keypair via ssh-keygen. Returns both private and public
  /// keys; private key is stored in the DB so the deployment agent can use it
  /// for authenticated git clone.
  Future<({SshKey key, String privateKey})> generateKey(
    User user, {
    required String name,
    required String
        algorithm, // ed25519 | rsa-4096 | rsa-2048 | ecdsa-p256 | ecdsa-p384
  }) async {
    final tmp = await Directory.systemTemp.createTemp('gisila_keygen_');
    final keyPath = '${tmp.path}/key';
    try {
      final (type, bits) = switch (algorithm) {
        'rsa-4096' => ('rsa', '4096'),
        'rsa-2048' => ('rsa', '2048'),
        'ecdsa-p256' => ('ecdsa', '256'),
        'ecdsa-p384' => ('ecdsa', '384'),
        _ => ('ed25519', null), // default: ed25519
      };

      final args = [
        '-t', type,
        if (bits != null) ...['-b', bits],
        '-f', keyPath,
        '-N', '', // no passphrase
        '-C', '$name@gisila-panel',
        '-q',
      ];

      final result = await Process.run('ssh-keygen', args);
      if (result.exitCode != 0) {
        throw Exception('ssh-keygen failed: ${result.stderr}');
      }

      final privateKey = await File(keyPath).readAsString();
      final publicKey = (await File('$keyPath.pub').readAsString()).trim();
      final fingerprint = _fingerprint(publicKey);

      final key =
          await Query<SshKey>(SshKeyTable.metadata).insert(<String, Object?>{
        'userId': user.id,
        'name': name,
        'algorithm': algorithm,
        'publicKey': publicKey,
        'privateKey': privateKey,
        'fingerprint': fingerprint,
        'isDeployKey': true,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }).one(_db.context());

      return (key: key, privateKey: privateKey);
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  Future<void> deleteSshKey(User user, int keyId) async {
    final key = await Query<SshKey>(SshKeyTable.metadata)
        .where(SshKeyTable.id.eq(keyId))
        .first(_db.context());
    if (key == null) throw NotFound('SSH key not found.');
    if (key.userId != user.id) {
      throw Forbidden('You can only delete your own keys.');
    }
    await Query<SshKey>(SshKeyTable.metadata)
        .where(SshKeyTable.id.eq(keyId))
        .delete()
        .run(_db.context());
  }

  String _fingerprint(String publicKey) {
    final parts = publicKey.split(RegExp(r'\s+'));
    if (parts.length < 2) return 'invalid';
    try {
      final bytes = base64.decode(parts[1]);
      final digest = sha256.convert(bytes).bytes;
      final b64 = base64.encode(digest).replaceAll('=', '');
      return 'SHA256:$b64';
    } catch (_) {
      return 'SHA256:invalid';
    }
  }
}
