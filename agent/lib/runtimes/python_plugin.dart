import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

class PythonPlugin extends RuntimePlugin {
  @override
  String get key => 'python';

  @override
  List<DeployMode> get supportedModes => const [DeployMode.directRun];

  @override
  bool get versioned => true;

  @override
  Future<void> installToolchain({String? version}) =>
      Builders.installPythonToolchain(version: version);

  @override
  Future<void> removeToolchain({String? version}) =>
      Builders.removePythonToolchain(version: version);

  @override
  Future<List<String>> installedVersions() async =>
      Builders.listPythonVersions();

  @override
  Future<void> build(RuntimeBuildContext ctx) => Builders.buildPython(
        workDir: ctx.workDir,
        user: ctx.user,
        buildCommand: ctx.buildCommand,
        pythonVersion: ctx.version,
        appEnv: ctx.appEnv,
        noCache: ctx.noCache,
        sourceSubdir: ctx.sourceSubdir,
      );
}
