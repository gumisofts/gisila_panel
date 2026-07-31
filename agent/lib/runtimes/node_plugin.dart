import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

class NodePlugin implements RuntimePlugin {
  @override
  String get key => 'node';

  @override
  List<DeployMode> get supportedModes =>
      const [DeployMode.buildExecute, DeployMode.directRun];

  @override
  Future<void> installToolchain({String? version}) async {
    if (version == null || version.isEmpty) return;
    await Builders.installNodeToolchain(version);
  }

  @override
  Future<void> removeToolchain({String? version}) =>
      Builders.removeNodeToolchain(version: version);

  @override
  Future<void> build(RuntimeBuildContext ctx) => Builders.buildNode(
        workDir: ctx.workDir,
        user: ctx.user,
        buildCommand: ctx.buildCommand,
        nodeVersion: ctx.version,
        appEnv: ctx.appEnv,
        noCache: ctx.noCache,
        sourceSubdir: ctx.sourceSubdir,
      );
}
