import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

/// A pre-built executable artifact is dropped in place by
/// `gisila-agent build --source-type binary` (see `Builders.binaryArtifact`,
/// invoked before the runtime dispatch). There is nothing further to build.
class BinaryPlugin extends RuntimePlugin {
  @override
  String get key => 'binary';

  @override
  List<DeployMode> get supportedModes => const [DeployMode.directRun];

  @override
  Future<void> installToolchain({String? version}) async {}

  @override
  Future<void> removeToolchain({String? version}) async {}

  @override
  Future<void> build(RuntimeBuildContext ctx) async {}
}
