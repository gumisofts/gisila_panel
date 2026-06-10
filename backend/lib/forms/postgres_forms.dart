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

  @override
  List<FormField<Object?>> collectFields() =>
      [dbName, roleName, password, extensions];
}
