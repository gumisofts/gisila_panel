import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

class NodePlugin extends RuntimePlugin {
  @override
  String get key => 'node';

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
      throw ArgumentError('node requires --version, e.g. --version 22.20.0');
    }
    await Builders.installNodeToolchain(version);
  }

  @override
  Future<void> removeToolchain({String? version}) =>
      Builders.removeNodeToolchain(version: version);

  @override
  Future<List<String>> installedVersions() async => Builders.listNodeVersions();

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
