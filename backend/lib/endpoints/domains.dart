import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/forms/domain_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/domains_service.dart';

part 'domains.g.dart';

@Controller('/apps/{appId}/domains', ['Domains'])
@RequireAuth()
class DomainsApi {
  @Get('/', summary: 'List domains')
  Future<Map<String, Object?>> list(
    int appId,
    DomainsService domains,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await domains.list(user, appId);
    return <String, Object?>{
      'results': result.map((d) => d.toJson()).toList(),
    };
  }

  @Post('/', summary: 'Attach a custom domain')
  Future<Map<String, Object?>> add(
    int appId,
    AddDomainForm form,
    DomainsService domains,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final domain = await domains.add(
      user,
      appId,
      hostname: form.hostname.value!,
      isPrimary: form.isPrimary.value ?? false,
    );
    return domain.toJson();
  }

  @Post('/{id}/ssl', summary: 'Issue or renew a Let\'s Encrypt certificate')
  Future<Map<String, Object?>> issueCert(
    int appId,
    int id,
    DomainsService domains,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await domains.issueCert(user, appId, id);
    return <String, Object?>{'detail': 'Certificate issuance queued.'};
  }

  @Delete('/{id}', summary: 'Remove a domain')
  Future<Map<String, Object?>> remove(
    int appId,
    int id,
    DomainsService domains,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await domains.delete(user, appId, id);
    return <String, Object?>{'detail': 'Domain removed.'};
  }
}
