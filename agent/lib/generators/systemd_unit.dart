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

  /// When true, relax sandbox flags that break the CPython interpreter:
  ///   - `MemoryDenyWriteExecute` must be off (Python JIT / .pyc bytecode)
  ///   - The venv and source tree need write access for .pyc / __pycache__
  final bool isPython;

  String render() {
    // Python needs write access to:
    //  - the venv for pip-created .dist-info stamps and script wrappers
    //  - the source tree so Python can write __pycache__ / .pyc files
    final extraRW = isPython
        ? ' $workDir/current/.venv $workDir/releases/current_build'
        : '';
    final mdwe = isPython
        ? '# MemoryDenyWriteExecute disabled for CPython (bytecode compilation)'
        : 'MemoryDenyWriteExecute=true';

    // Python apps (gunicorn/uvicorn) need the source tree as their working
    // directory so that the project's top-level packages (e.g. `core`, `blog`)
    // are on sys.path without requiring a PYTHONPATH override. The source is
    // always at releases/current_build after a successful build; $workDir/current
    // only holds the .venv symlink and compiled binaries for non-Python runtimes.
    final workingDir =
        isPython ? '$workDir/releases/current_build' : '$workDir/current';

    // Embed each user-defined env var as its own Environment= line.
    // Values are double-quoted; embedded double-quotes and backslashes are
    // escaped so systemd parses them correctly.
    final envLines = StringBuffer();
    for (final entry in envVars.entries) {
      final escaped =
          entry.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      envLines.writeln('Environment=${entry.key}="$escaped"');
    }

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
$mdwe
SystemCallArchitectures=native

# Filesystem
ReadWritePaths=$workDir/shared $workDir/tmp $workDir/logs$extraRW
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
