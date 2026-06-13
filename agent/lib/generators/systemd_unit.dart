/// Systemd .target that groups all Celery services for one app.
///
/// Lifecycle commands (`systemctl start gisila-<user>.target`) cascade to all
/// WantedBy / BindsTo members (workers, beat, flower).
class CeleryTarget {
  CeleryTarget({required this.linuxUser, required this.appId});

  final String linuxUser;
  final int appId;

  String get targetName => 'gisila-$linuxUser.target';

  String render() => '''
[Unit]
Description=Gisila Celery stack $linuxUser (id=$appId)
After=network.target
PartOf=gisila-apps.target

[Install]
WantedBy=gisila-apps.target
''';
}

/// A single Celery worker process unit.
class CeleryWorkerUnit {
  CeleryWorkerUnit({
    required this.appId,
    required this.linuxUser,
    required this.workDir,
    required this.celeryApp,
    required this.workerIndex,
    this.concurrency = 4,
    this.queues,
    this.extraArgs,
    this.memoryMb = 512,
    this.cpuQuotaPercent = 50,
    this.tasksMax = 512,
    this.envVars = const {},
  });

  final int appId;
  final String linuxUser;
  final String workDir;
  final String celeryApp;
  final int workerIndex;
  final int concurrency;
  final String? queues;
  final String? extraArgs;
  final int memoryMb;
  final int cpuQuotaPercent;
  final int tasksMax;
  final Map<String, String> envVars;

  String get serviceName => 'gisila-$linuxUser-worker-$workerIndex';

  String render() {
    final venv = '$workDir/current/.venv';
    final src = '$workDir/releases/current_build';
    final queuesArg =
        (queues != null && queues!.isNotEmpty) ? ' -Q $queues' : '';
    final extraArgsStr =
        (extraArgs != null && extraArgs!.isNotEmpty) ? ' ${extraArgs!.trim()}' : '';

    final envLines = StringBuffer();
    for (final entry in envVars.entries) {
      final escaped =
          entry.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      envLines.writeln('Environment=${entry.key}="$escaped"');
    }

    return '''
[Unit]
Description=Gisila Celery worker $workerIndex for $linuxUser (id=$appId)
After=network.target
PartOf=gisila-$linuxUser.target

[Service]
Type=simple
User=$linuxUser
Group=$linuxUser
WorkingDirectory=$src
ExecStart=$venv/bin/celery -A $celeryApp worker -n worker-$workerIndex@%h --loglevel=info -c $concurrency$queuesArg$extraArgsStr
Restart=always
RestartSec=10

Environment=GISILA_APP_ID=$appId
${envLines.toString().trimRight()}

# ── Sandboxing ─────────────────────────────────────────────────
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
ProtectProc=invisible
RestrictRealtime=true
RestrictNamespaces=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
LockPersonality=true
# MemoryDenyWriteExecute disabled for CPython (bytecode compilation)
SystemCallArchitectures=native

# Filesystem
ReadWritePaths=$workDir/shared $workDir/tmp $workDir/logs $workDir/releases/current_build $workDir/current/.venv
ReadOnlyPaths=$workDir/current $workDir/releases
PrivateMounts=true

# ── Resource limits (cgroups v2) ───────────────────────────────
MemoryMax=${memoryMb}M
CPUQuota=$cpuQuotaPercent%
TasksMax=$tasksMax
LimitNOFILE=4096

[Install]
WantedBy=gisila-$linuxUser.target
''';
  }
}

/// Celery beat scheduler unit.
class CeleryBeatUnit {
  CeleryBeatUnit({
    required this.appId,
    required this.linuxUser,
    required this.workDir,
    required this.celeryApp,
    this.memoryMb = 128,
    this.cpuQuotaPercent = 10,
    this.envVars = const {},
  });

  final int appId;
  final String linuxUser;
  final String workDir;
  final String celeryApp;
  final int memoryMb;
  final int cpuQuotaPercent;
  final Map<String, String> envVars;

  String get serviceName => 'gisila-$linuxUser-beat';

  String render() {
    final venv = '$workDir/current/.venv';
    final src = '$workDir/releases/current_build';
    final tmp = '$workDir/tmp';

    final envLines = StringBuffer();
    for (final entry in envVars.entries) {
      final escaped =
          entry.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      envLines.writeln('Environment=${entry.key}="$escaped"');
    }

    return '''
[Unit]
Description=Gisila Celery beat scheduler for $linuxUser (id=$appId)
After=network.target
PartOf=gisila-$linuxUser.target

[Service]
Type=simple
User=$linuxUser
Group=$linuxUser
WorkingDirectory=$src
ExecStart=$venv/bin/celery -A $celeryApp beat --loglevel=info --pidfile=$tmp/celerybeat.pid
Restart=always
RestartSec=10

Environment=GISILA_APP_ID=$appId
${envLines.toString().trimRight()}

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictNamespaces=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
LockPersonality=true
SystemCallArchitectures=native

ReadWritePaths=$workDir/shared $workDir/tmp $workDir/logs $workDir/releases/current_build $workDir/current/.venv
ReadOnlyPaths=$workDir/current $workDir/releases

MemoryMax=${memoryMb}M
CPUQuota=$cpuQuotaPercent%
TasksMax=64
LimitNOFILE=1024

[Install]
WantedBy=gisila-$linuxUser.target
''';
  }
}

