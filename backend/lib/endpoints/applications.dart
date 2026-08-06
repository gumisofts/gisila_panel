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
    final versions = await svc.versionsByApplication();
    return <String, Object?>{
      'results': [
        for (final app in apps)
          _serialize(app, versions: versions[app.id] ?? const []),
      ],
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
    return _serialize(
      app,
      includeDef: true,
      versions: await svc.listVersions(id),
    );
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

  // ── Installed versions ────────────────────────────────────────────────────

  @Get('/{id}/versions', summary: 'List installed versions of an Application')
  Future<Map<String, Object?>> versions(
    int id,
    ApplicationService svc,
  ) async {
    final rows = await svc.listVersions(id);
    return <String, Object?>{
      'results': rows.map((v) => v.toJson()).toList(),
    };
  }

  @Post('/{id}/versions', summary: 'Install another version alongside the rest')
  Future<Map<String, Object?>> installVersion(
    int id,
    InstallApplicationVersionForm form,
    ApplicationService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final row = await svc.installVersion(id, form.version.value!);
    return row.toJson();
  }

  @Delete('/{id}/versions/{versionId}', summary: 'Remove one installed version')
  Future<Map<String, Object?>> removeVersion(
    int id,
    int versionId,
    ApplicationService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await svc.removeVersion(id, versionId);
    return <String, Object?>{'detail': 'Removal queued.'};
  }

  @Post(
    '/{id}/versions/{versionId}/default',
    summary: 'Make this the version new apps get',
  )
  Future<Map<String, Object?>> setDefaultVersion(
    int id,
    int versionId,
    ApplicationService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final row = await svc.setDefaultVersion(id, versionId);
    return row.toJson();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Map<String, Object?> _serialize(
  Application a, {
  bool includeDef = false,
  List<ApplicationVersion> versions = const [],
}) {
  final base = a.toJson();
  base['versions'] = versions.map((v) => v.toJson()).toList();
  if (includeDef) {
    final def = findApplicationDef(a.key ?? '');
    if (def != null) base['_def'] = def.toJson();
  }
  return base;
}
