import 'package:gisila_agent/runtime/deploy_mode.dart';

/// Everything a [RuntimePlugin] needs to fetch-and-build (or prepare) an app.
///
/// The source tree has already been fetched into
/// `<workDir>/releases/current_build/` (git/zip/binary — that step is
/// runtime-agnostic and stays in `gisila-agent build`) by the time a plugin's
/// [RuntimePlugin.build] runs.
class RuntimeBuildContext {
  const RuntimeBuildContext({
    required this.workDir,
    required this.user,
    this.buildCommand,
    this.version,
    this.appEnv,
    this.noCache = false,
    this.sourceSubdir,
    this.deployMode,
  });

  final String workDir;
  final String user;

  /// Override for the Application's default build/prepare command.
  final String? buildCommand;

  /// Version pin (pyenv/fnm/Dart-SDK/Go/Bun version, rustup toolchain, …).
  final String? version;

  final Map<String, String>? appEnv;
  final bool noCache;
  final String? sourceSubdir;

  /// The App's chosen mode, when the Application supports more than one.
  final DeployMode? deployMode;
}

/// A self-contained runtime/language stack implementation.
///
/// Each plugin owns everything needed to (a) install/remove its toolchain on
/// a host independently of any specific app deployment (the "Application
/// Management" lifecycle — install/update/remove from the panel) and (b)
/// build/prepare an app of its kind during a deployment. Adding a new
/// runtime means adding one new plugin + registering it in
/// [RuntimeRegistry] — no existing plugin or the agent's orchestration code
/// needs to change.
abstract class RuntimePlugin {
  /// Stable identifier — matches `Application.key` on the panel.
  String get key;

  /// Deployment mechanisms this plugin supports (see [DeployMode]).
  List<DeployMode> get supportedModes;

  /// Install (or update, when called again with a new [version]) this
  /// runtime's toolchain on the host. Idempotent.
  Future<void> installToolchain({String? version});

  /// Remove this runtime's toolchain from the host (or just the pinned
  /// [version], when given). Idempotent; safe to call when nothing is
  /// installed.
  Future<void> removeToolchain({String? version});

  /// Fetch dependencies and, for [DeployMode.buildExecute], compile/package
  /// the app. For [DeployMode.directRun] this only prepares the source
  /// in-place (installs dependencies) — no compile step.
  Future<void> build(RuntimeBuildContext ctx);
}
