import 'dart:convert';

import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/forms/postgres_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/postgres_service.dart';

part 'databases.g.dart';

@Controller('/databases', ['Databases'])
@RequireAuth()
class DatabasesApi {
  // ── Instances ─────────────────────────────────────────────────────────────

  @Get('/', summary: 'List installed Postgres instances')
  Future<Map<String, Object?>> listInstances(
    PostgresService svc,
  ) async {
    final instances = await svc.listInstances();
    return {'results': instances.map(_serializeInstance).toList()};
  }

  @Post('/', summary: 'Install a Postgres version')
  Future<Map<String, Object?>> installInstance(
    CreateInstanceForm form,
    PostgresService svc,
  ) async {
    final instance = await svc.installInstance(
      version: form.version.value!,
      displayName: form.displayName.value!,
      port: form.port.value,
    );
    return _serializeInstance(instance);
  }

  @Get('/{id}', summary: 'Get a Postgres instance')
  Future<Map<String, Object?>> getInstance(
    int id,
    PostgresService svc,
  ) async {
    final instance = await svc.findInstance(id);
    return _serializeInstance(instance);
  }

  @Post('/{id}/start', summary: 'Start a Postgres instance')
  Future<Map<String, Object?>> startInstance(
    int id,
    PostgresService svc,
  ) async {
    final instance = await svc.startInstance(id);
    return _serializeInstance(instance);
  }

  @Post('/{id}/stop', summary: 'Stop a Postgres instance')
  Future<Map<String, Object?>> stopInstance(
    int id,
    PostgresService svc,
  ) async {
    final instance = await svc.stopInstance(id);
    return _serializeInstance(instance);
  }

  @Post('/{id}/set-default', summary: 'Set as the preferred Postgres instance')
  Future<Map<String, Object?>> setDefault(
    int id,
    PostgresService svc,
  ) async {
    final instance = await svc.setDefault(id);
    return _serializeInstance(instance);
  }

  @Delete('/{id}', summary: 'Uninstall a Postgres instance')
  Future<Map<String, Object?>> uninstallInstance(
    int id,
    PostgresService svc,
  ) async {
    await svc.uninstallInstance(id);
    return {'detail': 'Uninstall queued.'};
  }

  // ── Metrics & configuration ─────────────────────────────────────────────────

  @Get('/{id}/metrics', summary: 'Live metrics for an instance')
  Future<Map<String, Object?>> metrics(
    int id,
    PostgresService svc,
  ) async {
    return svc.metrics(id);
  }

  @Get('/{id}/config', summary: 'Read tunable Postgres settings')
  Future<Map<String, Object?>> getConfig(
    int id,
    PostgresService svc,
  ) async {
    return svc.getConfig(id);
  }

  @Put('/{id}/config', summary: 'Update tunable Postgres settings')
  Future<Map<String, Object?>> updateConfig(
    int id,
    UpdateConfigForm form,
    PostgresService svc,
  ) async {
    final instance = await svc.updateConfig(id, _toStringMap(form.settings.value));
    return _serializeInstance(instance);
  }

  // ── Databases ─────────────────────────────────────────────────────────────

  @Get('/{id}/dbs', summary: 'List databases in this instance')
  Future<Map<String, Object?>> listDatabases(
    int id,
    PostgresService svc,
  ) async {
    final instance = await svc.findInstance(id);
    final dbs = await svc.listDatabases(id);
    return {
      'results': dbs
          .map((d) => _serializeDatabase(d,
              instance: instance, includeConnectionInfo: false))
          .toList(),
    };
  }

  @Post('/{id}/dbs', summary: 'Create a role + database')
  Future<Map<String, Object?>> createDatabase(
    int id,
    CreateDatabaseForm form,
    PostgresService svc,
  ) async {
    final instance = await svc.findInstance(id);
    final extList = _toStringList(form.extensions.value);
    final password = form.password.value?.isNotEmpty == true
        ? form.password.value!
        : generatePassword();

    final db = await svc.createDatabase(
      instanceId: id,
      dbName: form.dbName.value!,
      roleName: form.roleName.value!,
      password: password,
      extensions: extList,
    );
    // On creation we return the plain-text password once.
    return _serializeDatabase(db,
        instance: instance, includeConnectionInfo: true);
  }

  @Get('/{id}/dbs/{dbId}', summary: 'Get a database')
  Future<Map<String, Object?>> getDatabase(
    int id,
    int dbId,
    PostgresService svc,
  ) async {
    final instance = await svc.findInstance(id);
    final db = await svc.findDatabase(dbId);
    return _serializeDatabase(db,
        instance: instance, includeConnectionInfo: true);
  }

  @Delete('/{id}/dbs/{dbId}', summary: 'Drop a database and its role')
  Future<Map<String, Object?>> dropDatabase(
    int id,
    int dbId,
    PostgresService svc,
  ) async {
    await svc.dropDatabase(dbId);
    return {'detail': 'Drop queued.'};
  }
}

// ── Serialisers ───────────────────────────────────────────────────────────────

Map<String, Object?> _serializeInstance(PostgresInstance i) => {
      'id': i.id,
      'version': i.version,
      'displayName': i.displayName,
      'port': i.port,
      'status': i.status,
      'isDefault': i.isDefault,
      'dataDirectory': i.dataDirectory,
      'errorMessage': i.errorMessage,
      'installedAt': i.installedAt?.toIso8601String(),
      'createdAt': i.createdAt.toIso8601String(),
      'updatedAt': i.updatedAt?.toIso8601String(),
    };

Map<String, Object?> _serializeDatabase(
  PostgresDatabase d, {
  required PostgresInstance instance,
  required bool includeConnectionInfo,
}) {
  final base = {
    'id': d.id,
    'instanceId': d.instanceId,
    'dbName': d.dbName,
    'roleName': d.roleName,
    'extensions': jsonDecode(d.extensions ?? '[]'),
    'status': d.status,
    'errorMessage': d.errorMessage,
    'createdAt': d.createdAt.toIso8601String(),
    'updatedAt': d.updatedAt?.toIso8601String(),
  };
  if (includeConnectionInfo) {
    // We expose the plain-text password here so users can copy their
    // connection string. In a future release this could be replaced by
    // a one-time reveal endpoint.
    final svc = PostgresService(); // stateless helper call
    base['connection'] = svc.connectionInfo(instance, d);
  }
  return base;
}

List<String> _toStringList(Object? raw) {
  if (raw == null) return [];
  if (raw is List) return raw.map((e) => e.toString()).toList();
  return [];
}

Map<String, String> _toStringMap(Object? raw) {
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
  }
  return {};
}
