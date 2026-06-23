import 'package:gisila/gisila.dart';

/// `POST /mongo` — install a new MongoDB version.
class CreateMongoInstanceForm extends Form {
  // Mongo versions are strings: "6.0" | "7.0" | "8.0".
  final version = StringField(name: 'version', required: true, maxLength: 16);
  final displayName =
      StringField(name: 'displayName', required: true, maxLength: 128);
  final port = IntField(name: 'port'); // optional

  @override
  List<FormField<Object?>> collectFields() => [version, displayName, port];
}

/// `POST /mongo/{id}/dbs` — create a database + authenticated user inside an
/// instance.
class CreateMongoDatabaseForm extends Form {
  final dbName = StringField(name: 'dbName', required: true, maxLength: 63);
  final userName = StringField(name: 'userName', required: true, maxLength: 63);
  // If omitted the API auto-generates a secure password.
  final password = StringField(name: 'password', maxLength: 128);
  // JSON array of built-in roles: ["readWrite","dbAdmin"]
  final roles = JsonField(name: 'roles');

  @override
  List<FormField<Object?>> collectFields() =>
      [dbName, userName, password, roles];
}

/// `PUT /mongo/{id}/dbs/{dbId}/roles` — update a database user's roles.
class UpdateMongoRolesForm extends Form {
  // JSON array: ["readWrite"] or [] to strip all roles.
  final roles = JsonField(name: 'roles', required: true);

  @override
  List<FormField<Object?>> collectFields() => [roles];
}
