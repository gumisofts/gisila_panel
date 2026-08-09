import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

class DartPlugin extends RuntimePlugin {
  @override
  String get key => 'dart';

  @override
  List<DeployMode> get supportedModes => const [DeployMode.buildExecute];

  @override
  bool get versioned => true;

  @override
  Future<void> installToolchain({String? version}) async {
    if (version == null || version.isEmpty) {
      // Returning quietly here used to mark the Application installed in the
      // panel while nothing had been put on disk.
      throw ArgumentError('dart requires --version, e.g. --version 3.12.2');
    }
    await Builders.installDartToolchain(version);
  }

  @override
  Future<void> removeToolchain({String? version}) =>
      Builders.removeDartToolchain(version: version);

  @override
  Future<List<String>> installedVersions() async => Builders.listDartVersions();

  @override
  Future<void> build(RuntimeBuildContext ctx) => Builders.buildDart(
        workDir: ctx.workDir,
        user: ctx.user,
        buildCommand: ctx.buildCommand,
        dartVersion: ctx.version,
        sourceSubdir: ctx.sourceSubdir,
      );
}
