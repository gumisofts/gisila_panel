import 'dart:convert';
import 'dart:io';

import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/authz/authz.dart';
// Generic, engine-agnostic forms are shared with the Postgres controller.
import 'package:gisila_panel/forms/postgres_forms.dart'
    show
        ExposeInstanceForm,
        UpdateConfigForm,
        BackupForm,
        BackupScheduleForm,
        RestoreBackupForm;
import 'package:gisila_panel/forms/mongo_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/mongo_service.dart';
import 'package:gisila_panel/services/postgres_service.dart'
    show generatePassword;

part 'mongo.g.dart';

@Controller('/mongo', ['MongoDB'])
@RequireAuth()
class MongoApi {
  // ── Instances ─────────────────────────────────────────────────────────────

  @Get('/', summary: 'List installed MongoDB instances')
  Future<Map<String, Object?>> listInstances(
    MongoService svc,
  ) async {
    final instances = await svc.listInstances();
    return {'results': instances.map(_serializeInstance).toList()};
  }

  @Post('/', summary: 'Install a MongoDB version')
  Future<Map<String, Object?>> installInstance(
    CreateMongoInstanceForm form,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final instance = await svc.installInstance(
      version: form.version.value!,
      displayName: form.displayName.value!,
      port: form.port.value,
    );
    return _serializeInstance(instance);
  }

  @Get('/{id}', summary: 'Get a MongoDB instance')
  Future<Map<String, Object?>> getInstance(
    int id,
    MongoService svc,
  ) async {
    return _serializeInstance(await svc.findInstance(id));
  }

  @Post('/{id}/start', summary: 'Start a MongoDB instance')
  Future<Map<String, Object?>> startInstance(
    int id,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    return _serializeInstance(await svc.startInstance(id));
  }

  @Post('/{id}/stop', summary: 'Stop a MongoDB instance')
  Future<Map<String, Object?>> stopInstance(
    int id,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    return _serializeInstance(await svc.stopInstance(id));
  }

  @Post('/{id}/set-default', summary: 'Set as the preferred MongoDB instance')
  Future<Map<String, Object?>> setDefault(
    int id,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    return _serializeInstance(await svc.setDefault(id));
  }

  @Post('/{id}/expose', summary: 'Toggle public TLS exposure for an instance')
  Future<Map<String, Object?>> exposeInstance(
    int id,
    ExposeInstanceForm form,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final instance = await svc.setPublicExposure(
      id,
      isPublic: form.isPublic.value ?? false,
      domain: form.domain.value,
    );
    return _serializeInstance(instance);
  }

  @Delete('/{id}', summary: 'Uninstall a MongoDB instance')
  Future<Map<String, Object?>> uninstallInstance(
    int id,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await svc.uninstallInstance(id);
    return {'detail': 'Uninstall queued.'};
  }

  // ── Metrics & configuration ─────────────────────────────────────────────────

  @Get('/{id}/metrics', summary: 'Live metrics for an instance')
  Future<Map<String, Object?>> metrics(int id, MongoService svc) async {
    return svc.metrics(id);
  }

  @Get('/{id}/config', summary: 'Read tunable mongod settings')
  Future<Map<String, Object?>> getConfig(int id, MongoService svc) async {
    return svc.getConfig(id);
  }

  @Put('/{id}/config', summary: 'Update tunable mongod settings')
  Future<Map<String, Object?>> updateConfig(
    int id,
    UpdateConfigForm form,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final instance =
        await svc.updateConfig(id, _toStringMap(form.settings.value));
    return _serializeInstance(instance);
  }

  // ── Databases ─────────────────────────────────────────────────────────────

