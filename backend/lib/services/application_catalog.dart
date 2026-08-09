/// Static catalog of the builtin Applications (runtime/language stacks) the
/// panel ships with. Applications are the deployment targets users pick when
/// creating an App — see [ApplicationService] for the installed-state CRUD
/// and [Application] (generated model) for the DB-backed installed row.
///
/// Each [ApplicationDef] mirrors the shape of [ServiceDef] in `catalog.dart`:
/// display metadata plus the deployment defaults seeded onto the
/// [Application] row when installed. Adding a brand-new Application means
/// adding an entry here (plus a matching agent-side `RuntimePlugin`) — it does
/// not require changing anything about how *existing* Applications or Apps
/// are deployed.
library gisila_panel.services.application_catalog;

/// A deployment mechanism an Application can support.
///
/// - [buildExecute]: the app is compiled/packaged first, then the built
///   artifact is executed (e.g. Dart, Go, Rust, a bundled Node app).
/// - [directRun]: the app is executed directly with no compile step — an
///   interpreter runs the source in place, or a pre-built binary is dropped
///   in as-is (e.g. Python, a `binary` artifact).
/// - [staticPublish]: no process is run at all; files are published for nginx
///   to serve directly (static sites).
enum DeployMode {
  buildExecute('build_execute'),
  directRun('direct_run'),
  staticPublish('static_publish');

  const DeployMode(this.value);
  final String value;

  static DeployMode fromValue(String raw) =>
      DeployMode.values.firstWhere((m) => m.value == raw);

  static List<DeployMode> parseCsv(String raw) => raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map(DeployMode.fromValue)
      .toList();

  static String toCsv(List<DeployMode> modes) =>
      modes.map((m) => m.value).join(',');
}

class ApplicationDef {
  const ApplicationDef({
    required this.key,
    required this.displayName,
    required this.description,
    required this.deployModes,
    required this.defaultDeployMode,
    this.versioned = false,
    this.availableVersions = const <String>[],
    this.defaultVersion,
    this.defaultBuildCommand,
    this.defaultStartCommand,
    this.versionHint,
    this.docsUrl,
  });

  /// Stable machine identifier — stored in [Application.key] and (for
  /// backward compatibility) mirrored onto `App.runtime`.
  final String key;
  final String displayName;
  final String description;

  /// Deployment mechanisms this Application supports.
  final List<DeployMode> deployModes;

  /// Which of [deployModes] new Apps get unless the admin/user overrides it.
  final DeployMode defaultDeployMode;

  /// Whether several versions of this Application can be installed side by
  /// side. True where a version manager (pyenv, fnm, rustup) or per-version
  /// install prefix makes that possible; false for stacks that either have no
  /// toolchain to install at all (static, binary) or borrow another's
  /// (celery runs on whichever Python its app pins).
  ///
  /// Versioned Applications keep one [ApplicationVersion] row per installed
  /// version; unversioned ones are tracked by the [Application] row alone.
  final bool versioned;

  /// Curated list of installable versions, newest first. Offered in the
  /// install dialog and the new-app wizard so both read the same list.
  ///
  /// Deliberately static: resolving live from `pyenv install --list` and
  /// friends would mean a network round trip through the agent on every page
  /// load, and these only need refreshing when a new release lands.
  final List<String> availableVersions;

  final String? defaultVersion;
  final String? defaultBuildCommand;
  final String? defaultStartCommand;

  /// Freeform hint shown next to the version field, e.g. "pyenv version
  /// string, e.g. 3.12.4".
  final String? versionHint;
  final String? docsUrl;

  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'displayName': displayName,
        'description': description,
        'deployModes': deployModes.map((m) => m.value).toList(),
        'defaultDeployMode': defaultDeployMode.value,
        'versioned': versioned,
        'availableVersions': availableVersions,
        if (defaultVersion != null) 'defaultVersion': defaultVersion,
        if (defaultBuildCommand != null)
          'defaultBuildCommand': defaultBuildCommand,
        if (defaultStartCommand != null)
          'defaultStartCommand': defaultStartCommand,
        if (versionHint != null) 'versionHint': versionHint,
        if (docsUrl != null) 'docsUrl': docsUrl,
      };
}

// ─────────────────────────── Catalog entries ─────────────────────────────────

/// CPython releases installable through pyenv, newest first.
const List<String> _kPythonVersions = [
  '3.14.7', '3.14.0', //
  '3.13.15', '3.13.5', '3.13.2', //
  '3.12.13', '3.12.9', '3.12.8', //
  '3.11.15', '3.11.11', //
  '3.10.20', '3.10.16', //
];

/// Node releases installable through fnm. Active LTS first, then older LTS
/// lines, the current line, and finally releases kept only for legacy apps.
const List<String> _kNodeVersions = [
  '24.19.0', '24.18.1', '24.16.0', // LTS "Krypton"
  '22.23.2', '22.22.3', '22.20.0', // LTS "Jod"
  '20.20.2', '20.19.6', // LTS "Iron" (EOL upstream)
  '26.7.0', '26.5.1', // current line — shorter support window
  '18.20.8', // EOL upstream, kept for older apps
];

const List<String> _kDartVersions = [
  '3.12.2', '3.12.1', '3.12.0', //
  '3.11.6', '3.11.4', '3.11.0', //
  '3.10.9', '3.10.4', '3.10.0', //
  '3.9.4', '3.8.3', '3.7.3', '3.6.2', //
  '3.5.4', '3.5.3', '3.4.4', '3.3.4', // legacy apps
];

const List<String> _kGoVersions = [
  '1.26.5', '1.26.4', '1.26.0', //
  '1.25.12', '1.25.11', '1.25.0', //
  '1.24.13', '1.23.12', //
];

