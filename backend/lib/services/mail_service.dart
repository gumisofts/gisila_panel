import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';

/// Virtual-mailbox email management: domains and mailboxes that the agent syncs
/// into Postfix (virtual maps) + Dovecot (passwd-file). A single host can serve
/// many domains and accounts.
class MailService extends Service {
  static final _rng = Random.secure();
  Database get _db => db<Database>();

  // ── Domains ────────────────────────────────────────────────────────────────

  Future<List<MailDomain>> listDomains() =>
      Query<MailDomain>(MailDomainTable.metadata)
          .orderBy(MailDomainTable.domain)
          .all(_db.context());

  Future<MailDomain> findDomain(int id) async {
    final row = await Query<MailDomain>(MailDomainTable.metadata)
        .where(MailDomainTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Mail domain #$id not found.');
    return row;
  }

  Future<MailDomain> addDomain(String domain) async {
    final d = domain.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$')
        .hasMatch(d)) {
      throw HttpException(422, 'Invalid domain name.');
    }
    final existing = await Query<MailDomain>(MailDomainTable.metadata)
        .where(MailDomainTable.domain.eq(d))
        .first(_db.context());
    if (existing != null) {
      throw HttpException(409, 'Domain already configured.');
    }
    final row = await Query<MailDomain>(MailDomainTable.metadata)
        .insert(<String, Object?>{
      'domain': d,
      'isActive': true,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
    await _enqueueSync();
    return row;
  }

  Future<void> removeDomain(int id) async {
    await findDomain(id);
    // Accounts cascade-delete via the FK.
    await Query<MailDomain>(MailDomainTable.metadata)
        .where(MailDomainTable.id.eq(id))
        .delete()
        .run(_db.context());
    await _enqueueSync();
  }

  // ── Accounts ───────────────────────────────────────────────────────────────

  Future<List<MailAccount>> listAccounts(int domainId) =>
      Query<MailAccount>(MailAccountTable.metadata)
          .where(MailAccountTable.mailDomainId.eq(domainId))
          .orderBy(MailAccountTable.address)
          .all(_db.context());

  Future<MailAccount> findAccount(int id) async {
    final row = await Query<MailAccount>(MailAccountTable.metadata)
        .where(MailAccountTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Mailbox #$id not found.');
    return row;
  }

  Future<MailAccount> addAccount({
    required int domainId,
    required String localPart,
    required String password,
    int? quotaMb,
  }) async {
    final domain = await findDomain(domainId);
    final local = localPart.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._%+-]+$').hasMatch(local)) {
      throw HttpException(422, 'Invalid mailbox name.');
    }
    if (password.length < 6) {
      throw HttpException(422, 'Password must be at least 6 characters.');
    }
    final address = '$local@${domain.domain}';
    final existing = await Query<MailAccount>(MailAccountTable.metadata)
        .where(MailAccountTable.address.eq(address))
        .first(_db.context());
    if (existing != null) {
      throw HttpException(409, 'Mailbox already exists.');
    }
    final row = await Query<MailAccount>(MailAccountTable.metadata)
        .insert(<String, Object?>{
      'mailDomainId': domainId,
      'address': address,
      'passwordHash': hashPassword(password),
      'quotaMb': quotaMb,
      'isActive': true,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
    await _enqueueSync();
    return row;
  }

  Future<MailAccount> setPassword(int accountId, String password) async {
    await findAccount(accountId);
    if (password.length < 6) {
      throw HttpException(422, 'Password must be at least 6 characters.');
    }
    await Query<MailAccount>(MailAccountTable.metadata)
        .where(MailAccountTable.id.eq(accountId))
        .update(<String, Object?>{
      'passwordHash': hashPassword(password),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }).run(_db.context());
    await _enqueueSync();
    return findAccount(accountId);
  }

  Future<void> removeAccount(int id) async {
    await findAccount(id);
    await Query<MailAccount>(MailAccountTable.metadata)
        .where(MailAccountTable.id.eq(id))
        .delete()
        .run(_db.context());
    await _enqueueSync();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Produce a Dovecot-compatible salted SHA-512 hash:
  /// `{SSHA512}<base64(sha512(password+salt) || salt)>`.
  static String hashPassword(String password) {
    final salt = List<int>.generate(8, (_) => _rng.nextInt(256));
    final digest = sha512.convert([...utf8.encode(password), ...salt]).bytes;
    return '{SSHA512}${base64.encode([...digest, ...salt])}';
  }

  Future<void> _enqueueSync() => RedisClient.instance.rpush(
        'gisila:queue:mail',
        jsonEncode({'action': 'sync'}),
      );
}
