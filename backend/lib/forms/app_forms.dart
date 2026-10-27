import 'dart:io';

import 'package:gisila/gisila.dart';
import 'package:gisila_panel/forms/runtime_version.dart';

// systemd's CPUQuota is "percent of one core" — a value above what the host
// actually has doesn't error, it just can never be reached, so the API caps
// it here (not just in the frontend's `<input max>` hint) at however many
// cores the panel process itself sees on this host.
final int _maxCpuQuotaPercent = Platform.numberOfProcessors * 100;

/// A [StringField] that binds an empty string as `""` rather than treating it
/// as absent, so a PATCH can tell "clear this field" apart from "leave it".
class _ClearableStringField extends StringField {
  _ClearableStringField({required super.name});

  @override
  bool isAbsent(Object? raw) => raw == null;
}

// Mirrors the agent's AgentValidators.requireGitUrl / optionalGitRef so a
// bad value is refused when the app is saved, not at deploy time. Remote
// transports only: `file://` and local paths would let one app clone another
// app's tree from /srv/apps.
final _gitUrlRe = RegExp(
    r'^(?:(?:https?|ssh|git)://[A-Za-z0-9\[][A-Za-z0-9._~%!$&()*+,;=:@\[\]-]*'
    r'(?:/\S*)?'
    r'|[A-Za-z0-9._-]+@[A-Za-z0-9][A-Za-z0-9.-]*:[^\s-]\S*)$');
final _gitRefRe = RegExp(r'^[A-Za-z0-9._@+-]+(/[A-Za-z0-9._@+-]+)*$');

String? _validGitUrl(String v) {
  if (v.isEmpty) return null;
  if (v.length > 2048 || v.startsWith('-') || !_gitUrlRe.hasMatch(v)) {
    return 'Use an https://, ssh:// or user@host:path git URL.';
  }
  return null;
}

String? _validGitRef(String v) {
  if (v.isEmpty) return null;
  if (v.length > 255 ||
      v.startsWith('-') ||
      v.contains('..') ||
      v.contains('@{') ||
      v.endsWith('.lock') ||
      !_gitRefRe.hasMatch(v)) {
    return 'Not a valid branch or tag name.';
  }
  return null;
}

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

  final gitUrl = StringField(name: 'gitUrl', validators: [_validGitUrl]);
  final gitBranch =
      StringField(name: 'gitBranch', validators: [_validGitRef]);
  // Optional subdirectory within the repo to build/run from, so a single
  // monorepo can be deployed by pointing at just one of its projects.
  final sourceSubdir = StringField(name: 'sourceSubdir');
  final buildCommand = StringField(name: 'buildCommand');
  final startCommand = StringField(name: 'startCommand');
  final healthCheckPath = StringField(name: 'healthCheckPath');

  final memoryMbLimit = IntField(name: 'memoryMbLimit');
  final cpuQuotaPercent =
      IntField(name: 'cpuQuotaPercent', min: 1, max: _maxCpuQuotaPercent);
  final tasksLimit = IntField(name: 'tasksLimit');

  // Python-specific fields.
  final pythonVersion =
      StringField(name: 'pythonVersion', validators: [validRuntimeVersion]);
  final pythonMode = StringField(name: 'pythonMode'); // wsgi | asgi
  final wsgiApp = StringField(name: 'wsgiApp');

  // Gunicorn tuning (python only).
  final gunicornWorkers = IntField(name: 'gunicornWorkers');
  final gunicornThreads = IntField(name: 'gunicornThreads');
  final gunicornTimeout = IntField(name: 'gunicornTimeout');
  final gunicornBind = StringField(name: 'gunicornBind');
  final gunicornExtraArgs = StringField(name: 'gunicornExtraArgs');

  // Runtime version pins.
  final nodeVersion =
      StringField(name: 'nodeVersion', validators: [validRuntimeVersion]);
  final dartVersion =
      StringField(name: 'dartVersion', validators: [validRuntimeVersion]);
  final goVersion = StringField(name: 'goVersion', validators: [validRuntimeVersion]);
  final rustVersion =
      StringField(name: 'rustVersion', validators: [validRuntimeVersion]);
  final bunVersion =
      StringField(name: 'bunVersion', validators: [validRuntimeVersion]);

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

  // web (default) | tcp | internal — set once at creation, immutable
  // afterward. See kExposeModes in apps_service.dart.
  final exposeMode = StringField(name: 'exposeMode');
  // Only meaningful when exposeMode = tcp.
  final publiclyReachable = BoolField(name: 'publiclyReachable');

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
        exposeMode,
        publiclyReachable,
      ];
}

class UpdateAppForm extends Form {
  final name = StringField(name: 'name', maxLength: 60);
  // Moves the app to another project (see AppsService._authorizeMove).
  final projectId = IntField(name: 'projectId');
  final gitUrl = StringField(name: 'gitUrl', validators: [_validGitUrl]);
  final gitBranch =
      StringField(name: 'gitBranch', validators: [_validGitRef]);
  // Sent as "" to go back to building/running from the repo root.
  final sourceSubdir = _ClearableStringField(name: 'sourceSubdir');
  final buildCommand = StringField(name: 'buildCommand');
  final startCommand = StringField(name: 'startCommand');
  final healthCheckPath = StringField(name: 'healthCheckPath');
  // Previous successful builds kept on disk for instant rollback.
  final releasesToKeep = IntField(name: 'releasesToKeep', min: 1, max: 50);
  final memoryMbLimit = IntField(name: 'memoryMbLimit');
  final cpuQuotaPercent =
      IntField(name: 'cpuQuotaPercent', min: 1, max: _maxCpuQuotaPercent);
  final tasksLimit = IntField(name: 'tasksLimit');
  final pythonVersion =
      StringField(name: 'pythonVersion', validators: [validRuntimeVersion]);
  final pythonMode = StringField(name: 'pythonMode');
  final wsgiApp = StringField(name: 'wsgiApp');
  final gunicornWorkers = IntField(name: 'gunicornWorkers');
  final gunicornThreads = IntField(name: 'gunicornThreads');
  final gunicornTimeout = IntField(name: 'gunicornTimeout');
  final gunicornBind = StringField(name: 'gunicornBind');
  final gunicornExtraArgs = StringField(name: 'gunicornExtraArgs');
  final nodeVersion =
      StringField(name: 'nodeVersion', validators: [validRuntimeVersion]);
  final dartVersion =
      StringField(name: 'dartVersion', validators: [validRuntimeVersion]);
  final goVersion = StringField(name: 'goVersion', validators: [validRuntimeVersion]);
  final rustVersion =
      StringField(name: 'rustVersion', validators: [validRuntimeVersion]);
  final bunVersion =
      StringField(name: 'bunVersion', validators: [validRuntimeVersion]);
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
        projectId,
        gitUrl,
        gitBranch,
        sourceSubdir,
        buildCommand,
        startCommand,
        healthCheckPath,
        releasesToKeep,
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

/// `POST /apps/{id}/network` — toggle firewall exposure for a `tcp` app.
class NetworkExposureForm extends Form {
  final publiclyReachable =
      BoolField(name: 'publiclyReachable', required: true);

  @override
  List<FormField<Object?>> collectFields() =>
      <FormField<Object?>>[publiclyReachable];
}

/// `POST /apps/{id}/exec` — run a one-off command in the app environment.
class ExecCommandForm extends Form {
  final command = StringField(name: 'command', required: true, maxLength: 4000);

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[command];
}
