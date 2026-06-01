import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:gisila_orm/gisila.dart';
import 'package:logger/logger.dart';

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
