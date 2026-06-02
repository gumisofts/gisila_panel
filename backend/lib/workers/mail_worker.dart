import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/mail_service.dart' show effectiveMailHostname;

/// Syncs the DB's mail domains + accounts into the host's Postfix/Dovecot
/// virtual-mailbox configuration and OpenDKIM signing setup
/// (queue `gisila:queue:mail`).
class MailWorker {
  MailWorker(this.database);

  final Database database;

  Future<void> onMailJob(Map<String, Object?> payload) async {
    final action = payload['action'] as String?;
    switch (action) {
      case 'setup':
        // Provision the stack without touching maps (idempotent bootstrap).
        await _runAgent(['mail', 'setup']);
      case 'sync':
        await _sync();
      default:
        return;
    }
  }

  Future<void> _sync() async {
    final domains = await Query<MailDomain>(MailDomainTable.metadata)
        .where(MailDomainTable.isActive.eq(true))
        .all(database.context());
    final accounts = await Query<MailAccount>(MailAccountTable.metadata)
        .where(MailAccountTable.isActive.eq(true))
        .all(database.context());

    final domainsJson = domains
        .map((d) => {
              'domain': d.domain,
              'hostname': effectiveMailHostname(d),
              'selector': (d.dkimSelector?.trim().isNotEmpty ?? false)
                  ? d.dkimSelector!.trim()
                  : 'gisila',
              'dmarc': (d.dmarcPolicy?.trim().isNotEmpty ?? false)
                  ? d.dmarcPolicy!.trim()
                  : 'none',
            })
        .toList();
    final accountsJson = accounts
        .map((a) => {
              'address': a.address,
              'hash': a.passwordHash,
              if (a.quotaMb != null) 'quota': a.quotaMb,
            })
        .toList();

    final stdoutText = await _runAgent([
      'mail',
      'sync',
      '--domains',
      jsonEncode(domainsJson),
      '--accounts',
      jsonEncode(accountsJson),
    ]);

    await _persistAgentResult(stdoutText);
  }

  /// Parse the agent's trailing JSON line and persist the DKIM public keys and
  /// detected public IP back onto each domain row.
  Future<void> _persistAgentResult(String stdoutText) async {
    final result = _parseTrailingJson(stdoutText);
    if (result == null) return;

    final publicIp = result['publicIp'] as String?;
    final domainsResult = result['domains'];
    if (domainsResult is! Map) return;

    for (final entry in domainsResult.entries) {
      final domain = entry.key.toString();
      final info = entry.value;
      if (info is! Map) continue;
      final selector = info['selector']?.toString();
      final publicKey = info['publicKey']?.toString();

      await Query<MailDomain>(MailDomainTable.metadata)
          .where(MailDomainTable.domain.eq(domain))
          .update(<String, Object?>{
        if (selector != null && selector.isNotEmpty) 'dkimSelector': selector,
        if (publicKey != null && publicKey.isNotEmpty) 'dkimPublicKey': publicKey,
        if (publicIp != null && publicIp.isNotEmpty) 'publicIp': publicIp,
      }).run(database.context());
    }
  }

  /// Scan stdout bottom-up for the last line that parses as a JSON object.
  Map<String, Object?>? _parseTrailingJson(String text) {
    final lines = text.trim().split('\n');
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (!line.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, Object?>) return decoded;
      } catch (_) {
        // Not the JSON line — keep scanning upward.
      }
    }
    return null;
  }

  Future<String> _runAgent(List<String> args) async {
    if (hostConfig.agentMode == 'dev') {
      logger.i('mail_worker (dev): agent ${args.take(2).join(' ')} '
          '(${args.length} args)');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return '';
    }
    final cmd = buildAgentCmd(args);
    logger.i('mail_worker: ${cmd.take(2).join(' ')} …');
    final result = await Process.run(cmd.first, cmd.skip(1).toList());
    if (result.exitCode != 0) {
      throw Exception('Agent exited ${result.exitCode}: ${result.stderr}'.trim());
    }
    return result.stdout as String? ?? '';
  }
}
