import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

/// Celery reuses the Python toolchain (pyenv) — see [Builders.buildCelery].
class CeleryPlugin implements RuntimePlugin {
  @override
  String get key => 'celery';

  @override
  List<DeployMode> get supportedModes => const [DeployMode.buildExecute];

  @override
  Future<void> installToolchain({String? version}) =>
      Builders.installPythonToolchain(version: version);

  @override
  Future<void> removeToolchain({String? version}) =>
      Builders.removePythonToolchain(version: version);

  @override
  Future<void> build(RuntimeBuildContext ctx) => Builders.buildCelery(
        workDir: ctx.workDir,
        user: ctx.user,
        buildCommand: ctx.buildCommand,
        pythonVersion: ctx.version,
        appEnv: ctx.appEnv,
        noCache: ctx.noCache,
        sourceSubdir: ctx.sourceSubdir,
      );
}
