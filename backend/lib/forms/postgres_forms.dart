import 'package:gisila/gisila.dart';

/// `POST /databases` — install a new Postgres version.
class CreateInstanceForm extends Form {
  final version = IntField(name: 'version', required: true);
  final displayName =
      StringField(name: 'displayName', required: true, maxLength: 128);
  final port = IntField(name: 'port');

  @override
  List<FormField<Object?>> collectFields() => [version, displayName, port];
}

/// `POST /databases/{id}/expose` — toggle public TLS exposure for an instance.
class ExposeInstanceForm extends Form {
  final isPublic = BoolField(name: 'isPublic', required: true);
  // Required when isPublic is true; ignored otherwise.
  final domain = StringField(name: 'domain', maxLength: 255);

  @override
  List<FormField<Object?>> collectFields() => [isPublic, domain];
}

/// `PUT /databases/{id}/config` — update tunable Postgres settings.
class UpdateConfigForm extends Form {
  // JSON object of { settingName: "value", … }.
  final settings = JsonField(name: 'settings', required: true);

  @override
  List<FormField<Object?>> collectFields() => [settings];
}

/// `POST /databases/{id}/dbs/{dbId}/backups` — trigger a backup.
class BackupForm extends Form {
  // full | schema | data; defaults to full when omitted.
  final scope = StringField(name: 'scope', maxLength: 16);

  @override
  List<FormField<Object?>> collectFields() => [scope];
}

/// `PUT /databases/{id}/dbs/{dbId}/backup-schedule` — partial schedule update.
class BackupScheduleForm extends Form {
  final enabled = BoolField(name: 'enabled');
  final frequency = StringField(name: 'frequency', maxLength: 16);
  final hour = IntField(name: 'hour');
  final minute = IntField(name: 'minute');
  final weekday = IntField(name: 'weekday');
  final scope = StringField(name: 'scope', maxLength: 16);
  final keepCount = IntField(name: 'keepCount');

  @override
  List<FormField<Object?>> collectFields() =>
      [enabled, frequency, hour, minute, weekday, scope, keepCount];
}

/// `POST /databases/{id}/dbs/{dbId}/restore` — restore from a stored backup.
class RestoreBackupForm extends Form {
  final backupId = IntField(name: 'backupId', required: true);

  @override
  List<FormField<Object?>> collectFields() => [backupId];
}

/// `POST /databases/{id}/dbs` — create a role + database inside an instance.
class CreateDatabaseForm extends Form {
  final dbName = StringField(name: 'dbName', required: true, maxLength: 63);
  final roleName = StringField(name: 'roleName', required: true, maxLength: 63);
  // If omitted the API auto-generates a secure password.
  final password = StringField(name: 'password', maxLength: 128);
  // JSON array of extension names to create, e.g. ["uuid-ossp","pg_trgm"].
  final extensions = JsonField(name: 'extensions');
  // JSON array of role attributes to grant the new role, e.g.
  // ["CREATEDB","CREATEROLE"]. Validated against a whitelist by the service.
  final roleAttributes = JsonField(name: 'roleAttributes');

  @override
  List<FormField<Object?>> collectFields() =>
      [dbName, roleName, password, extensions, roleAttributes];
}

/// `PUT /databases/{id}/dbs/{dbId}/role` — change a database role's attributes
/// (permissions) after creation. The full desired set is sent each time; the
/// service reconciles via `ALTER ROLE` (granting and revoking as needed).
class UpdateRoleForm extends Form {
  // JSON array of the attributes the role should have, e.g. ["CREATEDB"].
  // An empty array strips every optional attribute (role keeps only LOGIN).
  final roleAttributes = JsonField(name: 'roleAttributes', required: true);

  @override
  List<FormField<Object?>> collectFields() => [roleAttributes];
}
