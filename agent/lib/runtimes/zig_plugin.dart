import 'package:gisila_agent/runtime/deploy_mode.dart';
import 'package:gisila_agent/runtime/runtime_plugin.dart';

/// Zig has no dedicated toolchain manager or build step today — build/start
/// are entirely as specified by the app's own commands (preserves the
/// pre-refactor behaviour of the `case 'zig':` no-op in the build switch).
class ZigPlugin extends RuntimePlugin {
  @override
  String get key => 'zig';

  @override
  List<DeployMode> get supportedModes => const [DeployMode.buildExecute];

  @override
  Future<void> installToolchain({String? version}) async {}

  @override
  Future<void> removeToolchain({String? version}) async {}

  @override
  Future<void> build(RuntimeBuildContext ctx) async {}
}
