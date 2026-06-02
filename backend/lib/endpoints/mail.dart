import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/forms/mail_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/mail_service.dart';

part 'mail.g.dart';

@Controller('/mail', ['Mail'])
@RequireAuth()
class MailApi {
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

  @Delete('/domains/{id}', summary: 'Remove a mail domain and its mailboxes')
  Future<Map<String, Object?>> removeDomain(int id, MailService svc) async {
    await svc.removeDomain(id);
    return {'detail': 'Domain removed.'};
  }

  // ── Mailboxes ──────────────────────────────────────────────────────────────

  @Get('/domains/{id}/accounts', summary: 'List mailboxes in a domain')
  Future<Map<String, Object?>> listAccounts(int id, MailService svc) async {
    await svc.findDomain(id);
    final accounts = await svc.listAccounts(id);
    return {'results': accounts.map(_serializeAccount).toList()};
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
    return _serializeAccount(account);
  }

  @Put('/accounts/{id}/password', summary: 'Reset a mailbox password')
  Future<Map<String, Object?>> setPassword(
    int id,
    MailPasswordForm form,
    MailService svc,
  ) async {
    final account = await svc.setPassword(id, form.password.value!);
    return _serializeAccount(account);
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
      'isActive': d.isActive,
      'createdAt': d.createdAt.toIso8601String(),
    };

// Note: the password hash is never serialised.
Map<String, Object?> _serializeAccount(MailAccount a) => {
      'id': a.id,
      'mailDomainId': a.mailDomainId,
      'address': a.address,
      'quotaMb': a.quotaMb,
      'isActive': a.isActive,
      'createdAt': a.createdAt.toIso8601String(),
      'updatedAt': a.updatedAt?.toIso8601String(),
    };
