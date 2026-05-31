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

  /// When true, relax sandbox flags that break the CPython interpreter:
  ///   - `MemoryDenyWriteExecute` must be off (Python JIT / .pyc bytecode)
  ///   - The venv directory needs write access so gunicorn can create .pyc files
  final bool isPython;

  String render() {
    final extraRW = isPython ? ' $workDir/current/.venv' : '';
    final mdwe = isPython
        ? '# MemoryDenyWriteExecute disabled for CPython (bytecode compilation)'
        : 'MemoryDenyWriteExecute=true';

    return '''
[Unit]
Description=Gisila app $linuxUser (id=$appId)
After=network.target
PartOf=gisila-apps.target

[Service]
Type=simple
User=$linuxUser
Group=$linuxUser
WorkingDirectory=$workDir/current
ExecStart=$startCommand
Restart=always
RestartSec=5

EnvironmentFile=$workDir/.env
Environment=PORT=$port
Environment=GISILA_APP_ID=$appId

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
