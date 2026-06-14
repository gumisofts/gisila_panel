import 'dart:io';

import 'package:gisila_agent/generators/apparmor_profile.dart';
import 'package:gisila_agent/generators/nginx_vhost.dart';
import 'package:gisila_agent/generators/supervisor_conf.dart';
import 'package:gisila_agent/generators/systemd_unit.dart';
import 'package:gisila_agent/runtime/exec.dart';

/// Parameters for a Celery deployment passed to [Applier.applyCeleryUnits].
class CeleryUnitParams {
  const CeleryUnitParams({
    required this.celeryApp,
    required this.workerCount,
    this.concurrency = 4,
    this.queues,
    this.extraArgs,
    this.beatEnabled = false,
    this.memoryMb = 512,
    this.cpuQuotaPercent = 50,
  });

  final String celeryApp;
  final int workerCount;
  final int concurrency;
  final String? queues;
  final String? extraArgs;
  final bool beatEnabled;
  final int memoryMb;
  final int cpuQuotaPercent;
}

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
    bool isJit = false,
    String? runtimeBinDir,
    String? workingDir,
    bool writableSource = false,
    Map<String, String> envVars = const {},
  }) async {
    if (isDocker) {
      await _applyUnitDocker(
        appId: appId,
        linuxUser: linuxUser,
        workDir: workDir,
        startCommand: startCommand,
        port: port,
        runtimeBinDir: runtimeBinDir,
        workingDir: workingDir,
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
        isJit: isJit,
        runtimeBinDir: runtimeBinDir,
        workingDir: workingDir,
        writableSource: writableSource,
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
    String? runtimeBinDir,
    String? workingDir,
    Map<String, String> envVars = const {},
  }) async {
    final conf = SupervisorConf(
      appId: appId,
      linuxUser: linuxUser,
      workDir: workDir,
      startCommand: startCommand,
      port: port,
      runtimeBinDir: runtimeBinDir,
      workingDir: workingDir,
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
    bool isJit = false,
    String? runtimeBinDir,
    String? workingDir,
    bool writableSource = false,
    Map<String, String> envVars = const {},
  }) async {
    final profile = ApparmorProfile(
      linuxUser: linuxUser,
      workDir: workDir,
      writableSource: writableSource,
    );
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
      isJit: isJit,
      runtimeBinDir: runtimeBinDir,
      workingDirectory: workingDir,
      writableSource: writableSource,
      envVars: envVars,
    );
    final unitPath = '$systemdDir/gisila-$linuxUser.service';
    File(unitPath).writeAsStringSync(unit.render());
    await ShellExec.run('systemctl', ['daemon-reload']);
    await ShellExec.run('systemctl', ['enable', 'gisila-$linuxUser.service']);
  }

  /// Write and reload systemd (or supervisor) units for a Celery deployment.
  ///
  /// Creates:
  ///  - `gisila-<user>.target`
  ///  - `gisila-<user>-worker-N.service` for each worker
  ///  - `gisila-<user>-beat.service`  (when [params.beatEnabled])
  ///  - `gisila-<user>-flower.service` (always — Flower UI on [port])
  Future<void> applyCeleryUnits({
    required int appId,
    required String linuxUser,
    required String workDir,
    required int port,
    required CeleryUnitParams params,
    Map<String, String> envVars = const {},
  }) async {
    if (isDocker) {
      final conf = CeleryWorkerSupervisorConf(
        appId: appId,
        linuxUser: linuxUser,
        workDir: workDir,
        celeryApp: params.celeryApp,
        port: port,
        workerCount: params.workerCount,
        concurrency: params.concurrency,
        queues: params.queues,
        extraArgs: params.extraArgs,
        beatEnabled: params.beatEnabled,
        envVars: envVars,
      );
      Directory(supervisorConfDir).createSync(recursive: true);
      // Write a single file — the [group:] block lets supervisorctl address all
      // processes at once as "gisila-<linuxUser>".
      File('$supervisorConfDir/gisila-$linuxUser.conf')
          .writeAsStringSync(conf.render());
      await ShellExec.run('supervisorctl', ['update'], requireSuccess: false);
      return;
    }

    // ── systemd path ──────────────────────────────────────────────────────────

    // 0. Remove stale worker units from previous deploys that used more workers.
    final existingWorkerFiles = Directory(systemdDir)
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.path.split('/').last;
          return RegExp(r'^gisila-' + linuxUser + r'-worker-\d+\.service$')
              .hasMatch(name);
        })
        .toList();
    for (final f in existingWorkerFiles) {
      final name = f.path.split('/').last;
      final idx = int.tryParse(
          RegExp(r'-worker-(\d+)\.service$').firstMatch(name)?.group(1) ?? '');
      if (idx != null && idx > params.workerCount) {
        await ShellExec.run('systemctl', ['disable', name],
            requireSuccess: false);
        await ShellExec.run('systemctl', ['stop', name],
            requireSuccess: false);
        f.deleteSync();
      }
    }

    // 1. Target unit
    final target = CeleryTarget(linuxUser: linuxUser, appId: appId);
    File('$systemdDir/${target.targetName}')
        .writeAsStringSync(target.render());

    // 2. Worker units
    final perWorkerMemory = params.memoryMb;
    final perWorkerCpu = params.cpuQuotaPercent;
    for (var i = 1; i <= params.workerCount; i++) {
      final unit = CeleryWorkerUnit(
        appId: appId,
        linuxUser: linuxUser,
        workDir: workDir,
        celeryApp: params.celeryApp,
        workerIndex: i,
        concurrency: params.concurrency,
        queues: params.queues,
        extraArgs: params.extraArgs,
        memoryMb: perWorkerMemory,
        cpuQuotaPercent: perWorkerCpu,
        envVars: envVars,
      );
      File('$systemdDir/${unit.serviceName}.service')
          .writeAsStringSync(unit.render());
    }

    // 3. Beat (optional)
    if (params.beatEnabled) {
      final beat = CeleryBeatUnit(
        appId: appId,
        linuxUser: linuxUser,
        workDir: workDir,
        celeryApp: params.celeryApp,
        envVars: envVars,
      );
      File('$systemdDir/${beat.serviceName}.service')
          .writeAsStringSync(beat.render());
    }

    // 4. Flower (always)
    final flower = CeleryFlowerUnit(
      appId: appId,
      linuxUser: linuxUser,
      workDir: workDir,
      celeryApp: params.celeryApp,
      port: port,
      memoryMb: 128,
      cpuQuotaPercent: 10,
      envVars: envVars,
    );
    File('$systemdDir/${flower.serviceName}.service')
        .writeAsStringSync(flower.render());

    await ShellExec.run('systemctl', ['daemon-reload']);
    await ShellExec.run('systemctl', ['enable', 'gisila-$linuxUser.target']);
    for (var i = 1; i <= params.workerCount; i++) {
      await ShellExec.run(
          'systemctl', ['enable', 'gisila-$linuxUser-worker-$i.service']);
    }
    await ShellExec.run(
        'systemctl', ['enable', 'gisila-$linuxUser-flower.service']);
    if (params.beatEnabled) {
      await ShellExec.run(
          'systemctl', ['enable', 'gisila-$linuxUser-beat.service']);
    }
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

  /// Write a static-file nginx vhost.
  Future<void> applyStaticVhost({
    required int appId,
    required String staticDir,
    required List<String> hostnames,
    bool isSpa = false,
  }) async {
    final resolved = _resolveStaticDir(staticDir);
    // nginx (www-data) must be able to reach + read the build output. The per-app
    // work dir and its releases/ are 0750 app-owned, so without this nginx gets
    // "stat() … failed (13: Permission denied)" and serves nothing.
    await _grantNginxAccess(resolved);
    final vhost = StaticNginxVhost(
      appId: appId,
      staticDir: resolved,
      hostnames: hostnames,
      isSpa: isSpa,
    ).render();
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

  /// Resolve the directory nginx should actually serve for a static app.
  ///
  /// When the configured [staticDir] already has an `index.html`, use it as-is.
  /// Otherwise the user likely left the static root blank for a framework that
  /// builds into a subdirectory (Vite → `dist`, CRA → `build`, Astro → `dist`,
  /// Nuxt generate → `.output/public`). Probe the conventional output folders
  /// and serve the first one that contains an `index.html`. Falls back to the
  /// original path when nothing matches, so behaviour is never worse than before.
  static String _resolveStaticDir(String staticDir) {
    if (File('$staticDir/index.html').existsSync()) return staticDir;
    for (final sub in const [
      'dist',
      'build',
      'out',
      '.output/public',
      'dist/public',
      'public',
    ]) {
      if (File('$staticDir/$sub/index.html').existsSync()) {
        stdout.writeln(
            '[agent] static root has no index.html — serving detected build '
            'output "$sub" instead.');
        return '$staticDir/$sub';
      }
    }
    return staticDir;
  }

  /// Grant the nginx worker user (`www-data`) the access it needs to serve a
  /// static app's build output.
  ///
  /// Per-app work dirs are `0750` and owned by the app's own Linux user, and
  /// `<work>/releases` is `0750` too — so nginx, which runs as `www-data`,
  /// cannot even traverse into them to reach the (world-readable) build output
  /// and fails every request with `stat() … (13: Permission denied)`.
  ///
  /// We grant www-data a *scoped* ACL — execute (traverse only) on each per-app
  /// ancestor directory, and read+traverse on the served tree — so that other
  /// tenants gain nothing (their files stay unreadable to each other) while
  /// nginx can serve. ACLs apply immediately with no nginx restart. A recursive
  /// + default ACL keeps freshly-rebuilt files accessible on every redeploy.
  /// Falls back to widening the "other" permission bits when ACLs are
  /// unavailable, so the site still serves.
  Future<void> _grantNginxAccess(String staticDir) async {
    const nginx = 'www-data';
    final hasAcl = await _ensureAcl();

    // Per-app ancestor directories that need a traverse bit: everything from
    // `/srv/apps/<app>` down to (but excluding) the served dir. Path segments
    // with depth < 3 (`/`, `/srv`, `/srv/apps`) are skipped — those are shared
    // and already world-traversable.
    final segs = staticDir.split('/').where((s) => s.isNotEmpty).toList();
    final ancestors = <String>[];
    var path = '';
    for (var i = 0; i < segs.length - 1; i++) {
      path = '$path/${segs[i]}';
      if (i + 1 >= 3) ancestors.add(path);
    }

    if (hasAcl) {
      for (final dir in ancestors) {
        await ShellExec.run('setfacl', ['-m', 'u:$nginx:--x', dir],
            requireSuccess: false);
      }
      await ShellExec.run('setfacl', ['-R', '-m', 'u:$nginx:rX', staticDir],
          requireSuccess: false);
      await ShellExec.run('setfacl', ['-R', '-d', '-m', 'u:$nginx:rX', staticDir],
          requireSuccess: false);
    } else {
      // No ACL support: widen the "other" bits. Looser (any local user can
      // traverse the ancestors), but static web content is public and the app
      // must serve. Traverse-only on ancestors; read on the served tree.
      for (final dir in ancestors) {
        await ShellExec.run('chmod', ['o+x', dir], requireSuccess: false);
      }
      await ShellExec.run('chmod', ['-R', 'o+rX', staticDir],
          requireSuccess: false);
    }
  }

  /// Ensure `setfacl` is available, installing the `acl` package if missing.
  /// Returns whether ACLs can be used after the attempt.
  Future<bool> _ensureAcl() async {
    if ((await Process.run('sh', ['-c', 'command -v setfacl'])).exitCode == 0) {
      return true;
    }
    await ShellExec.run('apt-get', ['install', '-y', '-qq', 'acl'],
        requireSuccess: false);
    return (await Process.run('sh', ['-c', 'command -v setfacl'])).exitCode == 0;
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

  Future<void> start(String linuxUser, {String runtime = ''}) async {
    if (runtime == 'static') {
      // Static sites have no process — just ensure nginx is serving them.
      if (isDocker) {
        await ShellExec.run('nginx', ['-s', 'reload'], requireSuccess: false);
      } else {
        await ShellExec.run('systemctl', ['reload', 'nginx'],
            requireSuccess: false);
      }
      return;
    }
    if (runtime == 'celery') {
      if (isDocker) {
        await ShellExec.run('supervisorctl', ['start', 'gisila-$linuxUser:*'],
            requireSuccess: false);
      } else {
        await ShellExec.run('systemctl', ['start', 'gisila-$linuxUser.target']);
      }
      return;
    }
    if (isDocker) {
      await ShellExec.run('supervisorctl', ['start', 'gisila-$linuxUser'],
          requireSuccess: false);
    } else {
      await ShellExec.run('systemctl', ['start', 'gisila-$linuxUser.service']);
    }
  }

  Future<void> stop(String linuxUser, {String runtime = ''}) async {
    if (runtime == 'static') return;
    if (runtime == 'celery') {
      if (isDocker) {
        await ShellExec.run('supervisorctl', ['stop', 'gisila-$linuxUser:*'],
            requireSuccess: false);
      } else {
        await ShellExec.run('systemctl', ['stop', 'gisila-$linuxUser.target']);
      }
      return;
    }
    if (isDocker) {
      await ShellExec.run('supervisorctl', ['stop', 'gisila-$linuxUser'],
          requireSuccess: false);
    } else {
      await ShellExec.run('systemctl', ['stop', 'gisila-$linuxUser.service']);
    }
  }

  Future<void> restart(String linuxUser, {String runtime = ''}) async {
    if (runtime == 'static') {
      if (isDocker) {
        await ShellExec.run('nginx', ['-s', 'reload'], requireSuccess: false);
      } else {
        await ShellExec.run('systemctl', ['reload', 'nginx'],
            requireSuccess: false);
      }
      return;
    }
    if (runtime == 'celery') {
      if (isDocker) {
        await ShellExec.run('supervisorctl', ['restart', 'gisila-$linuxUser:*'],
            requireSuccess: false);
      } else {
        await ShellExec.run(
            'systemctl', ['restart', 'gisila-$linuxUser.target']);
      }
      return;
    }
    if (isDocker) {
      await ShellExec.run('supervisorctl', ['restart', 'gisila-$linuxUser'],
          requireSuccess: false);
    } else {
      await ShellExec.run(
          'systemctl', ['restart', 'gisila-$linuxUser.service']);
    }
  }

  /// Fully tear down every host resource an app created, leaving nothing
  /// behind. Each step is best-effort (`requireSuccess: false`) so a missing
  /// piece never blocks removal of the rest.
  ///
  /// Removed, in order:
  ///   1. process-manager units (systemd services/target or supervisor conf)
  ///   2. the AppArmor profile (unloaded from the kernel, then deleted)
  ///   3. the nginx vhost
  ///   4. Let's Encrypt certificates for the app's [hostnames]
  ///   5. the work dir (`/srv/apps/<user>` — releases, shared, logs, …)
  ///   6. the Linux user account
  Future<void> uninstall(
    String linuxUser,
    int? appId, {
    String runtime = '',
    String? workDir,
    List<String> hostnames = const [],
    bool removeUser = true,
  }) async {
    // ── 1. Process-manager units ──────────────────────────────────────────
    if (isDocker) {
      // Stop the group (celery) or single program (others).
      final target = runtime == 'celery'
          ? 'gisila-$linuxUser:*'
          : 'gisila-$linuxUser';
      await ShellExec.run('supervisorctl', ['stop', target],
          requireSuccess: false);
      final conf = '$supervisorConfDir/gisila-$linuxUser.conf';
      if (File(conf).existsSync()) File(conf).deleteSync();
      await ShellExec.run('supervisorctl', ['update'], requireSuccess: false);
    } else {
      if (runtime == 'celery') {
        await ShellExec.run(
            'systemctl', ['stop', 'gisila-$linuxUser.target'],
            requireSuccess: false);
        await ShellExec.run(
            'systemctl', ['disable', 'gisila-$linuxUser.target'],
            requireSuccess: false);
        // Remove all related unit files (target + worker/beat/flower services).
        for (final f in Directory(systemdDir)
            .listSync()
            .whereType<File>()
            .where((f) =>
                f.path
                    .split('/')
                    .last
                    .startsWith('gisila-$linuxUser-') ||
                f.path
                    .split('/')
                    .last == 'gisila-$linuxUser.target')) {
          f.deleteSync();
        }
      } else {
        await ShellExec.run(
            'systemctl', ['stop', 'gisila-$linuxUser.service'],
            requireSuccess: false);
        await ShellExec.run(
            'systemctl', ['disable', 'gisila-$linuxUser.service'],
            requireSuccess: false);
        final unitPath = '$systemdDir/gisila-$linuxUser.service';
        if (File(unitPath).existsSync()) File(unitPath).deleteSync();
      }
      await ShellExec.run('systemctl', ['daemon-reload'],
          requireSuccess: false);

      // ── 2. AppArmor profile ─────────────────────────────────────────────
      // Unload the profile from the kernel before deleting the file, otherwise
      // the policy lingers in memory until the next reboot.
      final apparmorPath = '$apparmorDir/gisila-$linuxUser';
      if (File(apparmorPath).existsSync()) {
        await ShellExec.run('apparmor_parser', ['-R', apparmorPath],
            requireSuccess: false);
        File(apparmorPath).deleteSync();
      }
    }

    // ── 3. nginx vhost ────────────────────────────────────────────────────
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

    // ── 4. TLS certificates ───────────────────────────────────────────────
    // Each domain gets its own certbot lineage named after the hostname.
    for (final hostname in hostnames) {
      await ShellExec.run(
        'certbot',
        ['delete', '--cert-name', hostname, '--non-interactive'],
        requireSuccess: false,
      );
    }

    // ── 5. Work dir ───────────────────────────────────────────────────────
    // releases/, shared/, logs/, tmp/, the venv/runtime symlinks — everything.
    if (workDir != null && workDir.isNotEmpty) {
      await ShellExec.run('rm', ['-rf', workDir], requireSuccess: false);
    }

    // ── 6. Linux user ─────────────────────────────────────────────────────
    // The account was created with --no-create-home and its work dir is gone,
    // so a plain userdel removes it completely.
    if (removeUser) {
      await ShellExec.run('userdel', [linuxUser], requireSuccess: false);
    }
  }
}
