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

const List<ApplicationDef> kApplicationCatalog = [
  ApplicationDef(
    key: 'dart',
    displayName: 'Dart',
    description: 'Compiles to a single native executable with '
        '`dart compile exe`. Fast startup, no runtime dependency on the host.',
    deployModes: [DeployMode.buildExecute],
    defaultDeployMode: DeployMode.buildExecute,
    defaultBuildCommand:
        'dart pub get && dart compile exe bin/server.dart -o build/app',
    versionHint: 'e.g. 3.4.4',
    docsUrl: 'https://dart.dev/',
  ),
  ApplicationDef(
    key: 'go',
    displayName: 'Go',
    description: 'Compiles to a single static binary with `go build`.',
    deployModes: [DeployMode.buildExecute],
    defaultDeployMode: DeployMode.buildExecute,
    defaultBuildCommand: 'go build -o build/app ./...',
    versionHint: 'e.g. 1.22.9',
    docsUrl: 'https://go.dev/',
  ),
  ApplicationDef(
    key: 'rust',
    displayName: 'Rust',
    description: 'Compiles a release binary with `cargo build --release`.',
    deployModes: [DeployMode.buildExecute],
    defaultDeployMode: DeployMode.buildExecute,
    defaultBuildCommand: 'cargo build --release',
    versionHint: 'e.g. stable | 1.81.0 | nightly',
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
    defaultBuildCommand: 'bun install',
    defaultStartCommand: 'bun run start',
    versionHint: 'e.g. 1.1.38',
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
    defaultBuildCommand: 'npm ci',
    defaultStartCommand: 'node dist/index.js',
    versionHint: 'e.g. 20.18.0 | 22.11.0',
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
    defaultBuildCommand:
        'python3 -m venv .venv && .venv/bin/pip install -r requirements.txt',
    versionHint: 'pyenv version string, e.g. 3.12.4',
    docsUrl: 'https://www.python.org/',
  ),
  ApplicationDef(
    key: 'celery',
    displayName: 'Celery',
    description: 'Python task queue workers (+ optional beat scheduler). '
        'Packaged the same way as Python, run as one or more worker units.',
    deployModes: [DeployMode.buildExecute],
    defaultDeployMode: DeployMode.buildExecute,
    versionHint: 'pyenv version string, e.g. 3.12.4',
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
