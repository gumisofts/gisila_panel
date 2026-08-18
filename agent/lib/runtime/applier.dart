import 'dart:io';

import 'package:gisila_agent/generators/apparmor_profile.dart';
import 'package:gisila_agent/generators/nginx_vhost.dart';
import 'package:gisila_agent/generators/supervisor_conf.dart';
import 'package:gisila_agent/generators/systemd_unit.dart';
import 'package:gisila_agent/runtime/exec.dart';
import 'package:gisila_agent/runtime/priv.dart';

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
    bool directSocket = false,
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
        directSocket: directSocket,
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
    bool directSocket = false,
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

    // systemd rejects relative ExecStart paths with a slash (e.g. bin/server.exe)
    // as a "bad unit file setting". Resolve those against the unit working dir.
    // For compiled runtimes the real binary is always installed at current/app.
    final unitWorkingDir = workingDir ??
        ((isPython || isJit)
            ? '$workDir/releases/current_build'
            : '$workDir/current');
    var resolvedStart = SystemdUnit.absolutizeExecStart(
      startCommand,
      workingDirectory: unitWorkingDir,
    );
    if (!isPython && !isJit) {
      final exe = resolvedStart.split(RegExp(r'\s+')).first;
      final installed = '$workDir/current/app';
      if (exe != installed &&
          !File(exe).existsSync() &&
          File(installed).existsSync()) {
        stdout.writeln(
          '[agent] start command "$startCommand" resolved to missing "$exe"; '
          'using installed artifact $installed',
        );
        resolvedStart = installed;
      }
    }

    final unit = SystemdUnit(
      appId: appId,
      linuxUser: linuxUser,
      workDir: workDir,
      startCommand: resolvedStart,
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
      directSocket: directSocket,
    );
    final unitPath = '$systemdDir/gisila-$linuxUser.service';
    File(unitPath).writeAsStringSync(unit.render());
    await ShellExec.run('systemctl', ['daemon-reload']);
    // Catch bad ExecStart / missing settings before enable/restart so the
    // deploy log shows a clear verify error instead of a opaque restart failure.
    final verify = await Process.run('systemd-analyze', ['verify', unitPath]);
    if (verify.exitCode != 0) {
      final err = '${verify.stderr}\n${verify.stdout}'.trim();
      throw StateError('Invalid systemd unit $unitPath:\n$err');
    }
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
      // Flower accumulates task/event state over time; 128M was too tight and
      // led to systemd OOM-kills + restarts. 512M gives ample headroom.
      memoryMb: 512,
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
    String? staticRoot,
    String? mediaRoot,
    bool protectedMedia = false,
    int maxUploadMb = 50,
  }) async {
    // Only let nginx serve a file root that actually exists and is non-empty
    // (e.g. Django collectstatic produced it). A bare/missing dir is dropped so
    // non-Django apps keep every path proxied to the app process.
    final effectiveStatic = _servableDir(staticRoot, requireNonEmpty: true);
    // Media is served even when empty so uploads created after deploy are
    // reachable without re-rendering the vhost.
    final effectiveMedia = _servableDir(mediaRoot, requireNonEmpty: false);
    // www-data must be able to traverse the per-app dirs and read the tree.
    if (effectiveStatic != null) await _grantNginxAccess(effectiveStatic);
    if (effectiveMedia != null) await _grantNginxAccess(effectiveMedia);

    final vhost = NginxVhost(
      appId: appId,
      port: port,
      hostnames: hostnames,
      staticRoot: effectiveStatic,
      mediaRoot: effectiveMedia,
      protectedMedia: effectiveMedia != null && protectedMedia,
      maxUploadMb: maxUploadMb,
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

  /// How many published static releases to retain under `releases/web/` (the
  /// live one always counts toward this budget and is never pruned).
  static const _keepStaticReleases = 5;

  /// Write a static-file nginx vhost backed by an atomically-swapped release.
  ///
  /// nginx always serves the **stable symlink** `<workDir>/current/web`. On a
  /// deploy ([publishFrom] set) the freshly-built output is copied into a new
  /// `releases/web/<id>` directory and `current/web` is repointed at it with a
  /// single `ln -sfn` (a `rename(2)`, hence atomic); old releases are then
  /// pruned. Because the swap happens only after a successful build and nginx's
  /// `root` never changes, nginx never observes a deleted or half-built root —
  /// this is what fixes the "works, then 404" bug where the previous design
  /// served `releases/current_build` directly and that directory was `rm -rf`'d
  /// at the start of the next build.
  ///
  /// When [publishFrom] is null (e.g. a domain add/remove re-rendering the
  /// vhost) the current release is left in place and only the `server_name` /
  /// SPA settings are refreshed.
  Future<void> applyStaticVhost({
    required int appId,
    required String workDir,
    required List<String> hostnames,
    String? publishFrom,
    String? releaseId,
    String? user,
    bool isSpa = false,
  }) async {
    final served = '$workDir/current/web';

    if (publishFrom != null && publishFrom.isNotEmpty) {
      final resolved = _resolveStaticDir(publishFrom);
      final realDir = await _publishStaticRelease(
        workDir: workDir,
        sourceDir: resolved,
        releaseId: releaseId,
        user: user,
      );
      // nginx (www-data) must reach + read the published tree. The per-app work
      // dir and its releases/ are 0750 app-owned, so without this nginx gets
      // "stat() … failed (13: Permission denied)" and serves nothing.
      await _grantNginxAccess(realDir);
    }
    // nginx follows `current/web` → the real release dir; grant traverse on
    // `current/` so it can resolve the symlink even on a no-publish re-render.
    await _grantTraverse('$workDir/current');

    final vhost = StaticNginxVhost(
      appId: appId,
      staticDir: served,
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

  /// Copy [sourceDir] into a fresh `releases/web/<id>` directory, atomically
  /// repoint `current/web` at it, then prune all but the newest
  /// [_keepStaticReleases] releases (never the live one). Returns the absolute
  /// path of the new release dir.
  Future<String> _publishStaticRelease({
    required String workDir,
    required String sourceDir,
    String? releaseId,
    String? user,
  }) async {
    final id = (releaseId != null && releaseId.isNotEmpty)
        ? releaseId
        : DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    final webRoot = '$workDir/releases/web';
    final releaseDir = '$webRoot/$id';
    final link = '$workDir/current/web';

    await ShellExec.run('mkdir', ['-p', webRoot]);
    // Re-deploying the same id (e.g. a retried deployment) must start clean.
    await ShellExec.run('rm', ['-rf', releaseDir]);
    await ShellExec.run('mkdir', ['-p', releaseDir]);
    // Copy the *contents* of the resolved build output (the trailing `/.` keeps
    // dotfiles and avoids nesting the source dir name inside the release).
    await ShellExec.run('cp', ['-a', '$sourceDir/.', releaseDir]);
    // Never expose VCS metadata (the source may be the repo root when a plain
    // HTML site has no build subdir). Best-effort.
    await ShellExec.run('rm', ['-rf', '$releaseDir/.git'], requireSuccess: false);
    if (user != null && user.isNotEmpty) {
      await ShellExec.run('chown', ['-R', '$user:$user', releaseDir],
          requireSuccess: false);
    }

    // Atomic swap: `ln -sfn` replaces the symlink via rename(2), so nginx sees
    // either the old target or the new one — never a missing root.
    await ShellExec.run('mkdir', ['-p', '$workDir/current']);
    await ShellExec.run('ln', ['-sfn', releaseDir, link]);
    if (user != null && user.isNotEmpty) {
      await ShellExec.run('chown', ['-h', '$user:$user', link],
          requireSuccess: false);
    }

    await _pruneStaticReleases(webRoot, liveTarget: releaseDir);
    return releaseDir;
  }

  /// Keep the newest [_keepStaticReleases] release dirs under [webRoot] (always
  /// including [liveTarget]); delete the rest. Best-effort — a failed prune must
  /// never fail the deploy.
  Future<void> _pruneStaticReleases(String webRoot,
      {required String liveTarget}) async {
    final dir = Directory(webRoot);
    if (!dir.existsSync()) return;
    final dirs = dir.listSync().whereType<Directory>().toList()
      // Newest first by mtime — deployment ids and ms timestamps don't sort
      // lexically, so order by modification time instead.
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    final keep = <String>{liveTarget};
    for (final d in dirs) {
      if (keep.length >= _keepStaticReleases) break;
      keep.add(d.path);
    }
    for (final d in dirs) {
      if (!keep.contains(d.path)) {
        await ShellExec.run('rm', ['-rf', d.path], requireSuccess: false);
      }
    }
  }

  /// Grant www-data the traverse (execute) bit on a single directory, falling
  /// back to widening the "other" bit when ACLs are unavailable.
  Future<void> _grantTraverse(String dir) async {
    if (await _ensureAcl()) {
      await ShellExec.run('setfacl', ['-m', 'u:www-data:--x', dir],
          requireSuccess: false);
    } else {
      await ShellExec.run('chmod', ['o+x', dir], requireSuccess: false);
    }
  }

  /// Returns [dir] when it is a directory nginx should serve, else null.
  ///
  /// A null/empty path, or (when [requireNonEmpty]) an empty directory, yields
  /// null so the caller omits the corresponding nginx `location` block.
  static String? _servableDir(String? dir, {required bool requireNonEmpty}) {
    if (dir == null || dir.isEmpty) return null;
    final d = Directory(dir);
    if (!d.existsSync()) return null;
    if (requireNonEmpty && d.listSync().isEmpty) return null;
    return dir;
  }

  /// Resolve the directory nginx should actually serve for a static app.
  ///
  /// When the configured [staticDir] already has an `index.html`, use it as-is.
  /// Otherwise the user likely left the static root blank for a framework that
  /// builds into a subdirectory (Vite → `dist`, CRA → `build`, Astro → `dist`,
  /// Nuxt generate → `.output/public`, Next export → `out`). Probe the
  /// conventional output folders and serve the first one that contains an
  /// `index.html`.
  ///
  /// If [staticDir] itself is missing (wrong setting, or build wrote elsewhere),
  /// probe the parent directory the same way before failing with a clear error.
  static String _resolveStaticDir(String staticDir) {
    const candidates = <String>[
      'dist',
      'build',
      'out',
      '.output/public',
      'dist/public',
      'public',
    ];

    String? withIndex(String dir) {
      if (File('$dir/index.html').existsSync()) return dir;
      for (final sub in candidates) {
        if (File('$dir/$sub/index.html').existsSync()) {
          stdout.writeln(
              '[agent] static root has no index.html — serving detected build '
              'output "$sub" instead.');
          return '$dir/$sub';
        }
      }
      return null;
    }

    final direct = withIndex(staticDir);
    if (direct != null) return direct;

    if (!Directory(staticDir).existsSync()) {
      final parent = Directory(staticDir).parent.path;
      final fromParent = withIndex(parent);
      if (fromParent != null) {
        stdout.writeln(
            '[agent] configured static root "$staticDir" is missing — '
            'using detected build output at "$fromParent" instead.');
        return fromParent;
      }
      final hint = candidates
          .where((s) => Directory('$parent/$s').existsSync())
          .toList();
      final hintText = hint.isEmpty
          ? 'No conventional build output (dist/build/out/…) was found under '
              '$parent either.'
          : 'Found folder(s) without index.html: ${hint.join(', ')}.';
      throw StateError(
        'Static files directory does not exist: $staticDir\n'
        '$hintText\n'
        'Set "Static files directory" to your build output (e.g. dist, build, '
        'out) or leave it blank to auto-detect, and ensure the build command '
        'produces an index.html there.',
      );
    }

    // Directory exists but has no index.html and no known subfolder — publish
    // it as-is (plain asset trees without index are unusual but valid).
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
    try {
      await Priv.aptUpdate(failOk: true);
      await Priv.aptInstall(['acl']);
    } catch (_) {
      // Best-effort — caller falls back when setfacl is still missing.
    }
    return (await Process.run('sh', ['-c', 'command -v setfacl'])).exitCode == 0;
  }

  /// Write (or rewrite) the nginx vhost that reverse-proxies [hostname] to the
  /// local MinIO S3 API on [apiPort], then test + reload nginx. Idempotent.
  Future<void> applyMinioVhost({
    required String hostname,
    required int apiPort,
    String? consoleHostname,
    int? consolePort,
  }) async {
    final vhost = MinioNginxVhost(
      hostname: hostname,
      apiPort: apiPort,
      consoleHostname: consoleHostname,
      consolePort: consolePort,
    ).render();
    Directory(nginxDir).createSync(recursive: true);
    File('$nginxDir/gisila-minio.conf').writeAsStringSync(vhost);
    await ShellExec.run('nginx', ['-t'], requireSuccess: false);
    if (isDocker) {
      await ShellExec.run('nginx', ['-s', 'reload'], requireSuccess: false);
    } else {
      await ShellExec.run('systemctl', ['reload', 'nginx'],
          requireSuccess: false);
    }
  }

  /// Remove the MinIO nginx vhost (e.g. when the public URL is cleared or the
  /// provider is uninstalled) and reload nginx. Best-effort.
  Future<void> removeMinioVhost() async {
    final path = '$nginxDir/gisila-minio.conf';
    if (File(path).existsSync()) File(path).deleteSync();
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

  /// Obtain a cert AND let certbot rewrite the vhost to add the `listen 443 ssl`
  /// server block + HTTP→HTTPS redirect (installer mode, unlike [issueCert]
  /// which only fetches the cert). Used for pgAdmin / mongo-express vhosts
  /// that are not re-rendered by gisila after issuance.
  Future<void> issueCertInstaller(String hostname) async {
    await ShellExec.run('certbot', [
      '--nginx',
      '--non-interactive',
      '--agree-tos',
      '--redirect',
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
      final unit = 'gisila-$linuxUser.service';
      final result = await Process.run('systemctl', ['restart', unit]);
      if (result.exitCode != 0) {
        final detail = '${result.stderr}\n${result.stdout}'.trim();
        final load = await Process.run('systemctl', [
          'show',
          unit,
          '-p',
          'LoadState',
          '-p',
          'LoadError',
          '--value',
        ]);
        throw ProcessException(
          'systemctl',
          ['restart', unit],
          'Failed to restart $unit.\n$detail\n'
              'systemctl show: ${load.stdout.toString().trim()}\n'
              'Hint: relative ExecStart paths like bin/server.exe are invalid — '
              'clear the app start command (use /srv/apps/<app>/current/app) '
              'and redeploy so apply-unit rewrites the unit.',
          result.exitCode,
        );
      }
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
