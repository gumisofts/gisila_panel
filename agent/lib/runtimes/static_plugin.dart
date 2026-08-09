import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

/// Static sites have no process unit — nginx serves the published files
/// directly. No toolchain of its own; an optional Node build step is handled
/// by [Builders.buildStatic] delegating to [Builders.buildNode].
class StaticPlugin extends RuntimePlugin {
  @override
  String get key => 'static';

  @override
  List<DeployMode> get supportedModes => const [DeployMode.staticPublish];

  @override
  Future<void> installToolchain({String? version}) async {}

  @override
  Future<void> removeToolchain({String? version}) async {}

  @override
  Future<void> build(RuntimeBuildContext ctx) => Builders.buildStatic(
        workDir: ctx.workDir,
        user: ctx.user,
        buildCommand: ctx.buildCommand,
        nodeVersion: ctx.version,
        appEnv: ctx.appEnv,
        noCache: ctx.noCache,
        sourceSubdir: ctx.sourceSubdir,
      );
}
