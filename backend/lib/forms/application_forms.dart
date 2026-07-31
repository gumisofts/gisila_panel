import 'package:gisila/gisila.dart';

/// `POST /applications` — install a builtin Application.
class InstallApplicationForm extends Form {
  final key = StringField(name: 'key', required: true, maxLength: 64);
  final version = StringField(name: 'version');

  @override
  List<FormField<Object?>> collectFields() => [key, version];
}

/// `PATCH /applications/{id}` — update an Application's deployment defaults.
class UpdateApplicationForm extends Form {
  final defaultVersion = StringField(name: 'defaultVersion');
  final defaultDeployMode = StringField(name: 'defaultDeployMode');
  final defaultBuildCommand = StringField(name: 'defaultBuildCommand');
  final defaultStartCommand = StringField(name: 'defaultStartCommand');

  @override
  List<FormField<Object?>> collectFields() => [
        defaultVersion,
        defaultDeployMode,
        defaultBuildCommand,
        defaultStartCommand,
      ];
}
