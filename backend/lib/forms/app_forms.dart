import 'package:gisila/gisila.dart';

/// `POST /apps`
class CreateAppForm extends Form {
  final projectId = IntField(name: 'projectId', required: true);
  final name = StringField(name: 'name', required: true, maxLength: 60);
  // Preferred: pick an installed Application by id. `runtime` is kept as a
  // deprecated free-text alias for backward compatibility — when
  // `applicationId` is supplied it wins and `runtime` is derived from it.
  final applicationId = IntField(name: 'applicationId');
  final runtime = StringField(name: 'runtime');
  // build_execute | direct_run | static_publish — must be one of the chosen
  // Application's supported deploy_modes. Defaults to that Application's
  // defaultDeployMode when omitted.
  final deploymentMode = StringField(name: 'deploymentMode');
  // binary | git | zip
  final sourceType = StringField(name: 'sourceType', required: true);

  final gitUrl = StringField(name: 'gitUrl');
  final gitBranch = StringField(name: 'gitBranch');
  // Optional subdirectory within the repo to build/run from, so a single
  // monorepo can be deployed by pointing at just one of its projects.
  final sourceSubdir = StringField(name: 'sourceSubdir');
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

  // Gunicorn tuning (python only).
  final gunicornWorkers = IntField(name: 'gunicornWorkers');
  final gunicornThreads = IntField(name: 'gunicornThreads');
  final gunicornTimeout = IntField(name: 'gunicornTimeout');
  final gunicornBind = StringField(name: 'gunicornBind');
  final gunicornExtraArgs = StringField(name: 'gunicornExtraArgs');

  // Runtime version pins.
  final nodeVersion = StringField(name: 'nodeVersion');
  final dartVersion = StringField(name: 'dartVersion');
  final goVersion = StringField(name: 'goVersion');
  final rustVersion = StringField(name: 'rustVersion');
  final bunVersion = StringField(name: 'bunVersion');

  // Celery-specific fields.
  final celeryApp = StringField(name: 'celeryApp');
  final celeryWorkerCount = IntField(name: 'celeryWorkerCount');
  final celeryConcurrency = IntField(name: 'celeryConcurrency');
  final celeryQueues = StringField(name: 'celeryQueues');
  final celeryBeatEnabled = BoolField(name: 'celeryBeatEnabled');
  final celeryExtraArgs = StringField(name: 'celeryExtraArgs');

  // Static site fields.
  final staticRoot = StringField(name: 'staticRoot');
  final staticSpa = BoolField(name: 'staticSpa');

  // Local disk media (Model A).
  final mediaEnabled = BoolField(name: 'mediaEnabled');
  final mediaMaxUploadMb = IntField(name: 'mediaMaxUploadMb');

  // Optional SSH deploy key for authenticated git clone.
  final deployKeyId = IntField(name: 'deployKeyId');

  // Internal port the app listens on. Optional: static sites have none.
  // The service requires it for every non-static runtime.
  final internalPort = IntField(name: 'internalPort');

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        projectId,
        name,
        applicationId,
        runtime,
        deploymentMode,
        sourceType,
        gitUrl,
        gitBranch,
        sourceSubdir,
        buildCommand,
        startCommand,
        healthCheckPath,
        memoryMbLimit,
        cpuQuotaPercent,
        tasksLimit,
        pythonVersion,
        pythonMode,
        wsgiApp,
        gunicornWorkers,
        gunicornThreads,
        gunicornTimeout,
        gunicornBind,
        gunicornExtraArgs,
        nodeVersion,
        dartVersion,
        goVersion,
        rustVersion,
        bunVersion,
        celeryApp,
        celeryWorkerCount,
        celeryConcurrency,
        celeryQueues,
        celeryBeatEnabled,
        celeryExtraArgs,
        staticRoot,
        staticSpa,
        mediaEnabled,
        mediaMaxUploadMb,
        deployKeyId,
        internalPort,
      ];
}

class UpdateAppForm extends Form {
  final name = StringField(name: 'name', maxLength: 60);
  final gitUrl = StringField(name: 'gitUrl');
  final gitBranch = StringField(name: 'gitBranch');
  final sourceSubdir = StringField(name: 'sourceSubdir');
  final buildCommand = StringField(name: 'buildCommand');
  final startCommand = StringField(name: 'startCommand');
  final healthCheckPath = StringField(name: 'healthCheckPath');
  final memoryMbLimit = IntField(name: 'memoryMbLimit');
  final cpuQuotaPercent = IntField(name: 'cpuQuotaPercent');
  final tasksLimit = IntField(name: 'tasksLimit');
  final pythonVersion = StringField(name: 'pythonVersion');
  final pythonMode = StringField(name: 'pythonMode');
  final wsgiApp = StringField(name: 'wsgiApp');
  final gunicornWorkers = IntField(name: 'gunicornWorkers');
  final gunicornThreads = IntField(name: 'gunicornThreads');
  final gunicornTimeout = IntField(name: 'gunicornTimeout');
  final gunicornBind = StringField(name: 'gunicornBind');
  final gunicornExtraArgs = StringField(name: 'gunicornExtraArgs');
  final nodeVersion = StringField(name: 'nodeVersion');
  final dartVersion = StringField(name: 'dartVersion');
  final goVersion = StringField(name: 'goVersion');
  final rustVersion = StringField(name: 'rustVersion');
  final bunVersion = StringField(name: 'bunVersion');
  final celeryApp = StringField(name: 'celeryApp');
  final celeryWorkerCount = IntField(name: 'celeryWorkerCount');
  final celeryConcurrency = IntField(name: 'celeryConcurrency');
  final celeryQueues = StringField(name: 'celeryQueues');
  final celeryBeatEnabled = BoolField(name: 'celeryBeatEnabled');
  final celeryExtraArgs = StringField(name: 'celeryExtraArgs');
  final staticRoot = StringField(name: 'staticRoot');
  final staticSpa = BoolField(name: 'staticSpa');
  final mediaEnabled = BoolField(name: 'mediaEnabled');
  final mediaMaxUploadMb = IntField(name: 'mediaMaxUploadMb');
  final deployKeyId = IntField(name: 'deployKeyId');
  final internalPort = IntField(name: 'internalPort');

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        name,
        gitUrl,
        gitBranch,
        sourceSubdir,
        buildCommand,
        startCommand,
        healthCheckPath,
        memoryMbLimit,
        cpuQuotaPercent,
        tasksLimit,
        pythonVersion,
        pythonMode,
        wsgiApp,
        gunicornWorkers,
        gunicornThreads,
        gunicornTimeout,
        gunicornBind,
        gunicornExtraArgs,
        nodeVersion,
        dartVersion,
        goVersion,
        rustVersion,
        bunVersion,
        celeryApp,
        celeryWorkerCount,
        celeryConcurrency,
        celeryQueues,
        celeryBeatEnabled,
        celeryExtraArgs,
        staticRoot,
        staticSpa,
        mediaEnabled,
        mediaMaxUploadMb,
        deployKeyId,
        internalPort,
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

/// `POST /apps/{id}/exec` — run a one-off command in the app environment.
class ExecCommandForm extends Form {
  final command = StringField(name: 'command', required: true, maxLength: 4000);

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[command];
}
