import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/forms/application_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/application_catalog.dart';
import 'package:gisila_panel/services/application_service.dart';

part 'applications.g.dart';

/// Application Management — install/update/remove runtime & language stacks
/// (Python, Dart, Node, …) independently of the panel itself. Apps then
/// pick one of the *installed* Applications as their deployment target.
@Controller('/applications', ['Applications'])
@RequireAuth()
class ApplicationsApi {
  // ── Catalog ───────────────────────────────────────────────────────────────

  @Get('/catalog', summary: 'List builtin Application definitions')
  Future<Map<String, Object?>> catalog(
    ApplicationService svc,
  ) async {
    return <String, Object?>{
      'results': svc.listCatalog(),
    };
  }

  // ── Installed applications ────────────────────────────────────────────────

  @Get('/', summary: 'List installed Applications')
  Future<Map<String, Object?>> list(
    ApplicationService svc,
  ) async {
    final apps = await svc.listInstalled();
    return <String, Object?>{
      'results': apps.map(_serialize).toList(),
    };
  }

  @Post('/', summary: 'Install an Application')
  Future<Map<String, Object?>> install(
    InstallApplicationForm form,
    ApplicationService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final installed = await svc.install(
      key: form.key.value!,
      version: form.version.value,
    );
    return _serialize(installed);
  }

  @Get('/{id}', summary: 'Get an Application')
  Future<Map<String, Object?>> retrieve(
    int id,
    ApplicationService svc,
  ) async {
    final app = await svc.findById(id);
    return _serialize(app, includeDef: true);
  }

  @Patch('/{id}', summary: 'Update an Application\'s deployment defaults')
  Future<Map<String, Object?>> update(
    int id,
    UpdateApplicationForm form,
    ApplicationService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final updated = await svc.update(
      id,
      defaultVersion: form.defaultVersion.value,
      defaultDeployMode: form.defaultDeployMode.value,
      defaultBuildCommand: form.defaultBuildCommand.value,
      defaultStartCommand: form.defaultStartCommand.value,
    );
    return _serialize(updated, includeDef: true);
  }

  @Delete('/{id}', summary: 'Remove an Application')
  Future<Map<String, Object?>> remove(
    int id,
    ApplicationService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await svc.remove(id);
    return <String, Object?>{'detail': 'Removal queued.'};
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Map<String, Object?> _serialize(Application a, {bool includeDef = false}) {
  final base = a.toJson();
  if (includeDef) {
    final def = findApplicationDef(a.key ?? '');
    if (def != null) base['_def'] = def.toJson();
  }
  return base;
}
