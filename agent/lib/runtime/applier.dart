import 'dart:io';

import 'package:gisila_agent/generators/apparmor_profile.dart';
import 'package:gisila_agent/generators/nginx_vhost.dart';
import 'package:gisila_agent/generators/supervisor_conf.dart';
import 'package:gisila_agent/generators/systemd_unit.dart';
import 'package:gisila_agent/runtime/exec.dart';

/// Writes the generated process-manager / nginx / apparmor artifacts to disk
/// and reloads the relevant subsystems.
///
/// When [isDocker] is true (env var DOCKER_DEPLOY=true) the agent runs inside
/// a privileged container. In that mode:
///   - supervisord replaces systemd  (configs in [supervisorConfDir])
///   - nginx is reloaded via `nginx -s reload` (no systemctl)
///   - AppArmor is skipped entirely
class Applier {
  Applier({
    String? systemdDir,
    String? apparmorDir,
    String? nginxDir,
    String? supervisorConfDir,
  })  : isDocker = Platform.environment['DOCKER_DEPLOY'] == 'true',
        systemdDir = systemdDir ?? '/etc/systemd/system',
        apparmorDir = apparmorDir ?? '/etc/apparmor.d',
        nginxDir = nginxDir ??
            (Platform.environment['DOCKER_DEPLOY'] == 'true'
                ? '/etc/nginx/conf.d'
                : '/etc/nginx/sites-enabled'),
        supervisorConfDir = supervisorConfDir ??
            Platform.environment['SUPERVISOR_CONF_DIR'] ??
            '/etc/supervisor/conf.d';

  final bool isDocker;
  final String systemdDir;
  final String apparmorDir;
  final String nginxDir;
  final String supervisorConfDir;

  Future<void> applyUnit({
    required int appId,
    required String linuxUser,
    required String workDir,
    required String startCommand,
    required int port,
    required int memoryMb,
    required int cpuQuotaPercent,
    required int tasksMax,
    bool isPython = false,
    Map<String, String> envVars = const {},
  }) async {
    if (isDocker) {
      await _applyUnitDocker(
        appId: appId,
        linuxUser: linuxUser,
        workDir: workDir,
        startCommand: startCommand,
        port: port,
        envVars: envVars,
      );
    } else {
      await _applyUnitSystemd(
        appId: appId,
        linuxUser: linuxUser,
        workDir: workDir,
        startCommand: startCommand,
        port: port,
        memoryMb: memoryMb,
        cpuQuotaPercent: cpuQuotaPercent,
        tasksMax: tasksMax,
        isPython: isPython,
        envVars: envVars,
      );
    }
  }

  Future<void> _applyUnitDocker({
    required int appId,
    required String linuxUser,
    required String workDir,
    required String startCommand,
    required int port,
    Map<String, String> envVars = const {},
  }) async {
    final conf = SupervisorConf(
      appId: appId,
      linuxUser: linuxUser,
      workDir: workDir,
      startCommand: startCommand,
      port: port,
      envVars: envVars,
    );
    Directory(supervisorConfDir).createSync(recursive: true);
    File('$supervisorConfDir/${conf.programName}.conf')
        .writeAsStringSync(conf.render());
    // Tell supervisord to pick up the new config.
    await ShellExec.run('supervisorctl', ['update'], requireSuccess: false);
  }

  Future<void> _applyUnitSystemd({
    required int appId,
    required String linuxUser,
    required String workDir,
    required String startCommand,
    required int port,
    required int memoryMb,
    required int cpuQuotaPercent,
    required int tasksMax,
    required bool isPython,
    Map<String, String> envVars = const {},
  }) async {
    final profile = ApparmorProfile(linuxUser: linuxUser, workDir: workDir);
    final apparmorPath = '$apparmorDir/gisila-$linuxUser';
    File(apparmorPath).writeAsStringSync(profile.render());
    await ShellExec.run('apparmor_parser', ['-r', apparmorPath],
        requireSuccess: false);

    final unit = SystemdUnit(
      appId: appId,
      linuxUser: linuxUser,
      workDir: workDir,
      startCommand: startCommand,
      port: port,
      memoryMb: memoryMb,
      cpuQuotaPercent: cpuQuotaPercent,
      tasksMax: tasksMax,
      apparmorProfile: profile.profileName,
      isPython: isPython,
      envVars: envVars,
    );
    final unitPath = '$systemdDir/gisila-$linuxUser.service';
    File(unitPath).writeAsStringSync(unit.render());
    await ShellExec.run('systemctl', ['daemon-reload']);
    await ShellExec.run('systemctl', ['enable', 'gisila-$linuxUser.service']);
  }

