import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:gisila_orm/gisila.dart';
import 'package:logger/logger.dart';
import 'package:redis/redis.dart';

/// Global environment variables (platform env + `.env` file).
final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();

/// Application-wide structured logger.
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    dateTimeFormat: (dt) => dt.toIso8601String(),
  ),
);

/// Resolved database config (populated by [init]).
late DatabaseConfig databaseConfig;

/// Initialise app globals before the server starts.
/// Called once per isolate.
///
/// The database config is resolved in this order:
///   1. `GISILA_DATABASE_FILE` env var, if set.
///   2. `/etc/gisila/database.yaml` (installed by `infra/install.sh`).
///   3. `./database.yaml` (the dev default).
Future<void> init() async {
  final candidates = <String>[
    if (env['GISILA_DATABASE_FILE']?.isNotEmpty ?? false)
      env['GISILA_DATABASE_FILE']!,
    '/etc/gisila/database.yaml',
    'database.yaml',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) {
      databaseConfig = await DatabaseConfig.fromFile(path);
      return;
    }
  }
  databaseConfig = await DatabaseConfig.fromFile('database.yaml');
}

// ── System PostgreSQL ─────────────────────────────────────────────────────────
//
// The panel runs on its own PostgreSQL cluster — the one configured in
// database.yaml. That cluster is always available (gisila_panel depends on it),
// so the Databases panel surfaces it automatically as a read-only "system"
// instance instead of asking the operator to install or point at it.
//
// Connection details come straight from [databaseConfig]; the major version is
// read from config (the `server_version` key under the default connection's
// `additional_params`) rather than requested in the UI.
//
// That cluster does not have to be on this host. Unlike the instances the panel
// installs — which the agent creates locally and can drive through systemd and
// a local socket — the system cluster can be a machine on the LAN or a managed
// provider, in which case the panel is only its client. Everything that
// connects to it, or asks the agent to act on it, has to respect that; see
// `instanceHost` / `isLocalInstance` in services/postgres_service.dart.

/// Host of the system PostgreSQL cluster that backs the panel. Read-only.
String get systemPgHost => databaseConfig.defaultConnection.host;

/// Port of the system PostgreSQL cluster that backs the panel. Read-only.
int get systemPgPort => databaseConfig.defaultConnection.port;

/// Database name the panel itself uses on the system cluster.
String get systemPgDatabase => databaseConfig.defaultConnection.database;

/// Credentials the panel authenticates to the system cluster with.
///
/// Used to read stats from a *remote* system cluster, where the agent cannot
/// provision the usual read-only `gisila_monitor` role because it has no way
/// to reach that host. These credentials are known to work — the panel is
/// already connected with them.
String get systemPgUser => databaseConfig.defaultConnection.username;
String get systemPgPassword => databaseConfig.defaultConnection.password;
bool get systemPgUseSsl => databaseConfig.defaultConnection.useSSL;

/// Major version of the system PostgreSQL cluster, read from config
/// (`additional_params.server_version` in database.yaml). Returns null when it
/// is not configured — in which case the system instance is not surfaced.
int? get systemPgVersion {
  final v = databaseConfig.defaultConnection.additionalParams['server_version'];
  final parsed = v is int ? v : (v is String ? int.tryParse(v) : null);
  // Treat a missing or non-positive value (e.g. failed install-time detection)
  // as "not configured" so we never seed a bogus instance.
  return (parsed != null && parsed > 0) ? parsed : null;
}

// ── External Redis ────────────────────────────────────────────────────────────
//
// Redis is not installed or managed by this panel (see infra/install.sh) — it
// is expected to already exist, with connection details supplied via env vars
// in /etc/gisila/.env. `connectRedis()` is the single place that resolves
// those vars and authenticates, so every call site (API, worker, log bridge)
// stays in sync if the auth story changes.

String get redisHost => env.getOrElse('REDIS_HOST', () => 'localhost');
int get redisPort => int.parse(env.getOrElse('REDIS_PORT', () => '6380'));
String? get redisPassword =>
    (env['REDIS_PASSWORD']?.isNotEmpty ?? false) ? env['REDIS_PASSWORD'] : null;

/// Open a new connection to the configured Redis instance, authenticating
/// with [redisPassword] first when one is set.
Future<Command> connectRedis() async {
  final cmd = await RedisConnection().connect(redisHost, redisPort);
  final password = redisPassword;
  if (password != null) {
    await cmd.send_object(['AUTH', password]);
  }
  return cmd;
}

