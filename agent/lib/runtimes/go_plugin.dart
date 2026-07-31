import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

class GoPlugin implements RuntimePlugin {
  @override
  String get key => 'go';

  @override
  List<DeployMode> get supportedModes => const [DeployMode.buildExecute];

  @override
  Future<void> installToolchain({String? version}) async {
    if (version == null || version.isEmpty) return;
    await Builders.installGoToolchain(version);
  }

  @override
  Future<void> removeToolchain({String? version}) =>
      Builders.removeGoToolchain(version: version);

  @override
  Future<void> build(RuntimeBuildContext ctx) => Builders.buildGo(
        workDir: ctx.workDir,
        user: ctx.user,
        buildCommand: ctx.buildCommand,
        goVersion: ctx.version,
        sourceSubdir: ctx.sourceSubdir,
      );
}