  Future<void> applyVhost({
    required int appId,
    required int port,
    required List<String> hostnames,
  }) async {
    final vhost =
        NginxVhost(appId: appId, port: port, hostnames: hostnames).render();
    Directory(nginxDir).createSync(recursive: true);
    File('$nginxDir/gisila-app-$appId.conf').writeAsStringSync(vhost);
    await ShellExec.run('nginx', ['-t'], requireSuccess: false);
    if (isDocker) {
      await ShellExec.run('nginx', ['-s', 'reload'], requireSuccess: false);
    } else {
      await ShellExec.run('systemctl', ['reload', 'nginx'],
          requireSuccess: false);
    }
  }

  Future<void> issueCert(String hostname) async {
    await ShellExec.run('certbot', [
      'certonly',
      '--nginx',
      '--non-interactive',
      '--agree-tos',
      '-m',
      'admin@$hostname',
      '-d',
      hostname,
    ]);
    if (isDocker) {
      await ShellExec.run('nginx', ['-s', 'reload'], requireSuccess: false);
    } else {
      await ShellExec.run('systemctl', ['reload', 'nginx'],
          requireSuccess: false);
    }
  }

  Future<void> start(String linuxUser) => isDocker
      ? ShellExec.run('supervisorctl', ['start', 'gisila-$linuxUser'],
          requireSuccess: false)
      : ShellExec.run('systemctl', ['start', 'gisila-$linuxUser.service']);

  Future<void> stop(String linuxUser) => isDocker
      ? ShellExec.run('supervisorctl', ['stop', 'gisila-$linuxUser'],
          requireSuccess: false)
      : ShellExec.run('systemctl', ['stop', 'gisila-$linuxUser.service']);

  Future<void> restart(String linuxUser) => isDocker
      ? ShellExec.run('supervisorctl', ['restart', 'gisila-$linuxUser'],
          requireSuccess: false)
      : ShellExec.run('systemctl', ['restart', 'gisila-$linuxUser.service']);

  Future<void> uninstall(String linuxUser, int? appId) async {
    if (isDocker) {
      await ShellExec.run('supervisorctl', ['stop', 'gisila-$linuxUser'],
          requireSuccess: false);
      final conf = '$supervisorConfDir/gisila-$linuxUser.conf';
      if (File(conf).existsSync()) File(conf).deleteSync();
      await ShellExec.run('supervisorctl', ['update'], requireSuccess: false);
    } else {
      await ShellExec.run('systemctl', ['stop', 'gisila-$linuxUser.service'],
          requireSuccess: false);
      await ShellExec.run('systemctl', ['disable', 'gisila-$linuxUser.service'],
          requireSuccess: false);
      final unitPath = '$systemdDir/gisila-$linuxUser.service';
      if (File(unitPath).existsSync()) File(unitPath).deleteSync();
      final apparmorPath = '$apparmorDir/gisila-$linuxUser';
      if (File(apparmorPath).existsSync()) File(apparmorPath).deleteSync();
      await ShellExec.run('systemctl', ['daemon-reload'],
          requireSuccess: false);
    }
    if (appId != null) {
      final vhost = '$nginxDir/gisila-app-$appId.conf';
      if (File(vhost).existsSync()) File(vhost).deleteSync();
      if (isDocker) {
        await ShellExec.run('nginx', ['-s', 'reload'], requireSuccess: false);
      } else {
        await ShellExec.run('systemctl', ['reload', 'nginx'],
            requireSuccess: false);
      }
    }
  }
}
