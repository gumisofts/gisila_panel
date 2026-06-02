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

  /// Update the editable, DNS-facing settings of a domain: the public mail
  /// hostname (MX/A target) and the advertised DMARC policy.
  Future<MailDomain> updateDomain(
    int id, {
    String? mailHostname,
    String? dmarcPolicy,
  }) async {
    await findDomain(id);
    final patch = <String, Object?>{};
    if (mailHostname != null) {
      final h = mailHostname.trim().toLowerCase();
      if (h.isEmpty) {
        patch['mailHostname'] = null;
      } else {
        if (!RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$')
            .hasMatch(h)) {
          throw HttpException(422, 'Invalid mail hostname.');
        }
        patch['mailHostname'] = h;
      }
    }
    if (dmarcPolicy != null) {
      const allowed = {'none', 'quarantine', 'reject'};
      if (!allowed.contains(dmarcPolicy)) {
        throw HttpException(422, 'DMARC policy must be none, quarantine, or reject.');
      }
      patch['dmarcPolicy'] = dmarcPolicy;
    }
    if (patch.isNotEmpty) {
      await Query<MailDomain>(MailDomainTable.metadata)
          .where(MailDomainTable.id.eq(id))
          .update(patch)
          .run(_db.context());
      await _enqueueSync();
    }
    return findDomain(id);
  }

  /// Persist DKIM public key + detected public IP reported by the agent after a
  /// sync. Looked up by domain name since the agent only knows the domain.
  Future<void> persistDkim({
    required String domain,
    required String selector,
    required String publicKey,
    String? publicIp,
  }) async {
    await Query<MailDomain>(MailDomainTable.metadata)
        .where(MailDomainTable.domain.eq(domain.trim().toLowerCase()))
        .update(<String, Object?>{
      'dkimSelector': selector,
      'dkimPublicKey': publicKey,
      if (publicIp != null && publicIp.isNotEmpty) 'publicIp': publicIp,
    }).run(_db.context());
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

  /// Enqueue a full sync. Public so the endpoint and worker can both call it.
  Future<void> enqueueSync() => RedisClient.instance.rpush(
        'gisila:queue:mail',
        jsonEncode({'action': 'sync'}),
      );

  Future<void> _enqueueSync() => enqueueSync();
}

/// Standard ports the agent configures for mail clients.
class MailPorts {
  static const submission = 587; // SMTP submission, STARTTLS
  static const smtps = 465; // SMTP, implicit TLS
  static const imap = 143; // IMAP, STARTTLS
  static const imaps = 993; // IMAP, implicit TLS
  static const pop3 = 110; // POP3, STARTTLS
  static const pop3s = 995; // POP3, implicit TLS
}

/// The public hostname mail clients connect to and DNS records point at.
/// Falls back to `mail.<domain>` when no hostname has been set.
String effectiveMailHostname(MailDomain d) {
  final h = d.mailHostname?.trim();
  if (h != null && h.isNotEmpty) return h;
  return 'mail.${d.domain}';
}

/// Build the list of DNS records the operator must publish for [d] so that mail
/// delivers and passes SPF/DKIM/DMARC. Returned as plain maps ready for JSON.
List<Map<String, Object?>> buildDnsRecords(MailDomain d) {
  final host = effectiveMailHostname(d);
  final selector = (d.dkimSelector?.trim().isNotEmpty ?? false)
      ? d.dkimSelector!.trim()
      : 'gisila';
  final policy = (d.dmarcPolicy?.trim().isNotEmpty ?? false)
      ? d.dmarcPolicy!.trim()
      : 'none';

  final records = <Map<String, Object?>>[
    {
      'type': 'A',
      'host': host,
      'value': d.publicIp ?? '<server-public-ip>',
      'note': 'Points the mail hostname at this server. '
          'Set reverse DNS (PTR) for this IP at your hosting provider.',
    },
    {
      'type': 'MX',
      'host': d.domain,
      'value': host,
      'priority': 10,
      'note': 'Routes inbound mail for the domain to this server.',
    },
    {
      'type': 'TXT',
      'host': d.domain,
      'value': 'v=spf1 mx ~all',
      'label': 'SPF',
      'note': 'Authorises this server (via its MX) to send for the domain.',
    },
    {
      'type': 'TXT',
      'host': '$selector._domainkey.${d.domain}',
      'value': d.dkimPublicKey == null || d.dkimPublicKey!.isEmpty
          ? '<generated after first sync>'
          : 'v=DKIM1; k=rsa; p=${d.dkimPublicKey}',
      'label': 'DKIM',
      'note': 'Public key used to verify DKIM signatures added by this server.',
    },
    {
      'type': 'TXT',
      'host': '_dmarc.${d.domain}',
      'value': 'v=DMARC1; p=$policy; rua=mailto:postmaster@${d.domain}',
      'label': 'DMARC',
      'note': 'Tells receivers how to handle mail that fails SPF/DKIM.',
    },
  ];
  return records;
}

/// Build the IMAP/POP3/SMTP client connection settings for [address] on [d].
Map<String, Object?> buildConnectionSettings(MailDomain d, String address) {
  final host = effectiveMailHostname(d);
  return {
    'host': host,
    'username': address,
    'smtp': {
      'host': host,
      'starttls': {'port': MailPorts.submission, 'security': 'STARTTLS'},
      'ssl': {'port': MailPorts.smtps, 'security': 'SSL/TLS'},
    },
    'imap': {
      'host': host,
      'ssl': {'port': MailPorts.imaps, 'security': 'SSL/TLS'},
      'starttls': {'port': MailPorts.imap, 'security': 'STARTTLS'},
    },
    'pop3': {
      'host': host,
      'ssl': {'port': MailPorts.pop3s, 'security': 'SSL/TLS'},
      'starttls': {'port': MailPorts.pop3, 'security': 'STARTTLS'},
    },
  };
}
