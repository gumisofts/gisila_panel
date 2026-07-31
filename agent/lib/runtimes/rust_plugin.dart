import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

class RustPlugin implements RuntimePlugin {
  @override
  String get key => 'rust';

  @override
  List<DeployMode> get supportedModes => const [DeployMode.buildExecute];

  @override
  Future<void> installToolchain({String? version}) =>
      Builders.installRustToolchain(version: version);

  @override
  Future<void> removeToolchain({String? version}) =>
      Builders.removeRustToolchain(version: version);

  @override
  Future<void> build(RuntimeBuildContext ctx) => Builders.buildRust(
        workDir: ctx.workDir,
        user: ctx.user,
        buildCommand: ctx.buildCommand,
        rustVersion: ctx.version,
        sourceSubdir: ctx.sourceSubdir,
      );
}
