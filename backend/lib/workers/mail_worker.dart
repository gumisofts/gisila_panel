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
        // Install + provision the stack (the panel's "Install email tools").
        await _runAgent(['mail', 'setup']);
      case 'sync':
        await _sync();
      default:
        return;
    }
  }

  /// Whether the mail tooling is installed on this host. Used at boot to decide
  /// whether to re-sync existing config — installation itself is never done
  /// automatically; the operator triggers it from the panel's Mail page.
  Future<bool> isStackInstalled() async {
    if (hostConfig.agentMode == 'dev') return true;
    final r = await _execAgent(['mail', 'status']);
    if (r.exitCode != 0) return false;
    return _parseTrailingJson(r.stdout)?['installed'] == true;
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

    final result = await _execAgent([
      'mail',
      'sync',
      '--domains',
      jsonEncode(domainsJson),
      '--accounts',
      jsonEncode(accountsJson),
    ]);

    // Persist the DKIM keys + public IP from whatever the agent reported, even
    // when it exited non-zero: the agent prints the keys before its fragile
    // cert/postfix/restart steps, so a failure in those steps must not strand a
    // successful keygen and leave the panel stuck on "Waiting for DKIM key…".
    await _persistAgentResult(result.stdout);

    if (result.exitCode != 0) {
      throw Exception(
          'Agent mail sync exited ${result.exitCode}: ${result.stderr}'.trim());
    }
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
    final r = await _execAgent(args);
    if (r.exitCode != 0) {
      throw Exception('Agent exited ${r.exitCode}: ${r.stderr}'.trim());
    }
    return r.stdout;
  }

  /// Run the agent and return its stdout, exit code, and stderr *without*
  /// throwing on failure, so callers can salvage partial stdout (e.g. DKIM keys
  /// the agent printed before a later step failed) before deciding how to react.
  Future<({String stdout, int exitCode, String stderr})> _execAgent(
      List<String> args) async {
    if (hostConfig.agentMode == 'dev') {
      logger.i('mail_worker (dev): agent ${args.take(2).join(' ')} '
          '(${args.length} args)');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return (stdout: '', exitCode: 0, stderr: '');
    }
    final cmd = buildAgentCmd(args);
    logger.i('mail_worker: ${cmd.take(2).join(' ')} …');
    final result = await Process.run(cmd.first, cmd.skip(1).toList());
    return (
      stdout: result.stdout as String? ?? '',
      exitCode: result.exitCode,
      stderr: (result.stderr as String? ?? '').trim(),
    );
  }
}
