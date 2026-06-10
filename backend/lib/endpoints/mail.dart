import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/forms/mail_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/mail_service.dart';

part 'mail.g.dart';

@Controller('/mail', ['Mail'])
@RequireAuth()
class MailApi {
  // ── Tooling installation ─────────────────────────────────────────────────────

  @Get('/status', summary: 'Whether the mail tooling is installed')
  Future<Map<String, Object?>> status(MailService svc) async {
    return {'installed': await svc.isStackInstalled()};
  }

  @Post('/install', summary: 'Install the mail tooling on this host')
  Future<Map<String, Object?>> install(MailService svc) async {
    await svc.enqueueInstall();
    return {'detail': 'Installation queued.'};
  }

  // ── Domains ────────────────────────────────────────────────────────────────

  @Get('/domains', summary: 'List mail domains')
  Future<Map<String, Object?>> listDomains(MailService svc) async {
    final domains = await svc.listDomains();
    return {'results': domains.map(_serializeDomain).toList()};
  }

  @Post('/domains', summary: 'Add a mail domain')
  Future<Map<String, Object?>> addDomain(
    MailDomainForm form,
    MailService svc,
  ) async {
    final domain = await svc.addDomain(form.domain.value!);
    return _serializeDomain(domain);
  }

  @Patch('/domains/{id}', summary: 'Update mail hostname / DMARC policy')
  Future<Map<String, Object?>> updateDomain(
    int id,
    MailDomainUpdateForm form,
    MailService svc,
  ) async {
    final domain = await svc.updateDomain(
      id,
      mailHostname: form.mailHostname.value,
      dmarcPolicy: form.dmarcPolicy.value,
    );
    return _serializeDomain(domain);
  }

  @Delete('/domains/{id}', summary: 'Remove a mail domain and its mailboxes')
  Future<Map<String, Object?>> removeDomain(int id, MailService svc) async {
    await svc.removeDomain(id);
    return {'detail': 'Domain removed.'};
  }

  @Get('/domains/{id}/dns', summary: 'DNS records to publish for a domain')
  Future<Map<String, Object?>> domainDns(int id, MailService svc) async {
    final domain = await svc.findDomain(id);
    return {
      'domain': domain.domain,
      'mailHostname': effectiveMailHostname(domain),
      'publicIp': domain.publicIp,
      'dkimConfigured': domain.dkimPublicKey != null && domain.dkimPublicKey!.isNotEmpty,
      'records': buildDnsRecords(domain),
    };
  }

  @Post('/domains/{id}/sync', summary: 'Re-queue a mail sync for this domain')
  Future<Map<String, Object?>> syncDomain(int id, MailService svc) async {
    await svc.findDomain(id); // validates existence
    await svc.enqueueSync();
    return {'detail': 'Sync queued.'};
  }

  // ── Mailboxes ──────────────────────────────────────────────────────────────

  @Get('/domains/{id}/accounts', summary: 'List mailboxes in a domain')
  Future<Map<String, Object?>> listAccounts(int id, MailService svc) async {
    final domain = await svc.findDomain(id);
    final accounts = await svc.listAccounts(id);
    return {
      'results': accounts.map((a) => _serializeAccount(a, domain)).toList(),
    };
  }

  @Post('/domains/{id}/accounts', summary: 'Create a mailbox')
  Future<Map<String, Object?>> addAccount(
    int id,
    MailAccountForm form,
    MailService svc,
  ) async {
    final account = await svc.addAccount(
      domainId: id,
      localPart: form.localPart.value!,
      password: form.password.value!,
      quotaMb: form.quotaMb.value,
    );
    final domain = await svc.findDomain(id);
    return _serializeAccount(account, domain);
  }

  @Put('/accounts/{id}/password', summary: 'Reset a mailbox password')
  Future<Map<String, Object?>> setPassword(
    int id,
    MailPasswordForm form,
    MailService svc,
  ) async {
    final account = await svc.setPassword(id, form.password.value!);
    final domain = await svc.findDomain(account.mailDomainId);
    return _serializeAccount(account, domain);
  }

  @Delete('/accounts/{id}', summary: 'Delete a mailbox')
  Future<Map<String, Object?>> removeAccount(int id, MailService svc) async {
    await svc.removeAccount(id);
    return {'detail': 'Mailbox deleted.'};
  }
}

Map<String, Object?> _serializeDomain(MailDomain d) => {
      'id': d.id,
      'domain': d.domain,
      'mailHostname': effectiveMailHostname(d),
      'dkimSelector': d.dkimSelector,
      'dkimConfigured': d.dkimPublicKey != null && d.dkimPublicKey!.isNotEmpty,
      'dmarcPolicy': d.dmarcPolicy ?? 'none',
      'publicIp': d.publicIp,
      'isActive': d.isActive,
      'createdAt': d.createdAt.toIso8601String(),
    };

// Note: the password hash is never serialised.
Map<String, Object?> _serializeAccount(MailAccount a, MailDomain d) => {
      'id': a.id,
      'mailDomainId': a.mailDomainId,
      'address': a.address,
      'quotaMb': a.quotaMb,
      'isActive': a.isActive,
      'createdAt': a.createdAt.toIso8601String(),
      'updatedAt': a.updatedAt?.toIso8601String(),
      'connection': buildConnectionSettings(d, a.address),
    };
