import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

class GoPlugin extends RuntimePlugin {
  @override
  String get key => 'go';

  @override
  List<DeployMode> get supportedModes => const [DeployMode.buildExecute];

  @override
  bool get versioned => true;

  @override
  Future<void> installToolchain({String? version}) async {
    if (version == null || version.isEmpty) {
      // Returning quietly here used to mark the Application installed in the
      // panel while nothing had been put on disk.
      throw ArgumentError('go requires --version, e.g. --version 1.23.4');
    }
    await Builders.installGoToolchain(version);
  }

  @override
  Future<void> removeToolchain({String? version}) =>
      Builders.removeGoToolchain(version: version);

  @override
  Future<List<String>> installedVersions() async => Builders.listGoVersions();

  @override
  Future<void> build(RuntimeBuildContext ctx) => Builders.buildGo(
        workDir: ctx.workDir,
        user: ctx.user,
        buildCommand: ctx.buildCommand,
        goVersion: ctx.version,
        sourceSubdir: ctx.sourceSubdir,
      );
}
