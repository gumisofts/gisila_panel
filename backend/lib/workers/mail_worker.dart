import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';

/// Syncs the DB's mail domains + accounts into the host's Postfix/Dovecot
/// virtual-mailbox configuration (queue `gisila:queue:mail`).
class MailWorker {
  MailWorker(this.database);

  final Database database;

  Future<void> onMailJob(Map<String, Object?> payload) async {
    if (payload['action'] != 'sync') return;

    final domains = await Query<MailDomain>(MailDomainTable.metadata)
        .where(MailDomainTable.isActive.eq(true))
        .all(database.context());
    final accounts = await Query<MailAccount>(MailAccountTable.metadata)
        .where(MailAccountTable.isActive.eq(true))
        .all(database.context());

    final domainsJson = domains.map((d) => d.domain).toList();
    final accountsJson = accounts
        .map((a) => {
              'address': a.address,
              'hash': a.passwordHash,
              if (a.quotaMb != null) 'quota': a.quotaMb,
            })
        .toList();

    await _runAgent([
      'mail',
      'sync',
      '--domains',
      jsonEncode(domainsJson),
      '--accounts',
      jsonEncode(accountsJson),
    ]);
  }

  Future<void> _runAgent(List<String> args) async {
    if (hostConfig.agentMode == 'dev') {
      logger.i('mail_worker (dev): agent ${args.take(2).join(' ')} '
          '(${args.length} args)');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return;
    }
    final cmd = buildAgentCmd(args);
    logger.i('mail_worker: ${cmd.take(2).join(' ')} …');
    final result = await Process.run(cmd.first, cmd.skip(1).toList());
    if (result.exitCode != 0) {
      throw Exception('Agent exited ${result.exitCode}: ${result.stderr}'.trim());
    }
  }
}