/// Celery Flower monitoring UI unit.
///
/// Flower is always deployed alongside Celery workers. The nginx vhost
/// reverse-proxies the assigned [port] so Flower is accessible via the
/// app's domain without exposing the raw port.
class CeleryFlowerUnit {
  CeleryFlowerUnit({
    required this.appId,
    required this.linuxUser,
    required this.workDir,
    required this.celeryApp,
    required this.port,
    this.memoryMb = 128,
    this.cpuQuotaPercent = 10,
    this.envVars = const {},
  });

  final int appId;
  final String linuxUser;
  final String workDir;
  final String celeryApp;
  final int port;
  final int memoryMb;
  final int cpuQuotaPercent;
  final Map<String, String> envVars;

  String get serviceName => 'gisila-$linuxUser-flower';

  String render() {
    final venv = '$workDir/current/.venv';
    final src = '$workDir/releases/current_build';

    final envLines = StringBuffer();
    for (final entry in envVars.entries) {
      final escaped =
          entry.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      envLines.writeln('Environment=${entry.key}="$escaped"');
    }

    return '''
[Unit]
Description=Gisila Celery Flower UI for $linuxUser (id=$appId)
After=network.target
PartOf=gisila-$linuxUser.target

[Service]
Type=simple
User=$linuxUser
Group=$linuxUser
WorkingDirectory=$src
ExecStart=$venv/bin/celery -A $celeryApp flower --port=$port --address=127.0.0.1 --logging=info
Restart=always
RestartSec=5

Environment=PORT=$port
Environment=GISILA_APP_ID=$appId
${envLines.toString().trimRight()}

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictNamespaces=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
LockPersonality=true
SystemCallArchitectures=native

ReadWritePaths=$workDir/shared $workDir/tmp $workDir/logs $workDir/releases/current_build $workDir/current/.venv
ReadOnlyPaths=$workDir/current $workDir/releases

MemoryMax=${memoryMb}M
CPUQuota=$cpuQuotaPercent%
TasksMax=128
LimitNOFILE=4096

[Install]
WantedBy=gisila-$linuxUser.target
''';
  }
}

/// Generate a hardened systemd unit for a per-app service.
///
/// The output is intentionally close to what the gisila-panel docs prescribe
/// (`NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`, `MemoryMax`,
/// `CPUQuota`, `TasksMax`, `RestrictNamespaces`, …) and references the
/// matching AppArmor profile.
class SystemdUnit {
  SystemdUnit({
    required this.appId,
    required this.linuxUser,
    required this.workDir,
    required this.startCommand,
    required this.port,
    this.memoryMb = 256,
    this.cpuQuotaPercent = 50,
    this.tasksMax = 100,
    this.apparmorProfile,
    this.isPython = false,
    this.isJit = false,
    this.runtimeBinDir,
    this.workingDirectory,
    this.writableSource = false,
    this.envVars = const {},
  });

  final int appId;
  final String linuxUser;
  final String workDir;
  final String startCommand;
  final int port;
  final int memoryMb;
  final int cpuQuotaPercent;
  final int tasksMax;
  final String? apparmorProfile;
  final Map<String, String> envVars;

  /// When set (e.g. for Node.js or Bun deployments with a pinned version),
  /// this directory is prepended to the service's PATH so commands like
  /// `node` or `bun` in [startCommand] resolve to the correct version.
  final String? runtimeBinDir;

  /// When true, relax sandbox flags that break the CPython interpreter:
  ///   - `MemoryDenyWriteExecute` must be off (Python JIT / .pyc bytecode)
  ///   - The venv and source tree need write access for .pyc / __pycache__
  final bool isPython;

  /// Disable MemoryDenyWriteExecute for JIT runtimes (Node.js V8, Bun JavaScriptCore,
  /// CPython bytecode). Set by the caller when runtime == 'node' or 'bun'.
  final bool isJit;

  /// Explicit working directory for the service. When null it is derived from
  /// the runtime (Python/Node/Bun → the build source tree; compiled runtimes →
  /// `<workDir>/current`). Frameworks with a self-contained output (e.g. Next
  /// standalone) set this to the subdirectory holding their server.
  final String? workingDirectory;

  /// Grant the build source tree (`releases/current_build`) read-write access so
  /// server frameworks can write their runtime caches (e.g. Next's `.next/cache`,
  /// Nuxt/Nitro temp). Set for Node/Bun server apps.
  final bool writableSource;

