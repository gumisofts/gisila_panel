import 'package:gisila/gisila.dart';

/// `POST /apps`
class CreateAppForm extends Form {
  final projectId = IntField(name: 'projectId', required: true);
  final name = StringField(name: 'name', required: true, maxLength: 60);
  final runtime = StringField(name: 'runtime', required: true);
  // binary | git | zip
  final sourceType = StringField(name: 'sourceType', required: true);

  final gitUrl = StringField(name: 'gitUrl');
  final gitBranch = StringField(name: 'gitBranch');
  final buildCommand = StringField(name: 'buildCommand');
  final startCommand = StringField(name: 'startCommand');
  final healthCheckPath = StringField(name: 'healthCheckPath');

  final memoryMbLimit = IntField(name: 'memoryMbLimit');
  final cpuQuotaPercent = IntField(name: 'cpuQuotaPercent');
  final tasksLimit = IntField(name: 'tasksLimit');

  // Python-specific fields.
  final pythonVersion = StringField(name: 'pythonVersion');
  final pythonMode = StringField(name: 'pythonMode'); // wsgi | asgi
  final wsgiApp = StringField(name: 'wsgiApp');

  // Optional SSH deploy key for authenticated git clone.
  final deployKeyId = IntField(name: 'deployKeyId');

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        projectId,
        name,
        runtime,
        sourceType,
        gitUrl,
        gitBranch,
        buildCommand,
        startCommand,
        healthCheckPath,
        memoryMbLimit,
        cpuQuotaPercent,
        tasksLimit,
        pythonVersion,
        pythonMode,
        wsgiApp,
        deployKeyId,
      ];
}

class UpdateAppForm extends Form {
  final name = StringField(name: 'name', maxLength: 60);
  final gitUrl = StringField(name: 'gitUrl');
  final gitBranch = StringField(name: 'gitBranch');
  final buildCommand = StringField(name: 'buildCommand');
  final startCommand = StringField(name: 'startCommand');
  final healthCheckPath = StringField(name: 'healthCheckPath');
  final memoryMbLimit = IntField(name: 'memoryMbLimit');
  final cpuQuotaPercent = IntField(name: 'cpuQuotaPercent');
  final tasksLimit = IntField(name: 'tasksLimit');
  final pythonVersion = StringField(name: 'pythonVersion');
  final pythonMode = StringField(name: 'pythonMode');
  final wsgiApp = StringField(name: 'wsgiApp');
  final deployKeyId = IntField(name: 'deployKeyId');

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        name,
        gitUrl,
        gitBranch,
        buildCommand,
        startCommand,
        healthCheckPath,
        memoryMbLimit,
        cpuQuotaPercent,
        tasksLimit,
        pythonVersion,
        pythonMode,
        wsgiApp,
        deployKeyId,
      ];
}

class EnvVarForm extends Form {
  final name = StringField(name: 'name', required: true, maxLength: 200);
  final value = StringField(name: 'value');
  final isSecret = BoolField(name: 'isSecret');

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[name, value, isSecret];
}

class BulkEnvVarForm extends Form {
  final entries = JsonField(name: 'entries', required: true);

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[entries];
}
