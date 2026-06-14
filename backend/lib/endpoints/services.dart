import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/forms/service_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/catalog.dart';
import 'package:gisila_panel/services/managed_service_service.dart';

part 'services.g.dart';

@Controller('/services', ['Services'])
@RequireAuth()
class ServicesApi {
  // ── Catalog ───────────────────────────────────────────────────────────────

  @Get('/catalog', summary: 'List available service types')
  Future<Map<String, Object?>> catalog(
    ManagedServiceService svc,
  ) async {
    return <String, Object?>{
      'results': svc.listCatalog(),
    };
  }

  // ── Installed services ────────────────────────────────────────────────────

  @Get('/', summary: 'List installed services')
  Future<Map<String, Object?>> list(
    ManagedServiceService svc,
  ) async {
    final services = await svc.listInstalled();
    return <String, Object?>{
      'results': services.map(_serialize).toList(),
    };
  }

  @Post('/', summary: 'Install a service')
  Future<Map<String, Object?>> install(
    InstallServiceForm form,
    ManagedServiceService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final installed = await svc.install(
      serviceType: form.serviceType.value!,
      displayName: form.displayName.value!,
      config: _toStringMap(form.config.value),
    );
    return _serialize(installed);
  }

  @Get('/{id}', summary: 'Get a service')
  Future<Map<String, Object?>> retrieve(
    int id,
    ManagedServiceService svc,
  ) async {
    final service = await svc.findById(id);
    return _serialize(service, includeDef: true);
  }

  @Put('/{id}/config', summary: 'Update service configuration')
  Future<Map<String, Object?>> configure(
    int id,
    UpdateServiceConfigForm form,
    ManagedServiceService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final updated = await svc.configure(
      id,
      _toStringMap(form.config.value),
    );
    return _serialize(updated, includeDef: true);
  }

  @Post('/{id}/start', summary: 'Start a service')
  Future<Map<String, Object?>> start(
    int id,
    ManagedServiceService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final updated = await svc.start(id);
    return _serialize(updated);
  }

  @Post('/{id}/stop', summary: 'Stop a service')
  Future<Map<String, Object?>> stop(
    int id,
    ManagedServiceService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final updated = await svc.stop(id);
    return _serialize(updated);
  }

  @Delete('/{id}', summary: 'Uninstall a service')
  Future<Map<String, Object?>> uninstall(
    int id,
    ManagedServiceService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await svc.uninstall(id);
    return <String, Object?>{'detail': 'Uninstall queued.'};
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Map<String, String> _toStringMap(Object? raw) {
  if (raw == null) return {};
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
  }
  return {};
}

Map<String, Object?> _serialize(ManagedService s, {bool includeDef = false}) {
  final base = s.toJson();
  if (includeDef) {
    final def = findService(s.serviceType);
    if (def != null) base['_def'] = def.toJson();
  }
  return base;
}