/// Host paths and runtime knobs that the worker / agent need.
class HostConfig {
  HostConfig({
    required this.appsRoot,
    required this.nginxSitesDir,
    required this.systemdUnitsDir,
    required this.apparmorProfilesDir,
    required this.portMin,
    required this.portMax,
    required this.agentMode,
    required this.agentBin,
    required this.agentDartEntry,
    required this.nodeId,
    required this.dockerDeploy,
  });

  factory HostConfig.fromEnv() => HostConfig(
        appsRoot: env.getOrElse('APPS_ROOT', () => '/srv/apps'),
        nginxSitesDir:
            env.getOrElse('NGINX_SITES_DIR', () => '/etc/nginx/sites-enabled'),
        systemdUnitsDir:
            env.getOrElse('SYSTEMD_UNITS_DIR', () => '/etc/systemd/system'),
        apparmorProfilesDir:
            env.getOrElse('APPARMOR_PROFILES_DIR', () => '/etc/apparmor.d'),
        portMin: int.parse(env.getOrElse('APP_PORT_RANGE_MIN', () => '4000')),
        portMax: int.parse(env.getOrElse('APP_PORT_RANGE_MAX', () => '4999')),
        agentMode: env.getOrElse('AGENT_MODE', () => 'sudo'),
        agentBin:
            env.getOrElse('AGENT_BIN', () => '/usr/local/bin/gisila-agent'),
        // Path to gisila-agent.dart, used when AGENT_BIN=dart (Docker mode).
        agentDartEntry: env.getOrElse(
          'AGENT_DART_ENTRY',
          () => '/workspace/gisila-panel/agent/bin/gisila-agent.dart',
        ),
        nodeId: env.getOrElse('NODE_ID', () => 'local'),
        // true when running inside Docker (set DOCKER_DEPLOY=true in the
        // container env). Prevents the worker from prepending `sudo` to the
        // agent command: Docker containers already run as root, and the kernel's
        // no_new_privileges flag blocks sudo even when AGENT_MODE=sudo.
        dockerDeploy: Platform.environment['DOCKER_DEPLOY'] == 'true' ||
            env['DOCKER_DEPLOY'] == 'true',
      );

  final String appsRoot;
  final String nginxSitesDir;
  final String systemdUnitsDir;
  final String apparmorProfilesDir;
  final int portMin;
  final int portMax;
  final String agentMode;
  final String agentBin;

  /// When [agentBin] is `dart`, the worker passes `run <agentDartEntry>` so
  /// the agent script is invoked without a pre-compiled binary.
  final String agentDartEntry;

  final String nodeId;

  /// True when running inside a Docker container (DOCKER_DEPLOY=true).
  final bool dockerDeploy;
}

/// Singleton host config.
final hostConfig = HostConfig.fromEnv();

/// Build the OS command used by every worker to invoke the agent.
///
/// Priority:
///   1. `AGENT_BIN=dart`             → `dart run <entry> <args>`
///   2. `DOCKER_DEPLOY=true`         → `<bin> <args>` (container is already root,
///                                      sudo would be blocked by no_new_privileges)
///   3. `AGENT_MODE=sudo`            → `sudo --non-interactive <bin> <args>`
///   4. anything else                → `<bin> <args>`
List<String> buildAgentCmd(List<String> args) {
  if (hostConfig.agentBin == 'dart') {
    return ['dart', 'run', hostConfig.agentDartEntry, ...args];
  }
  if (hostConfig.dockerDeploy || hostConfig.agentMode != 'sudo') {
    return [hostConfig.agentBin, ...args];
  }
  return ['sudo', '--non-interactive', hostConfig.agentBin, ...args];
}

/// Like [buildAgentCmd] but never uses sudo.
///
/// Used by the API server's runtime-log streaming. The API runs as the
/// unprivileged `gisila` user with systemd `NoNewPrivileges=true`, so it can
/// never invoke sudo regardless of `AGENT_MODE`. The agent's `logs` command
/// only needs to read journald, which works when `gisila` is a member of the
/// `systemd-journal` group (set up by infra/install.sh).
List<String> buildAgentCmdNoSudo(List<String> args) {
  if (hostConfig.agentBin == 'dart') {
    return ['dart', 'run', hostConfig.agentDartEntry, ...args];
  }
  return [hostConfig.agentBin, ...args];
}