  @Get('/{id}/dbs', summary: 'List databases in this instance')
  Future<Map<String, Object?>> listDatabases(
    int id,
    MongoService svc,
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

  @Post('/{id}/dbs', summary: 'Create a database + authenticated user')
  Future<Map<String, Object?>> createDatabase(
    int id,
    CreateMongoDatabaseForm form,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final instance = await svc.findInstance(id);
    final password = form.password.value?.isNotEmpty == true
        ? form.password.value!
        : generatePassword();

    final db = await svc.createDatabase(
      instanceId: id,
      dbName: form.dbName.value!,
      userName: form.userName.value!,
      password: password,
      roles: _toStringList(form.roles.value),
    );
    // On creation we return the plain-text password once.
    return _serializeDatabase(db,
        instance: instance, includeConnectionInfo: true);
  }

  @Put('/{id}/dbs/{dbId}/roles', summary: 'Update a database user\'s roles')
  Future<Map<String, Object?>> updateRoles(
    int id,
    int dbId,
    UpdateMongoRolesForm form,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final instance = await svc.findInstance(id);
    final db = await svc.updateRoles(dbId, _toStringList(form.roles.value));
    return _serializeDatabase(db,
        instance: instance, includeConnectionInfo: false);
  }

  @Get('/{id}/dbs/{dbId}', summary: 'Get a database')
  Future<Map<String, Object?>> getDatabase(
    int id,
    int dbId,
    MongoService svc,
  ) async {
    final instance = await svc.findInstance(id);
    final db = await svc.findDatabase(dbId);
    return _serializeDatabase(db,
        instance: instance, includeConnectionInfo: true);
  }

  @Delete('/{id}/dbs/{dbId}', summary: 'Drop a database and its user')
  Future<Map<String, Object?>> dropDatabase(
    int id,
    int dbId,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await svc.dropDatabase(dbId);
    return {'detail': 'Drop queued.'};
  }

  // ── Backups ───────────────────────────────────────────────────────────────

  @Get('/{id}/dbs/{dbId}/backups', summary: 'List backups for a database')
  Future<Map<String, Object?>> listBackups(
    int id,
    int dbId,
    MongoService svc,
  ) async {
    final backups = await svc.listBackups(dbId);
    return {'results': backups.map(_serializeBackup).toList()};
  }

  @Post('/{id}/dbs/{dbId}/backups', summary: 'Trigger a database backup')
  Future<Map<String, Object?>> createBackup(
    int id,
    int dbId,
    BackupForm form,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final scope = form.scope.value?.isNotEmpty == true ? form.scope.value! : 'full';
    final backup = await svc.triggerBackup(dbId, scope: scope);
    return _serializeBackup(backup);
  }

  @Get('/{id}/dbs/{dbId}/backups/{backupId}/download',
      summary: 'Download a backup file')
  Future<Response> downloadBackup(
    int id,
    int dbId,
    int backupId,
    MongoService svc,
  ) async {
    final b = await svc.findBackup(backupId);
    final path = b.filePath;
    if (b.status != 'completed' || path == null || path.isEmpty) {
      return Response.notFound('Backup is not available.');
    }
    final file = File(path);
    if (!await file.exists()) return Response.notFound('Backup file missing.');
    final name = b.fileName ?? 'backup-$backupId.archive.gz';
    return Response.ok(file.openRead(), headers: {
      'content-type': 'application/gzip',
      'content-disposition': 'attachment; filename="$name"',
      'content-length': '${await file.length()}',
    });
  }

  @Delete('/{id}/dbs/{dbId}/backups/{backupId}', summary: 'Delete a backup')
  Future<Map<String, Object?>> deleteBackup(
    int id,
    int dbId,
    int backupId,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await svc.deleteBackup(backupId);
    return {'detail': 'Backup deleted.'};
  }

  @Post('/{id}/dbs/{dbId}/restore',
      summary: 'Restore a database from a stored backup')
  Future<Map<String, Object?>> restoreBackup(
    int id,
    int dbId,
    RestoreBackupForm form,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await svc.restoreFromBackup(form.backupId.value!);
    return {'detail': 'Restore queued.'};
  }

  @Post('/{id}/dbs/{dbId}/restore-upload',
      summary: 'Restore a database from an uploaded dump')
  Future<Map<String, Object?>> restoreUpload(
    int id,
    int dbId,
    RequestContext ctx,
    MongoService svc,
  ) async {
    requireSuperuser(ctx);
    final filename = ctx.request.headers['x-filename'] ?? 'upload.archive';
    final bytes = <int>[];
    await for (final chunk in ctx.request.read()) {
      bytes.addAll(chunk);
    }
    await svc.saveUploadAndRestore(dbId, bytes, filename);
    return {'detail': 'Restore queued.'};
  }

  // ── Backup schedule ─────────────────────────────────────────────────────────

  @Get('/{id}/dbs/{dbId}/backup-schedule',
      summary: 'Get a database backup schedule')
  Future<Map<String, Object?>> getSchedule(
    int id,
    int dbId,
    MongoService svc,
  ) async {
    return _serializeSchedule(await svc.getSchedule(dbId));
  }

  @Put('/{id}/dbs/{dbId}/backup-schedule',
      summary: 'Update a database backup schedule')
  Future<Map<String, Object?>> updateSchedule(
    int id,
    int dbId,
    BackupScheduleForm form,
    MongoService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final s = await svc.updateSchedule(
      dbId,
      enabled: form.enabled.value,
      frequency: form.frequency.value,
      hour: form.hour.value,
      minute: form.minute.value,
      weekday: form.weekday.value,
      scope: form.scope.value?.isNotEmpty == true ? form.scope.value : null,
      keepCount: form.keepCount.value,
    );
    return _serializeSchedule(s);
  }
}

// ── Serialisers ───────────────────────────────────────────────────────────────

Map<String, Object?> _serializeInstance(MongoInstance i) => {
      'id': i.id,
      'engine': 'mongodb',
      'version': i.version,
      'displayName': i.displayName,
      'port': i.port,
      'status': i.status,
      'isDefault': i.isDefault,
      'isPublic': i.isPublic ?? false,
      'publicDomain': i.publicDomain,
      'dataDirectory': i.dataDirectory,
      'errorMessage': i.errorMessage,
      'installedAt': i.installedAt?.toIso8601String(),
      'createdAt': i.createdAt.toIso8601String(),
      'updatedAt': i.updatedAt?.toIso8601String(),
    };

Map<String, Object?> _serializeDatabase(
  MongoDatabase d, {
  required MongoInstance instance,
  required bool includeConnectionInfo,
}) {
  final base = <String, Object?>{
    'id': d.id,
    'instanceId': d.instanceId,
    'dbName': d.dbName,
    'userName': d.userName,
    'roles': jsonDecode(d.roles ?? '[]'),
    'status': d.status,
    'errorMessage': d.errorMessage,
    'createdAt': d.createdAt.toIso8601String(),
    'updatedAt': d.updatedAt?.toIso8601String(),
  };
  if (includeConnectionInfo) {
    final svc = MongoService(); // stateless helper call
    base['connection'] = svc.connectionInfo(instance, d);
  }
  return base;
}

Map<String, Object?> _serializeBackup(MongoBackup b) => {
      'id': b.id,
      'databaseId': b.databaseId,
      'fileName': b.fileName,
      'sizeBytes': b.sizeBytes,
      'scope': b.scope ?? 'full',
      'status': b.status,
      'trigger': b.trigger,
      'errorMessage': b.errorMessage,
      'startedAt': b.startedAt?.toIso8601String(),
      'completedAt': b.completedAt?.toIso8601String(),
      'createdAt': b.createdAt.toIso8601String(),
    };

Map<String, Object?> _serializeSchedule(MongoBackupSchedule s) => {
      'id': s.id,
      'databaseId': s.databaseId,
      'enabled': s.enabled ?? false,
      'frequency': s.frequency ?? 'daily',
      'hour': s.hour ?? 2,
      'minute': s.minute ?? 0,
      'weekday': s.weekday,
      'scope': s.scope ?? 'full',
      'keepCount': s.keepCount ?? 7,
      'nextRunAt': s.nextRunAt?.toIso8601String(),
      'createdAt': s.createdAt.toIso8601String(),
      'updatedAt': s.updatedAt?.toIso8601String(),
    };

List<String> _toStringList(Object? raw) {
  if (raw is List) return raw.map((e) => e.toString()).toList();
  return [];
}

Map<String, String> _toStringMap(Object? raw) {
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
  }
  return {};
}
