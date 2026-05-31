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
}

/// Singleton host config.
final hostConfig = HostConfig.fromEnv();
