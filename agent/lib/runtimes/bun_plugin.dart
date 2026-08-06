import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

class BunPlugin extends RuntimePlugin {
  @override
  String get key => 'bun';

  @override
  List<DeployMode> get supportedModes =>
      const [DeployMode.buildExecute, DeployMode.directRun];

  @override
  bool get versioned => true;

  @override
  Future<void> installToolchain({String? version}) async {
    if (version == null || version.isEmpty) {
      // Returning quietly here used to mark the Application installed in the
      // panel while nothing had been put on disk.
      throw ArgumentError('bun requires --version, e.g. --version 1.1.38');
    }
    await Builders.installBunToolchain(version);
  }

  @override
  Future<void> removeToolchain({String? version}) =>
      Builders.removeBunToolchain(version: version);

  @override
  Future<List<String>> installedVersions() async => Builders.listBunVersions();

  @override
  Future<void> build(RuntimeBuildContext ctx) => Builders.buildBun(
        workDir: ctx.workDir,
        user: ctx.user,
        buildCommand: ctx.buildCommand,
        bunVersion: ctx.version,
        appEnv: ctx.appEnv,
        noCache: ctx.noCache,
        sourceSubdir: ctx.sourceSubdir,
      );
}