/// rustup toolchains — the rolling channel names are versions in their own
/// right here, and install side by side with the pinned releases.
const List<String> _kRustVersions = [
  'stable', '1.97.1', '1.96.1', '1.95.0', '1.94.1', '1.93.1', 'nightly', //
];

const List<String> _kBunVersions = [
  '1.3.14', '1.3.13', '1.3.12', '1.3.10', //
  '1.2.23', '1.2.19', //
  '1.1.38', // legacy apps
];

const List<ApplicationDef> kApplicationCatalog = [
  ApplicationDef(
    key: 'dart',
    displayName: 'Dart',
    description: 'Compiles to a single native executable with '
        '`dart compile exe`. Fast startup, no runtime dependency on the host.',
    deployModes: [DeployMode.buildExecute],
    defaultDeployMode: DeployMode.buildExecute,
    versioned: true,
    availableVersions: _kDartVersions,
    defaultVersion: '3.12.2',
    defaultBuildCommand:
        'dart pub get && dart compile exe bin/server.dart -o build/app',
    versionHint: 'e.g. 3.12.2',
    docsUrl: 'https://dart.dev/',
  ),
  ApplicationDef(
    key: 'go',
    displayName: 'Go',
    description: 'Compiles to a single static binary with `go build`.',
    deployModes: [DeployMode.buildExecute],
    defaultDeployMode: DeployMode.buildExecute,
    versioned: true,
    availableVersions: _kGoVersions,
    defaultVersion: '1.26.5',
    defaultBuildCommand: 'go build -o build/app ./...',
    versionHint: 'e.g. 1.26.5',
    docsUrl: 'https://go.dev/',
  ),
  ApplicationDef(
    key: 'rust',
    displayName: 'Rust',
    description: 'Compiles a release binary with `cargo build --release`.',
    deployModes: [DeployMode.buildExecute],
    defaultDeployMode: DeployMode.buildExecute,
    versioned: true,
    availableVersions: _kRustVersions,
    defaultVersion: 'stable',
    defaultBuildCommand: 'cargo build --release',
    versionHint: 'e.g. stable | 1.97.1 | nightly',
    docsUrl: 'https://www.rust-lang.org/',
  ),
  ApplicationDef(
    key: 'zig',
    displayName: 'Zig',
    description: 'Compiled as specified by the app\'s own build/start '
        'commands.',
    deployModes: [DeployMode.buildExecute],
    defaultDeployMode: DeployMode.buildExecute,
    docsUrl: 'https://ziglang.org/',
  ),
  ApplicationDef(
    key: 'bun',
    displayName: 'Bun',
    description: 'Fast JS/TS runtime and package manager. Supports either a '
        'build step (bundling/transpiling) or running the source directly.',
    deployModes: [DeployMode.buildExecute, DeployMode.directRun],
    defaultDeployMode: DeployMode.buildExecute,
    versioned: true,
    availableVersions: _kBunVersions,
    defaultVersion: '1.3.14',
    defaultBuildCommand: 'bun install',
    defaultStartCommand: 'bun run start',
    versionHint: 'e.g. 1.3.14',
    docsUrl: 'https://bun.sh/',
  ),
  ApplicationDef(
    key: 'node',
    displayName: 'Node.js',
    description: 'npm/pnpm-based apps. Supports either a build step '
        '(TypeScript, bundlers, framework builds) or running the source '
        'directly for plain JS apps.',
    deployModes: [DeployMode.buildExecute, DeployMode.directRun],
    defaultDeployMode: DeployMode.buildExecute,
    versioned: true,
    availableVersions: _kNodeVersions,
    defaultVersion: '24.19.0',
    defaultBuildCommand: 'npm ci',
    defaultStartCommand: 'node dist/index.js',
    versionHint: 'e.g. 24.19.0 | 22.23.2',
    docsUrl: 'https://nodejs.org/',
  ),
  ApplicationDef(
    key: 'python',
    displayName: 'Python',
    description: 'Interpreted — dependencies are installed into a venv, then '
        'the interpreter runs the source directly (via gunicorn/uvicorn). '
        'No compile step.',
    deployModes: [DeployMode.directRun],
    defaultDeployMode: DeployMode.directRun,
    versioned: true,
    availableVersions: _kPythonVersions,
    defaultVersion: '3.13.15',
    defaultBuildCommand:
        'python3 -m venv .venv && .venv/bin/pip install -r requirements.txt',
    versionHint: 'pyenv version string, e.g. 3.13.15',
    docsUrl: 'https://www.python.org/',
  ),
  ApplicationDef(
    key: 'celery',
    displayName: 'Celery',
    description: 'Python task queue workers (+ optional beat scheduler). '
        'Packaged the same way as Python, run as one or more worker units.',
    deployModes: [DeployMode.buildExecute],
    defaultDeployMode: DeployMode.buildExecute,
    versionHint: 'pyenv version string, e.g. 3.13.15',
    docsUrl: 'https://docs.celeryq.dev/',
  ),
  ApplicationDef(
    key: 'static',
    displayName: 'Static Site',
    description: 'Publishes files (optionally produced by a Node build) '
        'directly via nginx. No process is run.',
    deployModes: [DeployMode.staticPublish],
    defaultDeployMode: DeployMode.staticPublish,
  ),
  ApplicationDef(
    key: 'binary',
    displayName: 'Binary',
    description: 'A pre-built executable artifact is dropped in place and '
        'executed as-is — no build step.',
    deployModes: [DeployMode.directRun],
    defaultDeployMode: DeployMode.directRun,
  ),
];

/// Look up a catalog definition by key, or null if unknown.
ApplicationDef? findApplicationDef(String key) {
  for (final def in kApplicationCatalog) {
    if (def.key == key) return def;
  }
  return null;
}
