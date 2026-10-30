import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_redis/gisila_redis.dart' show GisilaRedis;
import 'package:logger/logger.dart';
import 'package:redis/redis.dart';

/// Global environment variables (platform env + `.env` file).
final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();

/// Application-wide structured logger.
///
/// The filter must be explicit: the package default (DevelopmentFilter) logs
/// only when asserts are on, i.e. never in the `dart compile exe` binaries
/// that run in production. `LOG_LEVEL` (trace/debug/info/warning/error)
/// picks the threshold.
final logger = Logger(
  filter: ProductionFilter(),
  level: Level.values.firstWhere(
    (l) => l.name == env['LOG_LEVEL']?.trim().toLowerCase(),
    orElse: () => Level.info,
  ),
  printer: PrettyPrinter(
    methodCount: 0,
    dateTimeFormat: (dt) => dt.toIso8601String(),
    // journald stores escape codes verbatim and splits boxes into four lines:
    // decorate only a real terminal.
    colors: stdout.hasTerminal && stdout.supportsAnsiEscapes,
    noBoxingByDefault: !stdout.hasTerminal,
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

/// ACL user for managed Redis providers; null authenticates as `default`.
String? get redisUsername =>
    (env['REDIS_USERNAME']?.isNotEmpty ?? false) ? env['REDIS_USERNAME'] : null;

/// Connect over TLS (set from a `rediss://` URL at install time).
bool get redisTls => const {'1', 'true', 'yes', 'on'}
    .contains(env['REDIS_TLS']?.trim().toLowerCase());

bool _warnedRedisNoAuth = false;

/// Open a new connection to the configured Redis instance, authenticating
/// with [redisPassword] (and [redisUsername]) first when set.
Future<Command> connectRedis() async {
  final conn = RedisConnection();
  final cmd = redisTls
      ? await conn.connectSecure(redisHost, redisPort)
      : await conn.connect(redisHost, redisPort);
  final password = redisPassword;
  if (password != null) {
    final user = redisUsername;
    await cmd.send_object(['AUTH', if (user != null) user, password]);
  } else if (!_warnedRedisNoAuth) {
    // Hosted apps share this machine, so an unauthenticated Redis lets any of
    // them read and enqueue panel jobs. The installer refuses this setup; warn
    // for hosts configured by hand.
    _warnedRedisNoAuth = true;
    logger.w('Redis has no REDIS_PASSWORD set: any app on this host can reach '
        'the panel job queues. Set requirepass and REDIS_PASSWORD.');
  }
  return cmd;
}

/// A self-healing client for the same Redis, with a timeout on every
/// command, for things on the request path (the shared rate limiter).
/// Unlike [connectRedis], a dropped connection is re-opened on the next
/// command.
GisilaRedis panelRedis() => GisilaRedis(
      host: redisHost,
      port: redisPort,
      username: redisUsername,
      password: redisPassword,
      tls: redisTls,
    );

/// Whether GisilaStudio (the raw database admin UI) is mounted at `/admin`.
///
/// Off unless `STUDIO_ENABLED` is truthy. The studio reads and edits every
/// table — env var values and SSH private keys included — behind its own
/// username/password rather than panel auth, so it is something an operator
/// opts into rather than a default part of every deployment.
bool get studioEnabled => const {'1', 'true', 'yes', 'on'}
    .contains(env['STUDIO_ENABLED']?.trim().toLowerCase());

/// The studio's login password, or null when it isn't safe to mount: unset,
/// or a well-known default. There is deliberately no fallback — the studio
/// can read every secret the panel holds.
String? get studioPassword {
  final value = env['STUDIO_PASSWORD']?.trim() ?? '';
  if (value.isEmpty || const {'admin', 'password', 'changeme'}.contains(value)) {
    return null;
  }
  return value;
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

/// The environment every agent invocation runs with — pass it together with
/// `includeParentEnvironment: false`.
///
/// The panel and worker load `/etc/gisila/.env` (JWT_SECRET, SUPERUSER_PASSWORD,
/// database and Redis credentials) into their own environment, and the root
/// agent hands its environment on to the processes it starts as app users —
/// builds and Console commands. Inheriting it would put the panel's secrets in
/// front of every tenant (`env` in the Console prints them), so the agent only
/// gets this allowlist: what it reads itself plus what the tools it drives
/// (git, apt, certbot, toolchains) need from a normal root shell.
final Map<String, String> agentEnvironment = {
  for (final key in const [
    'PATH',
    'HOME',
    'USER',
    'LOGNAME',
    'LANG',
    'LANGUAGE',
    'LC_ALL',
    'TZ',
    'TERM',
    'SUPERVISOR_CONF_DIR',
    // Where uploads and backups live, when moved from the defaults: the
    // agent checks paths it is given against these.
    'GISILA_ARTIFACT_DIR',
    'GISILA_BACKUP_DIR',
    'RUSTUP_HOME',
    'CARGO_HOME',
    'PUB_CACHE',
    'SSL_CERT_FILE',
    'SSL_CERT_DIR',
    'http_proxy',
    'https_proxy',
    'no_proxy',
    'HTTP_PROXY',
    'HTTPS_PROXY',
    'NO_PROXY',
  ])
    if (Platform.environment[key] case final value?) key: value,
  if (hostConfig.dockerDeploy) 'DOCKER_DEPLOY': 'true',
};

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