  String render() {
    final src = '$workDir/releases/current_build';

    // Grant the source tree read-write when the runtime executes from it:
    //  - Python: venv (.dist-info stamps, script wrappers) + source (__pycache__).
    //  - Node/Bun servers: the build tree, so Next/Nuxt/etc. can write their
    //    runtime caches (.next/cache, .output, etc.). ReadWritePaths wins over
    //    the broader ReadOnlyPaths=$workDir/releases below (most-specific path).
    final rwPaths = <String>[
      if (isPython) '$workDir/current/.venv',
      if (isPython || writableSource) src,
    ];
    final extraRW = rwPaths.map((p) => ' $p').join();
    final mdwe = (isPython || isJit)
        ? '# MemoryDenyWriteExecute disabled (JIT runtime — Python/Node/Bun)'
        : 'MemoryDenyWriteExecute=true';

    // Working directory:
    //  - Explicit override (e.g. Next standalone's .next/standalone) wins.
    //  - Python (gunicorn/uvicorn) and Node/Bun run from the build source tree
    //    so package.json / node_modules / project packages resolve relative to
    //    cwd. The source is always at releases/current_build after a successful
    //    build; $workDir/current only holds the .venv symlink, the pinned
    //    runtime symlink, and compiled binaries for non-JIT runtimes.
    final workingDir = workingDirectory ??
        ((isPython || isJit) ? src : '$workDir/current');

    // Embed each user-defined env var as its own Environment= line.
    // Values are double-quoted; embedded double-quotes and backslashes are
    // escaped so systemd parses them correctly.
    final envLines = StringBuffer();
    for (final entry in envVars.entries) {
      final escaped =
          entry.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      envLines.writeln('Environment=${entry.key}="$escaped"');
    }

    // For Node.js / Bun apps pinned to a specific version, prepend the
    // versioned runtime's bin directory to PATH so `node` / `bun` in the
    // start command resolves to the right binary.
    final pathLine = runtimeBinDir != null
        ? 'Environment=PATH=$runtimeBinDir:/usr/local/bin:/usr/bin:/bin\n'
        : '';

    // Neutralise corepack in the running service, mirroring the same flags
    // applied during the build phase in builders.dart.
    //
    // Without these, corepack (which intercepts the system `pnpm` / `yarn` /
    // `npm` shims) tries to read/write its version cache from the service
    // user's home directory (~/.cache/node/corepack/lastKnownGood.json).
    // That fails with EACCES because the unit has ProtectHome=true, making
    // /home inaccessible to the sandboxed service.
    //
    //   COREPACK_HOME            → redirect the cache to the writable workDir
    //   COREPACK_ENABLE_STRICT   → fall back to system PM instead of erroring
    //                              when packageManager field doesn't match
    //   COREPACK_ENABLE_AUTO_PIN → do not mutate packageManager in package.json
    final corepkLines =
        'Environment=COREPACK_ENABLE_STRICT=0\n'
        'Environment=COREPACK_ENABLE_AUTO_PIN=0\n'
        'Environment=COREPACK_HOME=$workDir/.corepack\n';

    // Give pnpm/npm/yarn a writable HOME. The service runs as a system user
    // whose home (/home/<user>) was never created (useradd --no-create-home)
    // and is in any case blocked by ProtectHome=true, so pnpm's attempt to read
    // its global config ($HOME/.config/pnpm/config.yaml) fails with EACCES.
    // Redirect HOME — and the XDG base dirs derived from it (config / cache /
    // data / state) — into the app's writable tmp, which is already in
    // ReadWritePaths and the AppArmor profile. The tools then create and read
    // their config/cache there instead of in the inaccessible /home.
    final homeLines =
        'Environment=HOME=$workDir/tmp\n'
        'Environment=XDG_CONFIG_HOME=$workDir/tmp/.config\n'
        'Environment=XDG_CACHE_HOME=$workDir/tmp/.cache\n'
        'Environment=XDG_DATA_HOME=$workDir/tmp/.local/share\n'
        'Environment=XDG_STATE_HOME=$workDir/tmp/.local/state\n';

    return '''
[Unit]
Description=Gisila app $linuxUser (id=$appId)
After=network.target
PartOf=gisila-apps.target

[Service]
Type=simple
User=$linuxUser
Group=$linuxUser
WorkingDirectory=$workingDir
ExecStart=$startCommand
Restart=always
RestartSec=5

Environment=PORT=$port
Environment=GISILA_APP_ID=$appId
${pathLine}${corepkLines}${homeLines}${envLines.toString().trimRight()}

# ── Sandboxing ─────────────────────────────────────────────────
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
ProtectProc=invisible
RestrictRealtime=true
RestrictNamespaces=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
LockPersonality=true
$mdwe
SystemCallArchitectures=native

# Filesystem
ReadWritePaths=$workDir/shared $workDir/tmp $workDir/logs $workDir/.corepack$extraRW
ReadOnlyPaths=$workDir/current $workDir/releases
PrivateMounts=true

${apparmorProfile != null ? 'AppArmorProfile=$apparmorProfile\n' : ''}# ── Resource limits (cgroups v2) ───────────────────────────────
MemoryMax=${memoryMb}M
CPUQuota=$cpuQuotaPercent%
TasksMax=$tasksMax
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
''';
  }
}
