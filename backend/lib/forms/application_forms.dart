import 'package:gisila/gisila.dart';
import 'package:gisila_panel/forms/runtime_version.dart';

/// `POST /applications` — install a builtin Application.
class InstallApplicationForm extends Form {
  final key = StringField(name: 'key', required: true, maxLength: 64);
  final version =
      StringField(name: 'version', validators: [validRuntimeVersion]);

  @override
  List<FormField<Object?>> collectFields() => [key, version];
}

/// `POST /applications/{id}/versions` — install an additional toolchain
/// version of an already-installed Application, alongside the existing ones.
class InstallApplicationVersionForm extends Form {
  final version = StringField(
      name: 'version', required: true, validators: [validRuntimeVersion]);

  @override
  List<FormField<Object?>> collectFields() => [version];
}

/// `PATCH /applications/{id}` — update an Application's deployment defaults.
class UpdateApplicationForm extends Form {
  final defaultVersion =
      StringField(name: 'defaultVersion', validators: [validRuntimeVersion]);
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
