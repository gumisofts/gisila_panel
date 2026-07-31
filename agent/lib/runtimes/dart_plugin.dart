import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

class DartPlugin implements RuntimePlugin {
  @override
  String get key => 'dart';

  @override
  List<DeployMode> get supportedModes => const [DeployMode.buildExecute];

  @override
  Future<void> installToolchain({String? version}) async {
    if (version == null || version.isEmpty) return;
    await Builders.installDartToolchain(version);
  }

  @override
  Future<void> removeToolchain({String? version}) =>
      Builders.removeDartToolchain(version: version);

  @override
  Future<void> build(RuntimeBuildContext ctx) => Builders.buildDart(
        workDir: ctx.workDir,
        user: ctx.user,
        buildCommand: ctx.buildCommand,
        dartVersion: ctx.version,
        sourceSubdir: ctx.sourceSubdir,
      );
}
