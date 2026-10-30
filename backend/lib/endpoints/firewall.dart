import 'dart:io';

import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/forms/firewall_forms.dart';
import 'package:gisila_panel/infra/client_ip.dart';
import 'package:gisila_panel/services/firewall_service.dart';

part 'firewall.g.dart';

/// The host firewall (ufw). Superusers only.
///
/// Changes are applied by the worker and rolled back unless the person who
/// made them is back on the panel within [FirewallService.confirmWindow]
/// seconds, so a change that cuts off the panel undoes itself.
@Controller('/firewall', ['Firewall'])
@RequireAuth()
class FirewallApi {
  @Get('/', summary: 'Firewall status, rules and recent changes')
  Future<Map<String, Object?>> overview(
    FirewallService firewall,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    return firewall.overview();
  }

  /// Polled by every page of the panel for superusers: the browser confirms
  /// a change it made as soon as it sees it applied.
  @Get('/pending', summary: 'The firewall change in progress')
  Future<Map<String, Object?>> pending(
    FirewallService firewall,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    return <String, Object?>{'open': await firewall.pending()};
  }

  @Post('/refresh', summary: 'Read the firewall status again')
  Future<Map<String, Object?>> refresh(
    FirewallService firewall,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await firewall.refresh();
    return <String, Object?>{'detail': 'Refresh requested.'};
  }

  @Post('/rules', summary: 'Add a rule')
  Future<Map<String, Object?>> addRule(
    FirewallRuleForm form,
    FirewallService firewall,
    RequestContext ctx,
  ) =>
      _request(firewall, ctx, 'add', form.toRule());

  @Post('/rules/remove', summary: 'Remove a rule added from the panel')
  Future<Map<String, Object?>> removeRule(
    FirewallRuleForm form,
    FirewallService firewall,
    RequestContext ctx,
  ) =>
      _request(firewall, ctx, 'delete', form.toRule());

  /// Limit 80 and 443 to some sources, such as Cloudflare's ranges when
  /// every site is proxied through it, or open them to everyone again.
  @Post('/web-sources',
      summary: 'Limit the web ports (80, 443) to some sources, or open them')
  Future<Map<String, Object?>> webSources(
    WebSourcesForm form,
    FirewallService firewall,
    RequestContext ctx,
  ) {
    requireSuperuser(ctx);
    return _request(firewall, ctx, 'web-sources',
        FirewallService.validateWebSources(
            sources: form.sources.value, preset: form.preset.value));
  }

  @Post('/enable', summary: 'Turn the firewall on')
  Future<Map<String, Object?>> enable(
    FirewallService firewall,
    RequestContext ctx,
  ) =>
      _request(firewall, ctx, 'enable', null);

  @Post('/disable', summary: 'Turn the firewall off')
  Future<Map<String, Object?>> disable(
    FirewallService firewall,
    RequestContext ctx,
  ) =>
      _request(firewall, ctx, 'disable', null);

  @Get('/changes/{id}', summary: 'Get a firewall change')
  Future<Map<String, Object?>> change(
    int id,
    FirewallService firewall,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    return firewall.change(id);
  }

  /// Sent by the requester's browser, from any page of the panel, once the
  /// change is applied. That the request arrives at all is the proof the
  /// change didn't cut them off.
  @Post('/changes/{id}/confirm', summary: 'Keep a firewall change')
  Future<Map<String, Object?>> confirm(
    int id,
    FirewallService firewall,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    return firewall.confirm(currentUser(ctx), id);
  }

  @Post('/changes/{id}/revert', summary: 'Undo a change now')
  Future<Map<String, Object?>> revert(
    int id,
    FirewallService firewall,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    return firewall.revert(id);
  }
}

Future<Map<String, Object?>> _request(
  FirewallService firewall,
  RequestContext ctx,
  String op,
  Map<String, Object?>? rule,
) async {
  requireSuperuser(ctx);
  final info = ctx.request.context['shelf.io.connection_info']
      as HttpConnectionInfo?;
  return firewall.request(
    currentUser(ctx),
    op,
    rule: rule,
    requesterIp: clientIp(ctx.request),
    // Reached directly rather than through nginx (80 / 443, which the agent
    // always protects): keep the port this request came in on open too.
    protectPorts: [
      if (info != null && !info.remoteAddress.isLoopback) info.localPort,
    ],
  );
}
