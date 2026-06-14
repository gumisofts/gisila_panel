import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:gisila_agent/runtime/applier.dart';
import 'package:gisila_agent/runtime/builders.dart';
import 'package:gisila_agent/runtime/node_framework.dart';
import 'package:gisila_agent/runtime/provision.dart';
import 'package:gisila_agent/runtime/validators.dart';

/// gisila-agent — the privileged host-side CLI invoked by the worker.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exitCode = 64;
    return;
  }

  final command = args.first;
  final rest = args.sublist(1);

  try {
    switch (command) {
      case 'provision':
        await _provision(rest);
        break;
      case 'build':
        await _build(rest);
        break;
      case 'apply-unit':
        await _applyUnit(rest);
        break;
      case 'apply-vhost':
        await _applyVhost(rest);
        break;
      case 'issue-cert':
        await _issueCert(rest);
        break;
      case 'start':
      case 'stop':
      case 'restart':
        await _lifecycle(command, rest);
        break;
      case 'uninstall':
        await _uninstall(rest);
        break;
      case 'logs':
        await _logs(rest);
        return; // _logs streams and exits on its own.
      case 'stat':
        await _stat(rest);
        return; // _stat prints a single JSON line and exits.
      case 'exec':
        await _exec(rest);
        return; // _exec streams output and sets exitCode itself.
      case 'service':
        await _service(rest);
        break;
      case 'mail':
        await _mail(rest);
        break;
      case 'postgres':
        await _postgres(rest);
        break;
      case 'python':
        await _pythonCmd(rest);
        break;
      default:
        _usage();
        exitCode = 64;
        return;
    }
    _ok({'command': command});
  } catch (e, st) {
    stderr.writeln(e);
    stderr.writeln(st);
    _err({'command': command, 'error': e.toString()});
    exitCode = 1;
  }
}

ArgResults _parse(List<String> args, void Function(ArgParser) build) {
  final parser = ArgParser();
  build(parser);
  return parser.parse(args);
}

Future<void> _provision(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('app-id', mandatory: true);
    p.addOption('user', mandatory: true);
    p.addOption('work-dir', mandatory: true);
    // Optional: static apps have no port. Validate only when supplied.
    p.addOption('port');
  });
  final user = AgentValidators.requireUser(r['user'] as String?);
  final workDir = AgentValidators.requireWorkDir(r['work-dir'] as String?);
  final portRaw = r['port'] as String?;
  if (portRaw != null && portRaw.isNotEmpty) {
    AgentValidators.requirePort(portRaw);
  }
  await Provisioner.ensureLinuxUser(user);
  await Provisioner.ensureWorkDir(workDir, user);
  await Provisioner.ensureEnvFile(workDir, user);
}

Future<void> _build(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('app-id', mandatory: true);
    p.addOption('user', mandatory: true);
    p.addOption('work-dir', mandatory: true);
    p.addOption('runtime', mandatory: true);
    p.addOption('source-type', mandatory: true);
    p.addOption('git-url');
    p.addOption('git-branch');
    p.addOption('build-command');
    p.addOption('artifact-path');
    // SSH deploy key path (optional — for private git repos).
    p.addOption('deploy-key-path');
    // Python / Celery
    p.addOption('python-version');
    p.addOption('wsgi-app');
    // Runtime version pins (one per runtime)
    p.addOption('node-version');
    p.addOption('dart-version');
    p.addOption('go-version');
    p.addOption('rust-version');
    p.addOption('bun-version');
  });
  final user = AgentValidators.requireUser(r['user'] as String?);
  final workDir = AgentValidators.requireWorkDir(r['work-dir'] as String?);
  final runtime = AgentValidators.requireRuntime(r['runtime'] as String?);
  final sourceType =
      AgentValidators.requireSourceType(r['source-type'] as String?);
  final buildCommand =
      AgentValidators.optionalCommand(r['build-command'] as String?);

  switch (sourceType) {
    case 'binary':
      final artifact = r['artifact-path'] as String?;
      if (artifact == null || !File(artifact).existsSync()) {
        throw ArgumentError('Missing or unreadable --artifact-path');
      }
      await Builders.binaryArtifact(
          workDir: workDir, user: user, artifactPath: artifact);
      return;
    case 'git':
      final url = r['git-url'] as String?;
      if (url == null) throw ArgumentError('Missing --git-url');
      await Builders.fromGit(
        workDir: workDir,
        user: user,
        url: url,
        branch: r['git-branch'] as String?,
        deployKeyPath: r['deploy-key-path'] as String?,
      );
      break;
    case 'zip':
      final artifact = r['artifact-path'] as String?;
      if (artifact == null || !File(artifact).existsSync()) {
        throw ArgumentError('Missing or unreadable --artifact-path');
      }
      await Builders.fromZip(workDir: workDir, user: user, zipPath: artifact);
      break;
  }

  switch (runtime) {
    case 'dart':
      await Builders.buildDart(
        workDir: workDir,
        user: user,
        buildCommand: buildCommand,
        dartVersion: r['dart-version'] as String?,
      );
      break;
    case 'go':
      await Builders.buildGo(
        workDir: workDir,
        user: user,
        buildCommand: buildCommand,
        goVersion: r['go-version'] as String?,
      );
      break;
    case 'rust':
      await Builders.buildRust(
        workDir: workDir,
        user: user,
        buildCommand: buildCommand,
        rustVersion: r['rust-version'] as String?,
      );
      break;
    case 'node':
      await Builders.buildNode(
        workDir: workDir,
        user: user,
        buildCommand: buildCommand,
        nodeVersion: r['node-version'] as String?,
      );
      break;
    case 'bun':
      await Builders.buildBun(
        workDir: workDir,
        user: user,
        buildCommand: buildCommand,
        bunVersion: r['bun-version'] as String?,
      );
      break;
    case 'python':
      await Builders.buildPython(
        workDir: workDir,
        user: user,
        buildCommand: buildCommand,
        pythonVersion: r['python-version'] as String?,
      );
      break;
    case 'celery':
      await Builders.buildCelery(
        workDir: workDir,
        user: user,
        buildCommand: buildCommand,
        pythonVersion: r['python-version'] as String?,
      );
      break;
    case 'static':
      await Builders.buildStatic(
          workDir: workDir, user: user, buildCommand: buildCommand);
      break;
    case 'zig':
    case 'binary':
      // Nothing more to do — the executable is already in place.
      break;
  }
}

Future<void> _applyUnit(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('app-id', mandatory: true);
    p.addOption('user', mandatory: true);
    p.addOption('work-dir', mandatory: true);
    // Optional: static apps need no port (resolved below for service runtimes).
    p.addOption('port');
    p.addOption('runtime', defaultsTo: 'binary');
    p.addOption('start-command');
    p.addOption('memory-mb', defaultsTo: '256');
    p.addOption('cpu-quota', defaultsTo: '50');
    p.addOption('tasks-max', defaultsTo: '100');
    p.addOption('env-json', defaultsTo: '{}');
    // Python-specific
    p.addOption('python-mode', defaultsTo: 'wsgi');
    p.addOption('wsgi-app');
    p.addOption('workers', defaultsTo: '4');
    p.addOption('gunicorn-threads');
    p.addOption('gunicorn-timeout');
    p.addOption('gunicorn-bind');
    p.addOption('gunicorn-extra-args');
    // Celery-specific
    p.addOption('celery-app');
    p.addOption('celery-worker-count', defaultsTo: '2');
    p.addOption('celery-concurrency', defaultsTo: '4');
    p.addOption('celery-queues');
    p.addOption('celery-extra-args');
    p.addFlag('celery-beat', defaultsTo: false);
    // Node.js / Bun runtime bin dir for PATH injection
    p.addOption('runtime-bin-dir');
  });
  final appId = int.parse(r['app-id'] as String);
  final user = AgentValidators.requireUser(r['user'] as String?);
  final workDir = AgentValidators.requireWorkDir(r['work-dir'] as String?);
  final runtime = r['runtime'] as String;

  // ── Static: no process unit, no port needed ──────────────────────────────
  if (runtime == 'static') {
    stdout.writeln('[agent] static runtime — no process unit required.');
    return;
  }

  // Every remaining (service) runtime listens on a port.
  final port = AgentValidators.requirePort(r['port'] as String?);

  final envJson = r['env-json'] as String;
  final envVars = (jsonDecode(envJson) as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, (v as String?) ?? ''));

  // ── Celery: creates a target + worker/beat/flower services ────────────────
  if (runtime == 'celery') {
    final celeryApp = r['celery-app'] as String?;
    if (celeryApp == null || celeryApp.isEmpty) {
      throw ArgumentError('--celery-app is required for runtime=celery');
    }
    final workerCount = int.tryParse(r['celery-worker-count'] as String) ?? 2;
    final concurrency = int.tryParse(r['celery-concurrency'] as String) ?? 4;
    await Applier().applyCeleryUnits(
      appId: appId,
      linuxUser: user,
      workDir: workDir,
      port: port,
      params: CeleryUnitParams(
        celeryApp: celeryApp,
        workerCount: workerCount.clamp(1, 32),
        concurrency: concurrency.clamp(1, 64),
        queues: r['celery-queues'] as String?,
        extraArgs: r['celery-extra-args'] as String?,
        beatEnabled: r['celery-beat'] as bool,
        memoryMb: int.parse(r['memory-mb'] as String),
        cpuQuotaPercent: int.parse(r['cpu-quota'] as String),
      ),
      envVars: envVars,
    );
    return;
  }

  // ── Standard runtimes ─────────────────────────────────────────────────────
  final isPython = runtime == 'python';
  final isJit = runtime == 'node' || runtime == 'bun';

  // Node/Bun apps run from the build source tree (where package.json /
  // node_modules live). [unitWorkingDir] overrides that when a framework ships a
  // self-contained output (Next standalone). [unitWritableSource] grants the
  // tree write access so server frameworks can write their runtime caches.
  String? unitWorkingDir;
  var unitWritableSource = false;

  String startCommand;
  if (r['start-command'] != null && (r['start-command'] as String).isNotEmpty) {
    startCommand =
        AgentValidators.optionalCommand(r['start-command'] as String)!;
    // An explicit command still needs the corrected cwd + writable source for
    // Node/Bun — historically these ran from $workDir/current, which holds no
    // package.json, so `npm start` crashed with ENOENT.
    if (isJit) unitWritableSource = true;
  } else if (isPython) {
    // Auto-generate the gunicorn start command from the configurable options.
    final mode = r['python-mode'] as String; // wsgi | asgi
    final wsgiApp = r['wsgi-app'] as String? ?? 'app:application';
    final workers = r['workers'] as String;
    final threads = r['gunicorn-threads'] as String?;
    final timeoutRaw = r['gunicorn-timeout'] as String?;
    final timeout =
        (timeoutRaw != null && timeoutRaw.isNotEmpty) ? timeoutRaw : '120';
    final bindRaw = r['gunicorn-bind'] as String?;
    // Use the concrete port number directly. systemd only expands $VAR when it
    // is a complete whitespace-delimited token in ExecStart; embedded occurrences
    // like "0.0.0.0:$PORT" are passed through literally, so gunicorn would
    // receive the string "$PORT" rather than the actual port number.
    final bind =
        (bindRaw != null && bindRaw.isNotEmpty) ? bindRaw : '0.0.0.0:$port';
    final extraArgs = r['gunicorn-extra-args'] as String?;
    final venv = '$workDir/current/.venv';
    final logs = '$workDir/logs';

    final parts = <String>[
      '$venv/bin/gunicorn',
      '--workers',
      workers,
      if (threads != null && threads.isNotEmpty) ...['--threads', threads],
      if (mode == 'asgi') ...[
        '--worker-class',
        'uvicorn.workers.UvicornWorker',
      ],
      '--bind',
      bind,
      '--timeout',
      timeout,
      '--access-logfile',
      '$logs/access.log',
      '--error-logfile',
      '$logs/error.log',
      if (extraArgs != null && extraArgs.trim().isNotEmpty) extraArgs.trim(),
      wsgiApp,
    ];
    startCommand = parts.join(' ');
  } else if (isJit) {
    // Node / Bun with no explicit start command: detect the framework from the
    // built source tree and generate the right command + working directory.
    final src = '$workDir/releases/current_build';
    final plan = NodeFramework.plan(src: src, port: port, runtime: runtime);
    if (plan.isStaticSpa) {
      throw ArgumentError(
        'This app looks like a static ${plan.label} build (output in '
        '"${plan.staticDir}") — it has no server to run on a port. Set the '
        'app runtime to "static" (with build command e.g. "npm run build" and '
        'static root "${plan.staticDir}") instead of "$runtime".',
      );
    }
    if (plan.startCommand == null) {
      throw ArgumentError(
        'Could not determine how to start this $runtime app: no "start" script '
        'and no recognised entrypoint (server.js / index.js / app.js) in '
        '$src. Set an explicit start command in the panel.',
      );
    }
    startCommand = plan.startCommand!;
    unitWorkingDir = plan.workingDir;
    unitWritableSource = true;
    // Apply framework env defaults (e.g. HOST/HOSTNAME=0.0.0.0) without
    // clobbering anything the user configured.
    plan.extraEnv.forEach((k, v) => envVars.putIfAbsent(k, () => v));
    stdout.writeln('[agent] detected ${plan.label} → '
        '$startCommand  (cwd: ${plan.workingDir})');
  } else {
    startCommand = '$workDir/current/app';
  }

  var runtimeBinDir = r['runtime-bin-dir'] as String?;

  // Node apps: prepend the build-resolved pnpm store bin dir (recorded by the
  // `build` step in $workDir/.pnpm-bin) so `pnpm start` invokes the exact
  // pinned pnpm by path — corepack never runs at runtime. Kept first so it wins
  // over any node-version bin dir and the system corepack shims in /usr/bin.
  if (runtime == 'node') {
    final marker = File('$workDir/.pnpm-bin');
    if (marker.existsSync()) {
      final pnpmBinDir = marker.readAsStringSync().trim();
      if (pnpmBinDir.isNotEmpty) {
        runtimeBinDir = (runtimeBinDir != null && runtimeBinDir.isNotEmpty)
            ? '$pnpmBinDir:$runtimeBinDir'
            : pnpmBinDir;
      }
    }
  }

  await Applier().applyUnit(
    appId: appId,
    linuxUser: user,
    workDir: workDir,
    startCommand: startCommand,
    port: port,
    memoryMb: int.parse(r['memory-mb'] as String),
    cpuQuotaPercent: int.parse(r['cpu-quota'] as String),
    tasksMax: int.parse(r['tasks-max'] as String),
    isPython: isPython,
    isJit: isJit,
    runtimeBinDir: (runtimeBinDir != null && runtimeBinDir.isNotEmpty)
        ? runtimeBinDir
        : null,
    workingDir: unitWorkingDir,
    writableSource: unitWritableSource,
    envVars: envVars,
  );
}

Future<void> _applyVhost(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('app-id', mandatory: true);
    // Optional: a static vhost serves files directly and proxies no port.
    p.addOption('port');
    p.addMultiOption('hostname');
    // Static-specific
    p.addOption('runtime', defaultsTo: '');
    p.addOption('static-dir');   // absolute path to static files directory
    p.addFlag('static-spa', defaultsTo: false);
  });
  final appId = int.parse(r['app-id'] as String);
  final runtime = r['runtime'] as String;
  final hostnames = (r['hostname'] as List<String>? ?? <String>[])
      .map(AgentValidators.requireHostname)
      .toList();

  if (runtime == 'static') {
    final staticDir = r['static-dir'] as String?;
    if (staticDir == null || staticDir.isEmpty) {
      throw ArgumentError('--static-dir is required for runtime=static');
    }
    await Applier().applyStaticVhost(
      appId: appId,
      staticDir: staticDir,
      hostnames: hostnames,
      isSpa: r['static-spa'] as bool,
    );
    return;
  }

  // Non-static vhosts reverse-proxy to the app's listening port.
  final port = AgentValidators.requirePort(r['port'] as String?);
  await Applier().applyVhost(appId: appId, port: port, hostnames: hostnames);
}

Future<void> _issueCert(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('hostname', mandatory: true);
  });
  final hostname = AgentValidators.requireHostname(r['hostname'] as String?);
  await Applier().issueCert(hostname);
}

Future<void> _lifecycle(String action, List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('user', mandatory: true);
    p.addOption('runtime', defaultsTo: '');
  });
  final user = AgentValidators.requireUser(r['user'] as String?);
  final runtime = r['runtime'] as String;
  final applier = Applier();
  switch (action) {
    case 'start':
      await applier.start(user, runtime: runtime);
      break;
    case 'stop':
      await applier.stop(user, runtime: runtime);
      break;
    case 'restart':
      await applier.restart(user, runtime: runtime);
      break;
  }
}

Future<void> _uninstall(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('user', mandatory: true);
    p.addOption('app-id');
    p.addOption('runtime', defaultsTo: '');
    p.addOption('work-dir');
    p.addMultiOption('hostname');
  });
  final user = AgentValidators.requireUser(r['user'] as String?);
  final appId = int.tryParse((r['app-id'] as String?) ?? '');
  final runtime = r['runtime'] as String;
  final workDirRaw = (r['work-dir'] as String?)?.trim() ?? '';
  final workDir =
      workDirRaw.isEmpty ? null : AgentValidators.requireWorkDir(workDirRaw);
  final hostnames = (r['hostname'] as List<String>? ?? <String>[])
      .map(AgentValidators.requireHostname)
      .toList();
  await Applier().uninstall(
    user,
    appId,
    runtime: runtime,
    workDir: workDir,
    hostnames: hostnames,
  );
}

/// Stream an app's runtime logs to stdout (consumed by the panel WebSocket).
///
/// On a systemd host this tails `journalctl -u gisila-<user>.service`.
/// In Docker (supervisord) it tails the per-app stdout/stderr log files.
/// With `--follow` the stream stays open until the parent terminates it; we
/// then propagate SIGTERM to the child so no journalctl/tail process leaks.
Future<void> _logs(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('user', mandatory: true);
    p.addOption('work-dir');
    p.addOption('lines', defaultsTo: '200');
    p.addOption('runtime', defaultsTo: '');
    p.addFlag('follow', defaultsTo: false);
  });
  final user = AgentValidators.requireUser(r['user'] as String?);
  final lines = r['lines'] as String;
  final follow = r['follow'] as bool;
  final runtime = r['runtime'] as String;
  final isDocker = Platform.environment['DOCKER_DEPLOY'] == 'true';

  final String exe;
  final List<String> cmdArgs;
  if (isDocker) {
    final workDir = AgentValidators.requireWorkDir(r['work-dir'] as String?);
    exe = 'tail';
    cmdArgs = [
      '-n',
      lines,
      if (follow) '-F',
      '$workDir/logs/stdout.log',
      '$workDir/logs/stderr.log',
    ];
  } else if (runtime == 'celery') {
    // Celery runs as a .target with child worker/beat/flower services.
    // Use a glob so all child units are captured in one stream.
    exe = 'journalctl';
    cmdArgs = [
      '-u',
      'gisila-$user-*.service',
      '-n',
      lines,
      '--no-pager',
      '--output',
      'short-iso',
      if (follow) '-f',
    ];
  } else {
    exe = 'journalctl';
    cmdArgs = [
      '-u',
      'gisila-$user.service',
      '-n',
      lines,
      '--no-pager',
      '--output',
      'short-iso',
      if (follow) '-f',
    ];
  }

  final child = await Process.start(exe, cmdArgs);
  final outSub = child.stdout.listen(stdout.add);
  final errSub = child.stderr.listen(stderr.add);

  // Propagate termination to the child so the tail/journalctl process dies.
  final termSub = ProcessSignal.sigterm
      .watch()
      .listen((_) => child.kill(ProcessSignal.sigterm));
  final intSub = ProcessSignal.sigint
      .watch()
      .listen((_) => child.kill(ProcessSignal.sigterm));

  final code = await child.exitCode;
  await outSub.cancel();
  await errSub.cancel();
  await termSub.cancel();
  await intSub.cancel();
  await stdout.flush();
  exit(code);
}

// ── One-off command execution ────────────────────────────────────────────────

/// Run an arbitrary command as the app's Linux user, inside the app's working
/// directory. For Python apps the project virtualenv is activated first so that
/// `python`, `pip`, `manage.py`, etc. resolve against the app's interpreter.
///
/// stdout/stderr are streamed line-by-line to this process's stdout/stderr (the
/// worker forwards them to the live console). The process exit code becomes this
/// agent invocation's exit code.
Future<void> _exec(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('user', mandatory: true);
    p.addOption('work-dir', mandatory: true);
    p.addOption('runtime', defaultsTo: 'binary');
    p.addOption('command', mandatory: true);
    p.addOption('timeout', defaultsTo: '300'); // seconds
  });
  final user = AgentValidators.requireUser(r['user'] as String?);
  final workDir = AgentValidators.requireWorkDir(r['work-dir'] as String?);
  final runtime = r['runtime'] as String;
  final command = (r['command'] as String?)?.trim() ?? '';
  if (command.isEmpty) throw ArgumentError('--command is required');
  final timeout = int.tryParse(r['timeout'] as String? ?? '300') ?? 300;

  final isPython = runtime == 'python';
  // Python source (with .venv) lives under releases/current_build; other
  // runtimes keep their artifact under current/.
  final runDir =
      isPython ? '$workDir/releases/current_build' : '$workDir/current';
  final activate = isPython
      ? '[ -f .venv/bin/activate ] && source .venv/bin/activate; '
      : '';
  final script = 'cd "$runDir" 2>/dev/null || cd "$workDir"; $activate$command';

  final invocation = _isRoot
      ? ['runuser', '-u', user, '--', 'bash', '-lc', script]
      : ['sudo', '-u', user, 'bash', '-lc', script];

  final proc =
      await Process.start(invocation.first, invocation.skip(1).toList());

  final outSub = proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(stdout.writeln);
  final errSub = proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(stderr.writeln);

  var timedOut = false;
  final timer = Timer(Duration(seconds: timeout), () {
    timedOut = true;
    proc.kill(ProcessSignal.sigkill);
  });

  final code = await proc.exitCode;
  timer.cancel();
  await outSub.cancel();
  await errSub.cancel();
  if (timedOut) {
    stderr.writeln('[exec] command timed out after ${timeout}s and was killed');
  }
  await stdout.flush();
  exitCode = code;
}

// ── Resource sampling ────────────────────────────────────────────────────────

/// Sample a running unit's resource usage and print a single JSON line:
///   {"ok":true,"memBytes":N,"rssBytes":N,"cpuUsageNsec":N,"tasks":N,"active":S}
///
/// On a systemd host this reads `systemctl show` (cgroup accounting — covers the
/// whole process tree, e.g. gunicorn masters + workers). In Docker (supervisord)
/// it falls back to reading `/proc/<pid>` for the program's main process.
///
/// `cpuUsageNsec` is cumulative CPU time since the unit started; the caller
/// computes a percentage from the delta between two samples.
Future<void> _stat(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('user'); // app linux user → unit gisila-<user>.service
    p.addOption('unit'); // explicit systemd unit (e.g. postgresql@16-main)
    p.addOption('program'); // explicit supervisord program name (Docker)
  });
  final user = r['user'] as String?;
  final explicitUnit = r['unit'] as String?;
  final program = r['program'] as String? ?? (user != null ? 'gisila-$user' : null);
  final isDocker = Platform.environment['DOCKER_DEPLOY'] == 'true';

  var memBytes = 0;
  var cpuNsec = 0;
  var tasks = 0;
  var active = 'unknown';

  if (isDocker) {
    if (program == null) throw ArgumentError('--user or --program required');
    final stat = await _statFromProc(program);
    memBytes = stat.$1;
    cpuNsec = stat.$2;
    active = stat.$3;
  } else {
    final unit = explicitUnit ?? (user != null ? 'gisila-$user.service' : null);
    if (unit == null) throw ArgumentError('--user or --unit required');
    final res = await Process.run('systemctl', [
      'show',
      unit,
      '--property=MemoryCurrent',
      '--property=CPUUsageNSec',
      '--property=TasksCurrent',
      '--property=ActiveState',
    ]);
    final map = <String, String>{};
    for (final line in (res.stdout as String).split('\n')) {
      final i = line.indexOf('=');
      if (i > 0) map[line.substring(0, i)] = line.substring(i + 1).trim();
    }
    memBytes = _statInt(map['MemoryCurrent']);
    cpuNsec = _statInt(map['CPUUsageNSec']);
    tasks = _statInt(map['TasksCurrent']);
    active = map['ActiveState'] ?? 'unknown';
  }

  stdout.writeln(jsonEncode({
    'ok': true,
    'memBytes': memBytes,
    'rssBytes': memBytes,
    'cpuUsageNsec': cpuNsec,
    'tasks': tasks,
    'active': active,
  }));
}

/// Parse a systemd numeric property value, treating "[not set]" / non-numeric
/// (e.g. the sentinel `18446744073709551615` meaning "unset") as zero.
int _statInt(String? raw) {
  if (raw == null) return 0;
  final v = int.tryParse(raw.trim());
  if (v == null || v < 0) return 0;
  // systemd reports unset 64-bit counters as UINT64_MAX, which Dart parses as a
  // negative int; the < 0 guard above already handles that case.
  return v;
}

/// Docker fallback: resolve a supervisord program's PID and read `/proc/<pid>`.
/// Returns (memBytes, cpuNsec, activeState).
Future<(int, int, String)> _statFromProc(String program) async {
  final pidRes =
      await Process.run('supervisorctl', ['pid', program]);
  final pid = int.tryParse((pidRes.stdout as String).trim());
  if (pid == null || pid <= 0) return (0, 0, 'inactive');

  // Memory: VmRSS (kB) from /proc/<pid>/status.
  var memBytes = 0;
  try {
    final status = await File('/proc/$pid/status').readAsString();
    final m = RegExp(r'VmRSS:\s+(\d+)\s+kB').firstMatch(status);
    if (m != null) memBytes = int.parse(m.group(1)!) * 1024;
  } catch (_) {}

  // CPU: utime + stime (fields 14,15 in /proc/<pid>/stat) in clock ticks.
  // Assume the conventional 100 Hz tick (1 tick = 10 ms = 1e7 ns).
  var cpuNsec = 0;
  try {
    final stat = await File('/proc/$pid/stat').readAsString();
    // The comm field (2nd) may contain spaces/parens; split after the last ')'.
    final after = stat.substring(stat.lastIndexOf(')') + 1).trim();
    final fields = after.split(RegExp(r'\s+'));
    // fields[0] is state (field 3). utime=field14→index 11, stime=field15→12.
    final utime = int.tryParse(fields[11]) ?? 0;
    final stime = int.tryParse(fields[12]) ?? 0;
    cpuNsec = (utime + stime) * 10000000;
  } catch (_) {}

  return (memBytes, cpuNsec, 'active');
}

// ── Mail server (Postfix + Dovecot virtual mailboxes) ────────────────────────

Future<void> _mail(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: gisila-agent mail <status|setup|sync> [flags]');
    exitCode = 64;
    return;
  }
  final action = args.first;
  final parser = ArgParser()
    ..addOption('domains',
        help: 'JSON array of {domain, hostname, selector, dmarc} objects')
    ..addOption('accounts',
        help: 'JSON array of {address, hash, quota} objects');
  final r = parser.parse(args.sublist(1));

  switch (action) {
    case 'status':
      // Report whether the mail tooling is installed on this host. Used by the
      // panel to decide whether to show the "Install email tools" prompt before
      // the normal domain/mailbox setup. Read-only — needs no privileges.
      stdout.writeln(jsonEncode({'installed': await _mailStackInstalled()}));
    case 'setup':
      await _mailEnsureStack();
    case 'sync':
      final domains = (jsonDecode(r['domains'] as String? ?? '[]') as List)
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final accounts = (jsonDecode(r['accounts'] as String? ?? '[]') as List)
          .whereType<Map>()
          .toList();
      await _mailSync(domains, accounts);
    default:
      throw ArgumentError('Unknown mail action: $action');
  }
}

/// Whether the core mail daemons are present on this host. The panel calls this
/// (via `mail status`) to gate the mail UI behind an explicit install step, so
/// the tooling is no longer provisioned automatically on panel install.
Future<bool> _mailStackInstalled() async {
  Future<bool> present(String bin) async {
    // The daemons live in /usr/sbin, which isn't always on a non-root PATH, so
    // check PATH and the canonical sbin location. No sudo required.
    final res = await Process.run(
      'sh',
      ['-c', 'command -v $bin >/dev/null 2>&1 || test -x /usr/sbin/$bin'],
    );
    return res.exitCode == 0;
  }

  return await present('postfix') &&
      await present('dovecot') &&
      await present('opendkim');
}

/// Install Postfix + Dovecot + OpenDKIM (if missing) and lay down the base
/// virtual-mailbox configuration. Idempotent — safe to run before every sync.
Future<void> _mailEnsureStack() async {
  await _aptInstall([
    'postfix',
    'dovecot-core',
    'dovecot-imapd',
    'dovecot-pop3d',
    'dovecot-lmtpd',
    'opendkim',
    'opendkim-tools',
    'ssl-cert', // provides the snakeoil self-signed cert used as a TLS default
  ]);

  // Ensure a TLS certificate exists before configuring/starting the daemons so
  // STARTTLS / implicit TLS work immediately. Replaced with a SAN cert covering
  // the real mail hostnames during sync.
  await _mailEnsureCert(const []);
  // Always repair permissions on an already-existing key — this fixes servers
  // provisioned before the 644 change (where the key was 640 root:ssl-cert and
  // the postfix user wasn't in the group, causing smtpd to crash silently).
  await _sudo('chmod', ['644', _mailKeyPath], failOk: true);
  await _sudo('chown', ['root:root', _mailKeyPath], failOk: true);

  // Dedicated virtual-mail user owning every mailbox on disk.
  await _sudo('groupadd', ['-g', '5000', 'vmail'], failOk: true);
  await _sudo('useradd', [
    '-r',
    '-g',
    'vmail',
    '-u',
    '5000',
    'vmail',
    '-d',
    '/var/mail/vhosts',
    '-s',
    '/usr/sbin/nologin',
  ], failOk: true);
  await _sudo('mkdir', ['-p', '/var/mail/vhosts'], failOk: true);
  await _sudo('chown', ['-R', 'vmail:vmail', '/var/mail/vhosts'], failOk: true);

  // Postfix: route virtual domains to Dovecot LMTP, auth via Dovecot SASL,
  // TLS via the snakeoil cert (swap in a real cert in production), and sign
  // outbound mail through the OpenDKIM milter.
  const postconf = <String>[
    'virtual_mailbox_base=/var/mail/vhosts',
    'virtual_mailbox_maps=hash:/etc/postfix/vmailbox',
    'virtual_minimum_uid=5000',
    'virtual_uid_maps=static:5000',
    'virtual_gid_maps=static:5000',
    'virtual_transport=lmtp:unix:private/dovecot-lmtp',
    'smtpd_sasl_type=dovecot',
    'smtpd_sasl_path=private/auth',
    'smtpd_sasl_auth_enable=yes',
    'smtpd_recipient_restrictions='
        'permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination',
    // TLS — self-signed cert by default (swap in a real cert in production).
    // postfix won't start if these files don't exist, so we write them first
    // via _mailEnsureCert above.
    'smtpd_tls_cert_file=$_mailCertPath',
    'smtpd_tls_key_file=$_mailKeyPath',
    'smtpd_tls_security_level=may',
    'smtp_tls_security_level=may',
    'smtpd_tls_auth_only=no',
    'smtpd_tls_loglevel=1',
    // DKIM signing milter.
    'milter_default_action=accept',
    'milter_protocol=6',
    // Use explicit IPv4 loopback so there is no IPv6/localhost DNS ambiguity.
    // TCP milter connections work from both chroot'd and non-chroot'd smtpd.
    'smtpd_milters=inet:127.0.0.1:8891',
    'non_smtpd_milters=inet:127.0.0.1:8891',
  ];
  for (final kv in postconf) {
    await _sudo('postconf', ['-e', kv]);
  }

  // Enable the submission (587, STARTTLS) and smtps (465, implicit TLS) client
  // services in master.cf via postconf so mail clients can send authenticated.
  // chroot is disabled ('n') to avoid the empty-chroot pitfalls on Ubuntu.
  await _sudo('postconf',
      ['-M', 'submission/inet=submission inet n - n - - smtpd']);
  for (final p in <String>[
    'submission/inet/syslog_name=postfix/submission',
    'submission/inet/smtpd_tls_security_level=may',
    'submission/inet/smtpd_sasl_auth_enable=yes',
    'submission/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject',
  ]) {
    await _sudo('postconf', ['-P', p]);
  }
  await _sudo('postconf', ['-M', 'smtps/inet=smtps inet n - n - - smtpd']);
  for (final p in <String>[
    'smtps/inet/syslog_name=postfix/smtps',
    'smtps/inet/smtpd_tls_wrappermode=yes',
    'smtps/inet/smtpd_sasl_auth_enable=yes',
    'smtps/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject',
  ]) {
    await _sudo('postconf', ['-P', p]);
  }

  // Dovecot: virtual users from a passwd-file, static userdb mapping to vmail,
  // IMAP + POP3 over TLS.
  //
  // Ubuntu's /etc/dovecot/dovecot.conf ends with "!include_try local.conf",
  // meaning this file is sourced AFTER all conf.d/*.conf files. Settings here
  // therefore override the distribution defaults (10-ssl.conf, 10-auth.conf,
  // 10-master.conf, etc.) without file-ordering battles.
  final dovecotConf = '''
# Generated by gisila-agent — virtual mailbox hosting. Do not edit by hand.
protocols = imap pop3 lmtp
mail_location = maildir:/var/mail/vhosts/%d/%n
mail_privileged_group = vmail
disable_plaintext_auth = no
auth_mechanisms = plain login

# TLS — self-signed cert by default; point at a real cert in production.
ssl = yes
ssl_cert = <$_mailCertPath
ssl_key = <$_mailKeyPath

passdb {
  driver = passwd-file
  args = scheme=SSHA512 username_format=%u /etc/dovecot/users
}
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
}

# Postfix LMTP delivery socket (accessible from chroot and non-chroot alike).
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
# Postfix SASL auth socket.
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
''';
  // local.conf wins over all conf.d/* settings on Ubuntu (loaded last).
  await _writeFileSudo('/etc/dovecot/local.conf', dovecotConf);
  // Remove any old Gisila conf.d file from previous agent versions so that
  // service unix_listener blocks are not defined twice (would prevent startup).
  await _sudo(
    'rm',
    ['-f', '/etc/dovecot/conf.d/99-gisila-mail.conf'],
    failOk: true,
  );

  // OpenDKIM base config + runtime dir. Per-domain key tables are written on
  // sync; this lays down the daemon configuration once.
  //
  // Socket: bind on 127.0.0.1:8891 (explicit IPv4 loopback, not "localhost"
  // which can resolve to ::1 on dual-stack hosts).  TCP milter connections
  // work from chroot'd smtpd (port 25) and from non-chroot'd submission/smtps.
  //
  // Do NOT set "UserID opendkim" here.  Ubuntu 22.04's opendkim.service sets
  // User=opendkim via systemd, so the process is already non-root when it
  // starts.  A second setuid() attempt causes "Operation not permitted" and
  // the daemon refuses to start.
  const opendkimConf = '''
# Generated by gisila-agent — do not edit by hand.
Syslog                  yes
SyslogSuccess           yes
LogWhy                  yes
UMask                   002
Mode                    sv
Canonicalization        relaxed/simple
Socket                  inet:8891@127.0.0.1
PidFile                 /run/opendkim/opendkim.pid
OversignHeaders         From
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
KeyTable                /etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
''';
  await _sudo('mkdir', ['-p', '/etc/opendkim/keys'], failOk: true);
  // The keys/ parent directory MUST be owned by root (not by the opendkim
  // user). OpenDKIM running as root performs a security check and refuses to
  // load keys from a directory writable/owned by any non-root uid.
  await _sudo('chown', ['root:root', '/etc/opendkim/keys'], failOk: true);
  await _sudo('chmod', ['755', '/etc/opendkim/keys'], failOk: true);
  // /run/opendkim lives on tmpfs.  The Ubuntu 22.04 opendkim.service uses
  // RuntimeDirectory=opendkim so systemd creates it before start.  Install a
  // tmpfiles.d snippet as belt-and-suspenders so it also survives on older
  // Ubuntu or when the package is upgraded.
  await _writeFileSudo(
    '/etc/tmpfiles.d/opendkim.conf',
    'd /run/opendkim 0750 opendkim opendkim -\n',
  );
  await _sudo('mkdir', ['-p', '/run/opendkim'], failOk: true);
  await _sudo('chown', ['opendkim:opendkim', '/run/opendkim'], failOk: true);
  await _writeFileSudo('/etc/opendkim.conf', opendkimConf);
  await _writeFileSudo(
    '/etc/opendkim/TrustedHosts',
    '127.0.0.1\n::1\nlocalhost\n',
  );
  // Ensure the key/signing tables exist (even if empty) so the daemon can
  // start before any domain has been added.
  for (final f in <String>['/etc/opendkim/KeyTable', '/etc/opendkim/SigningTable']) {
    if (!await _privFileExists(f)) await _writeFileSudo(f, '');
  }

  // Validate Postfix config before touching running services.
  final cfgCheck = await Process.run(
    _isRoot ? 'postfix' : 'sudo',
    [if (!_isRoot) '--non-interactive', 'postfix', 'check'],
  );
  if (cfgCheck.exitCode != 0) {
    stderr.writeln(
        'mail_ensure_stack: postfix check:\n${cfgCheck.stderr}');
    // Log but continue — a misconfigured Postfix is still better than one
    // that was never started. The error surfaces in the worker log.
  }

  // Make sure every daemon is enabled (survives reboot) and running. opendkim
  // first so Postfix can reach the milter as soon as it (re)starts.
  for (final svc in <String>['opendkim', 'postfix', 'dovecot']) {
    await _serviceCtl('enable', svc);
    await _serviceCtl('reload-or-restart', svc);
  }

  // Open the standard mail ports on the host firewall (no-op when ufw absent).
  await _mailOpenFirewall();
}

/// Self-signed TLS certificate paths used by Postfix + Dovecot. Operators can
/// point these at a real (Let's Encrypt) certificate for full client trust.
const _mailCertPath = '/etc/gisila/mail/mail.crt';
const _mailKeyPath = '/etc/gisila/mail/mail.key';
const _mailCertDir = '/etc/gisila/mail';

/// Generate a self-signed certificate for the mail daemons. When [hostnames]
/// are supplied the cert's CN + SANs cover them so clients don't see a
/// name-mismatch error; otherwise a generic cert is created so daemons can
/// start before any domain exists. Existing certs are only regenerated when
/// the hostname set changes.
///
/// Uses a temp openssl.cnf file for SANs — compatible with all Ubuntu LTS
/// versions including 20.04 which does not have `openssl req -addext`.
Future<void> _mailEnsureCert(List<String> hostnames) async {
  await _sudo('mkdir', ['-p', _mailCertDir], failOk: true);
  await _sudo('chmod', ['755', _mailCertDir], failOk: true);

  final names = hostnames.where((h) => h.trim().isNotEmpty).toSet().toList();

  // Prefer a real, publicly-trusted Let's Encrypt certificate so mail clients
  // (iOS/Android/Outlook) connect without any "untrusted certificate" prompt.
  // Only attempted when we have real hostnames; falls back to the self-signed
  // cert below when issuance isn't possible (no DNS, port 80 blocked, etc.).
  if (names.isNotEmpty && await _mailEnsureLetsEncrypt(names)) {
    return;
  }

  final primary = names.isNotEmpty ? names.first : _systemMailname();
  final desired = names.isEmpty ? primary : names.join(',');

  // Skip regeneration when a cert already exists for the same hostname set.
  final stamp = '$_mailCertDir/.cn';
  final existing = await _readPrivFile(stamp);
  final certExists = await _privFileExists(_mailCertPath);
  if (certExists && existing?.trim() == desired) return;

  // Build a temporary openssl.cnf that includes a SAN extension, so this
  // works on Ubuntu 20.04 (OpenSSL 1.1.1) which lacks `req -addext`.
  final sanEntries = (names.isEmpty ? [primary] : names)
      .map((h) => 'DNS:$h')
      .join(', ');
  final opensslCnf = '''
[req]
distinguished_name = dn
x509_extensions    = v3_req
prompt             = no

[dn]
CN = $primary

[v3_req]
subjectAltName = $sanEntries
keyUsage       = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
''';

  const tmpConf = '/tmp/gisila-mail-openssl.cnf';
  await _writeFileSudo(tmpConf, opensslCnf);

  final cmd = _priv('sh', [
    '-c',
    'openssl req -new -x509 -nodes -days 3650 -newkey rsa:2048 '
        '-config $tmpConf '
        "-keyout '$_mailKeyPath' -out '$_mailCertPath' 2>/dev/null",
  ]);
  await _run(cmd.first, cmd.skip(1).toList(), failOk: true);

  // If openssl failed (e.g. not installed), fall back to snakeoil so the
  // daemons can still start — better than refusing to configure at all.
  if (!await _privFileExists(_mailCertPath)) {
    await _sudo('cp', ['/etc/ssl/certs/ssl-cert-snakeoil.pem', _mailCertPath],
        failOk: true);
    await _sudo('cp', ['/etc/ssl/private/ssl-cert-snakeoil.key', _mailKeyPath],
        failOk: true);
  }

  // Make both files world-readable so postfix + dovecot can always read them
  // without depending on group membership (which requires a process restart to
  // take effect and creates a fragile ordering dependency).
  await _sudo('chmod', ['644', _mailCertPath], failOk: true);
  await _sudo('chmod', ['644', _mailKeyPath], failOk: true);
  await _sudo('chown', ['root:root', _mailCertPath], failOk: true);
  await _sudo('chown', ['root:root', _mailKeyPath], failOk: true);
  await _writeFileSudo(stamp, desired);
  await _sudo('rm', ['-f', tmpConf], failOk: true);
}

/// Stable certbot lineage name + live directory for the mail certificate.
/// Using a fixed `--cert-name` keeps the path constant regardless of how the
/// set of mail hostnames changes over time.
const _mailLeCertName = 'gisila-mail';
const _mailLeLiveDir = '/etc/letsencrypt/live/gisila-mail';

/// Obtain (or reuse) a Let's Encrypt certificate covering every mail
/// [hostnames] entry and point the daemons' stable cert paths at it. Returns
/// true when a real cert is in place; false when issuance isn't possible so the
/// caller can fall back to a self-signed cert.
///
/// Requirements for issuance: each hostname must resolve to this host's public
/// IP and the ACME HTTP-01 challenge must reach port 80 (served by the panel's
/// nginx when present, otherwise certbot's standalone listener).
Future<bool> _mailEnsureLetsEncrypt(List<String> hostnames) async {
  if (hostnames.isEmpty) return false;

  // certbot must be available; install it (plus the nginx plugin) if missing.
  if (!await _hasCommand('certbot')) {
    await _aptInstall(['certbot', 'python3-certbot-nginx']);
  }
  if (!await _hasCommand('certbot')) {
    stderr.writeln('mail_le: certbot unavailable — using self-signed cert.');
    return false;
  }

  final fullchain = '$_mailLeLiveDir/fullchain.pem';
  final privkey = '$_mailLeLiveDir/privkey.pem';
  final desired = (hostnames.toSet().toList()..sort()).join(',');
  final stamp = '$_mailCertDir/.le-hosts';
  final stamped = (await _readPrivFile(stamp))?.trim();

  // (Re)issue when no cert exists yet or the covered hostname set changed.
  if (!await _privFileExists(fullchain) || stamped != desired) {
    final issued = await _mailRunCertbot(hostnames);
    if (issued && await _privFileExists(fullchain)) {
      await _writeFileSudo(stamp, desired);
    }
  }

  // If issuance failed and no prior cert exists, signal fallback.
  if (!await _privFileExists(fullchain)) {
    stderr.writeln('mail_le: no Let\'s Encrypt cert — using self-signed.');
    return false;
  }

  // Mirror the LE material into the stable paths the daemons are configured to
  // read, and keep them fresh on future renewals via a deploy hook.
  await _mailCopyCert(fullchain, privkey);
  await _mailInstallRenewalHook();
  return true;
}

/// Run certbot to obtain/expand the mail certificate. Uses the nginx plugin
/// when nginx is running (the panel serves port 80/443), otherwise the
/// standalone HTTP-01 listener. Returns true on success.
Future<bool> _mailRunCertbot(List<String> hostnames) async {
  final nginxActive =
      (await Process.run('systemctl', ['is-active', 'nginx'])).exitCode == 0;

  final args = <String>[
    'certonly',
    '--non-interactive',
    '--agree-tos',
    '-m', 'admin@${hostnames.first}',
    '--cert-name', _mailLeCertName,
    '--keep-until-expiring',
    '--expand',
    if (nginxActive)
      '--nginx'
    else ...['--standalone', '--preferred-challenges', 'http'],
    for (final h in hostnames) ...['-d', h],
  ];

  final cmd = _priv('certbot', args);
  final res = await Process.run(cmd.first, cmd.skip(1).toList());
  if (res.exitCode != 0) {
    stderr.writeln('mail_le: certbot failed (exit ${res.exitCode}):\n'
        '${res.stdout}\n${res.stderr}');
    return false;
  }
  return true;
}

/// Copy the LE fullchain/privkey into the stable mail cert paths. Kept
/// world-readable (644) so postfix/dovecot read them without depending on
/// group membership — consistent with the self-signed path.
Future<void> _mailCopyCert(String fullchain, String privkey) async {
  await _sudo('cp', [fullchain, _mailCertPath], failOk: true);
  await _sudo('cp', [privkey, _mailKeyPath], failOk: true);
  await _sudo('chmod', ['644', _mailCertPath], failOk: true);
  await _sudo('chmod', ['644', _mailKeyPath], failOk: true);
  await _sudo('chown', ['root:root', _mailCertPath], failOk: true);
  await _sudo('chown', ['root:root', _mailKeyPath], failOk: true);
}

/// Install a certbot deploy hook so renewed mail certs are copied into the
/// stable paths and the mail daemons reload automatically (~every 60 days).
Future<void> _mailInstallRenewalHook() async {
  const hookDir = '/etc/letsencrypt/renewal-hooks/deploy';
  await _sudo('mkdir', ['-p', hookDir], failOk: true);
  const hook = '$hookDir/gisila-mail.sh';
  final script = '''#!/bin/sh
# Installed by gisila-agent — refreshes the mail TLS cert and reloads the mail
# daemons whenever certbot renews the "$_mailLeCertName" certificate.
# Only act when this renewal touched our lineage (or was a bulk renewal).
case "\$RENEWED_LINEAGE" in
  */$_mailLeCertName) ;;
  "") ;;
  *) exit 0 ;;
esac
LIVE="$_mailLeLiveDir"
[ -f "\$LIVE/fullchain.pem" ] || exit 0
cp "\$LIVE/fullchain.pem" "$_mailCertPath"
cp "\$LIVE/privkey.pem" "$_mailKeyPath"
chmod 644 "$_mailCertPath" "$_mailKeyPath"
chown root:root "$_mailCertPath" "$_mailKeyPath"
systemctl reload postfix 2>/dev/null || systemctl restart postfix 2>/dev/null || true
systemctl restart dovecot 2>/dev/null || true
''';
  await _writeFileSudo(hook, script);
  await _sudo('chmod', ['755', hook], failOk: true);
}

/// Whether an executable is on PATH.
Future<bool> _hasCommand(String name) async =>
    (await Process.run('sh', ['-c', 'command -v $name'])).exitCode == 0;

/// Open the standard SMTP/IMAP/POP3 ports when `ufw` is present. Harmless
/// (failOk) when ufw is not installed or not active.
Future<void> _mailOpenFirewall() async {
  final has = await Process.run('sh', ['-c', 'command -v ufw']);
  if (has.exitCode != 0) return; // ufw not installed — nothing to open
  // Port 80 is included so the Let's Encrypt HTTP-01 challenge can reach the
  // host for certificate issuance and renewal.
  for (final port in <String>[
    '80', '25', '465', '587', '143', '993', '110', '995'
  ]) {
    await _sudo('ufw', ['allow', '$port/tcp'], failOk: true);
  }
}

/// Read a (possibly root-owned) file's contents with privileges, or null.
Future<String?> _readPrivFile(String path) async {
  final cmd = _priv('cat', [path]);
  final res = await Process.run(cmd.first, cmd.skip(1).toList());
  if (res.exitCode != 0) return null;
  return res.stdout as String?;
}

/// Write the per-domain/per-account virtual maps, provision DKIM keys, and
/// reload Postfix + Dovecot + OpenDKIM. Emits a single JSON line on stdout with
/// each domain's DKIM public key and the host's detected public IP, which the
/// backend persists onto the domain rows.
Future<void> _mailSync(
  List<Map<String, dynamic>> domains,
  List<Map> accounts,
) async {
  await _mailEnsureStack();

  final domainNames =
      domains.map((d) => d['domain']?.toString() ?? '').where((d) => d.isNotEmpty).toList();

  // Public mail hostname (e.g. mail.bita.et). Postfix announces this as its
  // HELO/EHLO name and uses it as the envelope origin. It MUST match the
  // server's reverse DNS (PTR) or receivers (Gmail etc.) will reject or spam
  // outbound mail. A "localhost" myhostname is the classic cause of "my mail
  // never arrives". Falls back to the first domain's mail.<domain> host.
  final mailHostnames = domains
      .map((d) => d['hostname']?.toString().trim() ?? '')
      .where((h) => h.isNotEmpty)
      .toList();
  final myHostname = mailHostnames.isNotEmpty
      ? mailHostnames.first
      : (domainNames.isNotEmpty ? 'mail.${domainNames.first}' : _systemMailname());

  // Which domains we are authoritative for (handled by the virtual transport).
  await _sudo(
      'postconf', ['-e', 'virtual_mailbox_domains=${domainNames.join(' ')}']);
  await _sudo('postconf', ['-e', 'mydestination=localhost']);
  // Identity used for outbound SMTP (HELO + envelope). Critical for delivery.
  await _sudo('postconf', ['-e', 'myhostname=$myHostname']);
  await _sudo('postconf', ['-e', 'myorigin=\$myhostname']);

  for (final d in domainNames) {
    await _sudo('mkdir', ['-p', '/var/mail/vhosts/$d'], failOk: true);
  }
  await _sudo('chown', ['-R', 'vmail:vmail', '/var/mail/vhosts'], failOk: true);

  final vmailbox = StringBuffer();
  final users = StringBuffer();
  for (final a in accounts) {
    final address = a['address']?.toString() ?? '';
    final hash = a['hash']?.toString() ?? '';
    final at = address.indexOf('@');
    if (at <= 0 || hash.isEmpty) continue;
    final local = address.substring(0, at);
    final domain = address.substring(at + 1);
    vmailbox.writeln('$address $domain/$local/');
    users.writeln('$address:$hash::::::');
  }

  await _writeFileSudo('/etc/postfix/vmailbox', vmailbox.toString());
  await _sudo('postmap', ['/etc/postfix/vmailbox']);

  await _writeFileSudo('/etc/dovecot/users', users.toString());
  await _sudo('chown', ['root:dovecot', '/etc/dovecot/users'], failOk: true);
  await _sudo('chmod', ['640', '/etc/dovecot/users'], failOk: true);

  // Provision DKIM signing keys per domain and rebuild the OpenDKIM tables.
  final dkimResults = await _mailEnsureDkim(domains);

  // Report DKIM public keys + the detected public IP back to the backend *now*,
  // before the cert/postfix-check/restart steps below. Those steps can fail
  // (invalid postfix config makes `postfix check` throw, systemd/apt hiccups,
  // etc.) and used to abort the sync before this line ever ran — stranding the
  // freshly generated keys on disk and leaving the panel stuck on "Waiting for
  // DKIM key…" forever. Emitting here means a later failure can never hide a
  // successful keygen. Nothing below writes to stdout (all routed via _sudo),
  // so this stays the trailing JSON line the backend parses; keep it last.
  final publicIp = await _detectPublicIp();
  stdout.writeln(jsonEncode({
    'domains': dkimResults,
    if (publicIp != null) 'publicIp': publicIp,
  }));

  // Issue a self-signed cert whose CN/SANs cover the real mail hostnames so
  // clients connecting to them don't hit a certificate name mismatch.
  final hostnames = domains
      .map((d) => d['hostname']?.toString() ?? '')
      .where((h) => h.isNotEmpty)
      .toList();
  await _mailEnsureCert(hostnames);

  // Validate Postfix config before restarting — a broken config causes smtpd
  // to accept TCP connections then immediately drop them with no banner.
  final checkResult = await Process.run(
    _isRoot ? 'postfix' : 'sudo',
    [if (!_isRoot) '--non-interactive', 'postfix', 'check'],
  );
  if (checkResult.exitCode != 0) {
    stderr.writeln(
        'mail_sync: postfix check failed:\n${checkResult.stderr}');
    throw Exception('Postfix configuration check failed; aborting restart.');
  }

  await _serviceCtl('restart', 'opendkim');
  await _serviceCtl('reload-or-restart', 'postfix');
  await _serviceCtl('restart', 'dovecot');
}

/// Generate (if missing) a DKIM keypair per domain, rebuild the OpenDKIM
/// KeyTable / SigningTable, and return `{domain: {selector, publicKey}}`.
Future<Map<String, Map<String, String>>> _mailEnsureDkim(
  List<Map<String, dynamic>> domains,
) async {
  final keyTable = StringBuffer();
  final signingTable = StringBuffer();
  final results = <String, Map<String, String>>{};

  for (final d in domains) {
    final domain = d['domain']?.toString() ?? '';
    if (domain.isEmpty) continue;
    final selector = (d['selector']?.toString().trim().isNotEmpty ?? false)
        ? d['selector'].toString().trim()
        : 'gisila';

    final keyDir = '/etc/opendkim/keys/$domain';
    final privatePath = '$keyDir/$selector.private';
    final txtPath = '$keyDir/$selector.txt';

    await _sudo('mkdir', ['-p', keyDir], failOk: true);
    // OpenDKIM (running as root) checks that every directory in the key path
    // is owned by root and not writable by any other uid. If any directory is
    // owned by e.g. the opendkim user (uid 115) it refuses to load the key
    // with "key data is not secure". Keep the domain key directory owned by
    // root with standard 755 permissions.
    await _sudo('chown', ['root:root', keyDir], failOk: true);
    await _sudo('chmod', ['755', keyDir], failOk: true);

    // Generate the keypair only when it does not already exist.
    if (!await _privFileExists(privatePath)) {
      await _sudo('opendkim-genkey', [
        '-b', '2048',
        '-d', domain,
        '-s', selector,
        '-D', keyDir,
      ]);
      await _sudo('chown', ['root:root', privatePath], failOk: true);
      await _sudo('chown', ['root:root', '$keyDir/$selector.txt'], failOk: true);
      await _sudo('chmod', ['600', privatePath], failOk: true);
    }

    keyTable.writeln(
        '$selector._domainkey.$domain $domain:$selector:$privatePath');
    signingTable.writeln('*@$domain $selector._domainkey.$domain');

    final publicKey = await _readDkimPublicKey(txtPath);
    results[domain] = {
      'selector': selector,
      if (publicKey != null) 'publicKey': publicKey,
    };
  }

  await _writeFileSudo('/etc/opendkim/KeyTable', keyTable.toString());
  await _writeFileSudo('/etc/opendkim/SigningTable', signingTable.toString());

  return results;
}

/// Read the generated `.txt` DKIM record and extract the base64 `p=` value,
/// stripping the quoting/whitespace that `opendkim-genkey` wraps it in.
Future<String?> _readDkimPublicKey(String txtPath) async {
  final cmd = _priv('cat', [txtPath]);
  final res = await Process.run(cmd.first, cmd.skip(1).toList());
  if (res.exitCode != 0) return null;
  final raw = res.stdout as String? ?? '';
  // Collapse all quoted segments into the raw record text.
  final unquoted =
      RegExp(r'"([^"]*)"').allMatches(raw).map((m) => m.group(1)).join();
  final body = unquoted.isNotEmpty ? unquoted : raw;
  final match = RegExp(r'p=([A-Za-z0-9+/=]+)').firstMatch(body);
  return match?.group(1);
}

/// Whether a (possibly root-owned) file exists, checked with privileges.
Future<bool> _privFileExists(String path) async {
  final cmd = _priv('test', ['-f', path]);
  final res = await Process.run(cmd.first, cmd.skip(1).toList());
  return res.exitCode == 0;
}

/// Best-effort public IP detection: ask an external echo service, then fall
/// back to the primary outbound interface address.
Future<String?> _detectPublicIp() async {
  try {
    final res = await Process.run('curl', ['-s', '--max-time', '5', 'https://api.ipify.org']);
    final ip = (res.stdout as String? ?? '').trim();
    if (res.exitCode == 0 && _looksLikeIp(ip)) return ip;
  } catch (_) {}
  try {
    final res = await Process.run('sh', ['-c', "hostname -I | awk '{print \$1}'"]);
    final ip = (res.stdout as String? ?? '').trim();
    if (res.exitCode == 0 && _looksLikeIp(ip)) return ip;
  } catch (_) {}
  return null;
}

bool _looksLikeIp(String s) =>
    RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(s) || s.contains(':');

// ── Service management ───────────────────────────────────────────────────────

Future<void> _service(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: gisila-agent service <action> [flags]');
    exitCode = 64;
    return;
  }

  final action = args.first;
  final rest = args.sublist(1);

  final parser = ArgParser()
    ..addOption('type',
        help: 'Service type (redis|memcached|smtp|mailpit|postfix|dovecot)')
    ..addOption('config', help: 'JSON config string');
  final r = parser.parse(rest);

  final type = r['type'] as String?;
  if (type == null) throw ArgumentError('--type is required');

  final rawConfig = r['config'] as String?;
  final config = rawConfig != null
      ? (jsonDecode(rawConfig) as Map<String, dynamic>)
      : <String, dynamic>{};

  switch (action) {
    case 'install':
      await _serviceInstall(type, config);
    case 'configure':
      await _serviceConfigure(type, config);
    case 'start':
      await _serviceCtl('start', type);
    case 'stop':
      await _serviceCtl('stop', type);
    case 'uninstall':
      await _serviceUninstall(type);
    default:
      throw ArgumentError('Unknown service action: $action');
  }
}

Future<void> _serviceInstall(String type, Map<String, dynamic> config) async {
  // Map service type to apt package name (or download URL for binary services).
  final packages = {
    'pgbouncer': 'pgbouncer',
  };
  final pkg = packages[type];
  const handledTypes = {'mailpit', 'postfix', 'dovecot', 'redis', 'memcached'};
  if (pkg == null && !handledTypes.contains(type)) {
    // smtp and other config-only services — nothing to install on the host.
    stdout.writeln('Service $type is config-only — nothing to install.');
    return;
  }

  // Redis and Memcached run as *dedicated* gisila-managed systemd instances so
  // they never reconfigure or remove the panel's own system services (the panel
  // runs its job queue on the distro redis-server.service at :6379).
  if (type == 'redis') {
    await _installRedisInstance(config);
    return;
  }
  if (type == 'memcached') {
    await _installMemcachedInstance(config);
    return;
  }

  if (type == 'mailpit') {
    await _installMailpit(config);
    return;
  }

  if (type == 'postfix') {
    await _aptInstall(['postfix', 'libsasl2-modules']);
    await _serviceConfigure(type, config);
    await _serviceCtl('enable', 'postfix');
    await _serviceCtl('start', 'postfix');
    return;
  }

  if (type == 'dovecot') {
    final protos = (config['protocols'] as String? ?? 'imap').trim();
    final pkgs = ['dovecot-core'];
    if (protos.contains('imap')) pkgs.add('dovecot-imapd');
    if (protos.contains('pop3')) pkgs.add('dovecot-pop3d');
    await _aptInstall(pkgs);
    await _serviceConfigure(type, config);
    await _serviceCtl('enable', 'dovecot');
    await _serviceCtl('start', 'dovecot');
    return;
  }

  // apt install (pgbouncer — its own dedicated service, safe to manage directly).
  await _aptInstall([pkg!]);
  await _serviceConfigure(type, config);
  await _serviceCtl('enable', type);
  await _serviceCtl('start', type);
}

// ── Dedicated managed instances (Redis / Memcached) ──────────────────────────
//
// The panel itself runs on the distro `redis-server.service` (port 6379, no
// password) installed by infra/install.sh. A managed Redis/Memcached service
// must therefore be a *separate* systemd unit + config + data dir so that
// configuring — or uninstalling — it can never disturb the panel's own queue.

const String _kRedisConf = '/etc/redis/gisila-redis.conf';
const String _kRedisDataDir = '/var/lib/gisila-redis';
const String _kRedisUnitFile = '/etc/systemd/system/gisila-redis.service';
const String _kMemcachedUnitFile =
    '/etc/systemd/system/gisila-memcached.service';

/// Return [v] as a bare integer string, or [fallback] when it is not a clean
/// integer. Used for values injected into a systemd ExecStart line.
String _intField(Object? v, String fallback) {
  final s = (v ?? '').toString().trim();
  return RegExp(r'^\d+$').hasMatch(s) ? s : fallback;
}

/// Strip CR/LF from a value destined for a single redis.conf line so it cannot
/// inject extra directives.
String _redisVal(Object? v, String fallback) {
  final s = (v ?? '').toString().replaceAll(RegExp(r'[\r\n]'), '').trim();
  return s.isEmpty ? fallback : s;
}

Future<void> _installRedisInstance(Map<String, dynamic> config) async {
  // We only need the redis-server *binary*; apt install is idempotent and does
  // not disturb the panel's own running instance.
  await _aptInstall(['redis-server']);
  // Dedicated data dir owned by the redis user (AOF / RDB land here).
  await _sudo('install',
      ['-d', '-o', 'redis', '-g', 'redis', '-m', '0750', _kRedisDataDir]);
  await _writeFileSudo(_kRedisUnitFile, _redisUnit());
  await _serviceCtl('daemon-reload', 'redis');
  await _serviceCtl('enable', 'redis'); // → gisila-redis
  // Writes gisila-redis.conf and (re)starts the unit.
  await _serviceConfigure('redis', config);
}

String _redisUnit() => '''
[Unit]
Description=Gisila managed Redis instance
After=network.target

[Service]
Type=notify
ExecStart=/usr/bin/redis-server $_kRedisConf
User=redis
Group=redis
RuntimeDirectory=gisila-redis
RuntimeDirectoryMode=0750
Restart=on-failure
UMask=007

[Install]
WantedBy=multi-user.target
''';

Future<void> _installMemcachedInstance(Map<String, dynamic> config) async {
  await _aptInstall(['memcached']);
  // The packaged memcached.service would otherwise hold the default port; the
  // panel manages its own gisila-memcached unit instead.
  await _sudo('systemctl', ['disable', '--now', 'memcached'], failOk: true);
  await _writeMemcachedUnit(config);
  await _serviceCtl('daemon-reload', 'memcached');
  await _serviceCtl('enable', 'memcached'); // → gisila-memcached
  await _serviceCtl('restart', 'memcached');
}

Future<void> _writeMemcachedUnit(Map<String, dynamic> config) async {
  final port = _intField(config['port'], '11211');
  final mem = _intField(config['memory_mb'], '64');
  final conn = _intField(config['connections'], '1024');
  final unit = '''
[Unit]
Description=Gisila managed Memcached instance
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/memcached -l 127.0.0.1 -p $port -m $mem -c $conn -u memcache
User=memcache
Group=memcache
Restart=on-failure

[Install]
WantedBy=multi-user.target
''';
  await _writeFileSudo(_kMemcachedUnitFile, unit);
}

Future<void> _serviceConfigure(String type, Map<String, dynamic> config) async {
  switch (type) {
    case 'redis':
      // Writes the *managed* instance config — NOT /etc/redis/redis.conf, which
      // belongs to the panel's own queue. `supervised systemd` + an explicit
      // data dir are required for the gisila-redis unit (Type=notify) to start.
      final lines = [
        'bind ${_redisVal(config['bind'], '127.0.0.1')}',
        'port ${_intField(config['port'], '6380')}',
        'dir $_kRedisDataDir',
        'supervised systemd',
        'daemonize no',
        if ((config['maxmemory'] as String?)?.isNotEmpty ?? false)
          'maxmemory ${_redisVal(config['maxmemory'], '')}',
        'maxmemory-policy ${_redisVal(config['maxmemory_policy'], 'allkeys-lru')}',
        if ((config['password'] as String?)?.isNotEmpty ?? false)
          'requirepass ${_redisVal(config['password'], '')}',
        'appendonly ${config['appendonly'] == 'false' ? 'no' : 'yes'}',
      ];
      await _writeFileSudo(_kRedisConf, lines.join('\n') + '\n');
      await _serviceCtl('restart', 'redis'); // → gisila-redis (see _unitName)

    case 'memcached':
      // Regenerate the dedicated gisila-memcached unit (config lives on the
      // ExecStart line) and restart it. The distro memcached.service is left
      // disabled so it never contends for the port.
      await _writeMemcachedUnit(config);
      await _serviceCtl('daemon-reload', 'memcached');
      await _serviceCtl('restart', 'memcached'); // → gisila-memcached

    case 'pgbouncer':
      await _configurePgbouncer(config);

    case 'smtp':
      // SMTP is config-only — no host config files, just stored credentials.
      stdout
          .writeln('SMTP relay configuration saved (no host changes needed).');

    case 'postfix':
      await _configurePostfix(config);

    case 'dovecot':
      await _configureDovecot(config);

    case 'mailpit':
      final smtpPort = config['smtp_port'] ?? '1025';
      final uiPort = config['ui_port'] ?? '8025';
      final maxMsg = config['max_messages'] ?? '500';
      final isDocker = Platform.environment['DOCKER_DEPLOY'] == 'true';
      if (isDocker) {
        // In Docker, use supervisord instead of systemd.
        const supervisorConf = '/etc/supervisor/conf.d/mailpit.conf';
        const supervisorDir = '/etc/supervisor/conf.d';
        await _sudo('mkdir', ['-p', supervisorDir]);
        await _writeFileSudo(supervisorConf, '''
[program:mailpit]
command=/usr/local/bin/mailpit --smtp 0.0.0.0:$smtpPort --listen 0.0.0.0:$uiPort --max $maxMsg
autostart=true
autorestart=true
stdout_logfile=/var/log/mailpit.log
stderr_logfile=/var/log/mailpit.err
''');
        await _sudo('supervisorctl', ['update'], failOk: true);
        await _sudo('supervisorctl', ['restart', 'mailpit'], failOk: true);
      } else {
        const unitContent = r'''
[Unit]
Description=Mailpit — local email capture
After=network.target

[Service]
ExecStart=/usr/local/bin/mailpit \
  --smtp 0.0.0.0:SMTP_PORT \
  --listen 0.0.0.0:UI_PORT \
  --max MESSAGES
Restart=on-failure

[Install]
WantedBy=multi-user.target
''';
        final unit = unitContent
            .replaceAll('SMTP_PORT', smtpPort)
            .replaceAll('UI_PORT', uiPort)
            .replaceAll('MESSAGES', maxMsg);
        await _writeFileSudo('/etc/systemd/system/mailpit.service', unit);
        await _serviceCtl('daemon-reload', 'mailpit');
        await _serviceCtl('restart', 'mailpit');
      }
  }
}

/// Write `/etc/pgbouncer/pgbouncer.ini` + `userlist.txt` from the panel config
/// and restart the pooler. `databases` and `users` arrive as JSON strings inside
/// the flat config blob (edited by the dedicated PgBouncer panel).
Future<void> _configurePgbouncer(Map<String, dynamic> config) async {
  List<dynamic> decodeList(String key) {
    final raw = config[key];
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw is String ? raw : jsonEncode(raw));
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  // Reject characters that would break out of an ini line / userlist entry.
  String tokenField(String label, String? v, {bool allowEmpty = false}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) {
      if (allowEmpty) return '';
      throw ArgumentError('pgbouncer: $label is required');
    }
    if (RegExp('[\n\r" ]').hasMatch(s)) {
      throw ArgumentError('pgbouncer: invalid characters in $label');
    }
    return s;
  }

  String numField(String label, String? v, String dflt) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return dflt;
    if (!RegExp(r'^\d+$').hasMatch(s)) {
      throw ArgumentError('pgbouncer: $label must be a number');
    }
    return s;
  }

  // [databases] — one connection-string line per upstream pool.
  final dbLines = <String>[];
  for (final d in decodeList('databases')) {
    if (d is! Map) continue;
    final name = tokenField('database name', d['name']?.toString());
    final host = tokenField('host', d['host']?.toString());
    final port = numField('port', d['port']?.toString(), '5432');
    final dbname = tokenField('dbname', d['dbname']?.toString());
    final parts = <String>['host=$host', 'port=$port', 'dbname=$dbname'];
    final user = (d['user']?.toString() ?? '').trim();
    if (user.isNotEmpty) parts.add('user=${tokenField('user', user)}');
    final pass = (d['password']?.toString() ?? '').trim();
    if (pass.isNotEmpty) {
      if (RegExp('[\\s" ]').hasMatch(pass)) {
        throw ArgumentError('pgbouncer: invalid characters in db password');
      }
      parts.add('password=$pass');
    }
    final poolSize =
        (d['pool_size']?.toString() ?? d['poolSize']?.toString() ?? '').trim();
    if (poolSize.isNotEmpty) {
      parts.add('pool_size=${numField('pool_size', poolSize, '0')}');
    }
    dbLines.add('$name = ${parts.join(' ')}');
  }

  // userlist.txt — `"user" "password"` with embedded quotes doubled.
  final userLines = <String>[];
  final userNames = <String>[];
  for (final u in decodeList('users')) {
    if (u is! Map) continue;
    final name = tokenField('username', u['username']?.toString());
    final pass = u['password']?.toString() ?? '';
    userNames.add(name);
    userLines.add('"${name.replaceAll('"', '""')}" '
        '"${pass.replaceAll('"', '""')}"');
  }

  final listenAddr =
      tokenField('listen_addr', config['listen_addr']?.toString(), allowEmpty: true);
  final iniLines = <String>[
    '# Generated by gisila-agent — do not edit by hand.',
    '[databases]',
    ...dbLines,
    '',
    '[pgbouncer]',
    'listen_addr = ${listenAddr.isEmpty ? '127.0.0.1' : listenAddr}',
    'listen_port = ${numField('listen_port', config['listen_port']?.toString(), '6432')}',
    'auth_type = ${_pgbAuthType(config['auth_type']?.toString())}',
    'auth_file = /etc/pgbouncer/userlist.txt',
    'pool_mode = ${_pgbPoolMode(config['pool_mode']?.toString())}',
    'max_client_conn = ${numField('max_client_conn', config['max_client_conn']?.toString(), '1000')}',
    'default_pool_size = ${numField('default_pool_size', config['default_pool_size']?.toString(), '25')}',
    'min_pool_size = ${numField('min_pool_size', config['min_pool_size']?.toString(), '0')}',
    'reserve_pool_size = ${numField('reserve_pool_size', config['reserve_pool_size']?.toString(), '5')}',
    'max_db_connections = ${numField('max_db_connections', config['max_db_connections']?.toString(), '50')}',
    'max_user_connections = ${numField('max_user_connections', config['max_user_connections']?.toString(), '0')}',
    if (userNames.isNotEmpty) 'admin_users = ${userNames.join(', ')}',
    if (userNames.isNotEmpty) 'stats_users = ${userNames.join(', ')}',
    'unix_socket_dir = /var/run/postgresql',
    'logfile = /var/log/postgresql/pgbouncer.log',
    'pidfile = /var/run/postgresql/pgbouncer.pid',
    'ignore_startup_parameters = extra_float_digits',
  ];

  await _sudo('mkdir', ['-p', '/etc/pgbouncer'], failOk: true);
  await _writeFileSudo(
      '/etc/pgbouncer/pgbouncer.ini', '${iniLines.join('\n')}\n');
  await _writeFileSudo('/etc/pgbouncer/userlist.txt',
      userLines.isEmpty ? '' : '${userLines.join('\n')}\n');

  // pgbouncer runs as the `postgres` user on Debian and must read both files.
  for (final f in const [
    '/etc/pgbouncer/pgbouncer.ini',
    '/etc/pgbouncer/userlist.txt',
  ]) {
    await _sudo('chown', ['postgres:postgres', f], failOk: true);
    await _sudo('chmod', ['640', f], failOk: true);
  }

  await _serviceCtl('restart', 'pgbouncer');
}

String _pgbAuthType(String? v) {
  const allowed = {'scram-sha-256', 'md5', 'trust'};
  final s = (v ?? '').trim();
  return allowed.contains(s) ? s : 'scram-sha-256';
}

String _pgbPoolMode(String? v) {
  const allowed = {'transaction', 'session', 'statement'};
  final s = (v ?? '').trim();
  return allowed.contains(s) ? s : 'transaction';
}

Future<void> _configurePostfix(Map<String, dynamic> config) async {
  final mode = config['mode'] as String? ?? 'relay';
  final maxSizeMb =
      int.tryParse(config['max_message_size_mb']?.toString() ?? '25') ?? 25;
  final maxSizeBytes = maxSizeMb * 1024 * 1024;

  // Build the main.cf content.
  final lines = <String>[
    '# Generated by gisila-agent — do not edit manually.',
    'smtpd_banner = \$myhostname ESMTP',
    'biff = no',
    'append_dot_mydomain = no',
    'readme_directory = no',
    'message_size_limit = $maxSizeBytes',
    'compatibility_level = 3.6',
    '',
    '# TLS.',
    if ((config['tls_cert'] as String?)?.isNotEmpty ?? false) ...[
      'smtpd_tls_cert_file = ${config['tls_cert']}',
      'smtpd_tls_key_file = ${config['tls_key'] ?? ''}',
      'smtpd_tls_security_level = may',
      'smtp_tls_security_level = may',
      'smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache',
      'smtp_tls_session_cache_database  = btree:\${data_directory}/smtp_scache',
    ],
  ];

  if (mode == 'relay') {
    final relayHost = config['relay_host'] as String? ?? '';
    final relayUser = config['relay_username'] as String? ?? '';
    final relayPass = config['relay_password'] as String? ?? '';
    lines.addAll([
      '',
      '# Relay mode.',
      'myhostname = localhost',
      'myorigin = \$myhostname',
      'relayhost = $relayHost',
      'mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128',
      'smtp_sasl_auth_enable = yes',
      'smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd',
      'smtp_sasl_security_options = noanonymous',
    ]);
    if (relayHost.isNotEmpty && relayUser.isNotEmpty) {
      await _writeFileSudo(
          '/etc/postfix/sasl_passwd', '$relayHost $relayUser:$relayPass\n');
      await _sudo('postmap', ['/etc/postfix/sasl_passwd']);
      await _sudo('chmod', ['600', '/etc/postfix/sasl_passwd']);
    }
  } else {
    // Standalone mode.
    lines.addAll([
      '',
      '# Standalone mode.',
      'myhostname = ${config['myhostname'] ?? 'mail.example.com'}',
      'mydomain = ${config['mydomain'] ?? 'example.com'}',
      'myorigin = \$mydomain',
      'mydestination = \$myhostname, localhost.\$mydomain, \$mydomain',
      'relayhost =',
      'mynetworks = ${config['mynetworks'] ?? '127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128'}',
      'home_mailbox = Maildir/',
      'smtpd_sasl_type = dovecot',
      'smtpd_sasl_path = private/auth',
      'smtpd_sasl_auth_enable = yes',
      'smtpd_recipient_restrictions = '
          'permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination',
    ]);
  }

  await _writeFileSudo('/etc/postfix/main.cf', lines.join('\n') + '\n');
  await _serviceCtl('reload-or-restart', 'postfix');
}

Future<void> _configureDovecot(Map<String, dynamic> config) async {
  final protocols = config['protocols'] as String? ?? 'imap';
  final mailLocation =
      config['mail_location'] as String? ?? 'maildir:~/Maildir';
  final authMechanisms = config['auth_mechanisms'] as String? ?? 'plain login';
  final disablePlaintext = config['disable_plaintext_auth'] != 'false';
  final imapPort = config['imap_port'] as String? ?? '143';
  final imapsPort = config['imaps_port'] as String? ?? '993';
  final pop3Port = config['pop3_port'] as String? ?? '110';
  final pop3sPort = config['pop3s_port'] as String? ?? '995';
  final cert = config['tls_cert'] as String? ?? '';
  final key = config['tls_key'] as String? ?? '';

  final conf = '''
# Generated by gisila-agent — do not edit manually.
protocols = $protocols
mail_location = $mailLocation
disable_plaintext_auth = ${disablePlaintext ? 'yes' : 'no'}
auth_mechanisms = $authMechanisms

ssl = ${cert.isNotEmpty ? 'required' : 'no'}
${cert.isNotEmpty ? 'ssl_cert = <$cert' : '# ssl_cert ='}
${key.isNotEmpty ? 'ssl_key  = <$key' : '# ssl_key  ='}

# Listeners.
service imap-login {
  inet_listener imap  { port = $imapPort; }
  inet_listener imaps { port = $imapsPort; ssl = yes; }
}
service pop3-login {
  inet_listener pop3  { port = $pop3Port; }
  inet_listener pop3s { port = $pop3sPort; ssl = yes; }
}

# Postfix SASL socket (needed when postfix mode=standalone).
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
''';

  await _writeFileSudo('/etc/dovecot/local.conf', conf);
  // local.conf is included automatically when it exists in newer dovecot.
  // Ensure the include is in dovecot.conf.
  final dovecotConfPath = '/etc/dovecot/dovecot.conf';
  final catCmd = _priv('cat', [dovecotConfPath]);
  final catResult = await Process.run(catCmd.first, catCmd.skip(1).toList());
  final existing = catResult.stdout.toString();
  if (!existing.contains('!include local.conf')) {
    await _writeFileSudo(dovecotConfPath, '$existing\n!include local.conf\n');
  }
  await _serviceCtl('reload-or-restart', 'dovecot');
}

/// Manage a system service, routing to the right init system.
///
/// In Docker (`DOCKER_DEPLOY=true`) systemd is not available:
///   - daemon-reload / enable / disable → no-op
///   - start / stop / restart / reload-or-restart → `service <unit> <cmd>`
///
/// On a bare-metal host the normal `systemctl` path is used.
Future<void> _serviceCtl(String action, String type) async {
  final isDocker = Platform.environment['DOCKER_DEPLOY'] == 'true';
  final unitName = _unitName(type);

  if (isDocker) {
    const noOps = {'daemon-reload', 'enable', 'disable'};
    if (noOps.contains(action)) return;
    // SysV shim: `service <unit> restart` etc.
    final svcAction = action == 'reload-or-restart' ? 'restart' : action;
    await _sudo('service', [unitName, svcAction], failOk: true);
  } else {
    if (action == 'daemon-reload') {
      await _sudo('systemctl', ['daemon-reload']);
    } else {
      await _sudo('systemctl', [action, unitName]);
    }
  }
}

Future<void> _serviceUninstall(String type) async {
  try {
    await _serviceCtl('stop', type);
  } catch (_) {}
  try {
    await _serviceCtl('disable', type);
  } catch (_) {}

  switch (type) {
    case 'redis':
      // Remove ONLY the managed instance — never the redis-server package,
      // which the panel's own queue depends on.
      await _sudo('rm', ['-f', _kRedisUnitFile], failOk: true);
      await _sudo('rm', ['-f', _kRedisConf], failOk: true);
      await _sudo('rm', ['-rf', _kRedisDataDir], failOk: true);
      await _serviceCtl('daemon-reload', 'redis');
    case 'memcached':
      // Drop the dedicated unit; leave the memcached package in place.
      await _sudo('rm', ['-f', _kMemcachedUnitFile], failOk: true);
      await _serviceCtl('daemon-reload', 'memcached');
    case 'pgbouncer':
      await _sudo('apt-get', ['-qq', '-y', 'remove', '--purge', 'pgbouncer']);
      await _sudo('rm', ['-rf', '/etc/pgbouncer'], failOk: true);
    case 'mailpit':
      await _sudo('rm', ['-f', '/usr/local/bin/mailpit'], failOk: true);
      final isDocker = Platform.environment['DOCKER_DEPLOY'] == 'true';
      if (isDocker) {
        await _sudo('rm', ['-f', '/etc/supervisor/conf.d/mailpit.conf'],
            failOk: true);
        await _sudo('supervisorctl', ['update'], failOk: true);
      } else {
        await _sudo('rm', ['-f', '/etc/systemd/system/mailpit.service'],
            failOk: true);
        await _serviceCtl('daemon-reload', 'mailpit');
      }
    case 'smtp':
      // Nothing to remove for config-only services.
      break;
  }
}

Future<void> _installMailpit(Map<String, dynamic> config) async {
  // Download the latest mailpit binary (requires root to install to /usr/local/bin).
  await _sudo('sh', [
    '-c',
    'curl -sL https://raw.githubusercontent.com/axllent/mailpit/develop/install.sh | bash',
  ]);
  await _serviceConfigure('mailpit', config);
  await _serviceCtl('enable', 'mailpit');
  await _serviceCtl('start', 'mailpit');
}

String _unitName(String type) => switch (type) {
      // Managed Redis/Memcached run as dedicated gisila-* units, never the
      // distro redis-server.service / memcached.service.
      'redis' => 'gisila-redis',
      'memcached' => 'gisila-memcached',
      _ => type,
    };

Future<void> _run(String exe, List<String> args, {bool failOk = false}) async {
  final result = await Process.run(exe, args);
  if (result.exitCode != 0 && !failOk) {
    throw Exception(
        '$exe ${args.join(' ')}: exit ${result.exitCode}\n${result.stderr}');
  }
}

/// Whether the agent is already running as root (uid 0).
///
/// When true we must NOT use `sudo`: the worker now launches the agent directly
/// as root, and many VPS / container hosts enforce the kernel-level
/// `no_new_privileges` flag which blocks `sudo` even for root with
/// "The 'no new privileges' flag is set, which prevents sudo from running as
/// root." Running the underlying command directly avoids that entirely.
final bool _isRoot = () {
  try {
    final r = Process.runSync('id', ['-u']);
    return r.exitCode == 0 && (r.stdout as String).trim() == '0';
  } catch (_) {
    return false;
  }
}();

/// Build a command list, prepending `sudo` only when not already root.
List<String> _priv(String exe, List<String> args) =>
    _isRoot ? [exe, ...args] : ['sudo', exe, ...args];

/// Run a privileged command — directly when root, otherwise via sudo.
Future<void> _sudo(String exe, List<String> args, {bool failOk = false}) {
  final cmd = _priv(exe, args);
  return _run(cmd.first, cmd.skip(1).toList(), failOk: failOk);
}

/// Install one or more apt packages non-interactively.
///
/// `DEBIAN_FRONTEND=noninteractive` plus the dpkg conffile flags prevent any
/// package from blocking on a debconf prompt — most importantly Postfix, whose
/// "General type of mail configuration" dialog would otherwise hang the whole
/// install (and therefore the mail sync) forever on a headless host.
Future<void> _aptInstall(List<String> packages) async {
  if (packages.contains('postfix')) {
    // Preseed Postfix so its installer never opens the interactive dialog.
    await _debconfSet('postfix postfix/main_mailer_type select Internet Site');
    await _debconfSet('postfix postfix/mailname string ${_systemMailname()}');
  }
  final cmd = _priv('sh', [
    '-c',
    'DEBIAN_FRONTEND=noninteractive apt-get -qq -y '
        '-o Dpkg::Options::=--force-confdef '
        '-o Dpkg::Options::=--force-confold '
        'install ${packages.join(' ')}',
  ]);
  await _run(cmd.first, cmd.skip(1).toList());
}

/// Feed a single debconf selection line to `debconf-set-selections`.
Future<void> _debconfSet(String selection) async {
  final escaped = selection.replaceAll("'", r"'\''");
  final cmd = _priv('sh', ['-c', "echo '$escaped' | debconf-set-selections"]);
  await _run(cmd.first, cmd.skip(1).toList(), failOk: true);
}

/// The system mail name used to preseed Postfix. Falls back to the hostname.
String _systemMailname() {
  try {
    final r = Process.runSync('hostname', ['-f']);
    final name = (r.stdout as String).trim();
    if (r.exitCode == 0 && name.isNotEmpty) return name;
  } catch (_) {}
  try {
    final r = Process.runSync('hostname', []);
    final name = (r.stdout as String).trim();
    if (name.isNotEmpty) return name;
  } catch (_) {}
  return 'localhost';
}

/// Write [content] to a privileged [path] using `tee` (via sudo when needed).
Future<void> _writeFileSudo(String path, String content) async {
  final cmd = _priv('tee', [path]);
  final proc = await Process.start(cmd.first, cmd.skip(1).toList());
  proc.stdin.write(content);
  await proc.stdin.close();
  // tee echoes to stdout — drain it so the process can finish.
  await proc.stdout.drain<void>();
  final exit = await proc.exitCode;
  if (exit != 0) throw Exception('tee $path failed with exit $exit');
}

// =============================================================================
// postgres subcommand
// =============================================================================

Future<void> _postgres(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: gisila-agent postgres <subcommand> [options]\n'
        'Subcommands: install-instance | uninstall-instance | '
        'start-instance | stop-instance | create-db | drop-db | '
        'backup | restore');
    exitCode = 64;
    return;
  }

  final sub = args.first;
  final parser = ArgParser()
    ..addOption('version', abbr: 'v', help: 'Postgres major version (e.g. 16)')
    ..addOption('port', help: 'Port to run this instance on')
    ..addOption('db', help: 'Database name')
    ..addOption('role', help: 'Role / user name')
    ..addOption('password', help: 'Role password')
    ..addOption('extensions',
        help: 'Comma-separated extension names to CREATE EXTENSION')
    ..addOption('settings',
        help: 'JSON object of postgresql.conf settings to ALTER SYSTEM SET')
    ..addOption('output', help: 'Backup destination path (.sql.gz)')
    ..addOption('input', help: 'Backup source path to restore (.sql or .sql.gz)')
    ..addOption('scope', help: 'Backup scope: full | schema | data');

  final opts = parser.parse(args.sublist(1));
  final version = int.tryParse(opts['version'] as String? ?? '');

  switch (sub) {
    case 'install-instance':
      if (version == null) throw ArgumentError('--version required');
      final port =
          int.tryParse(opts['port'] as String? ?? '') ?? (5400 + version);
      await _pgInstallInstance(version, port);

    case 'uninstall-instance':
      if (version == null) throw ArgumentError('--version required');
      await _pgUninstallInstance(version);

    case 'start-instance':
      if (version == null) throw ArgumentError('--version required');
      await _sudo('systemctl', ['start', 'postgresql@$version-main']);

    case 'stop-instance':
      if (version == null) throw ArgumentError('--version required');
      await _sudo('systemctl', ['stop', 'postgresql@$version-main']);

    case 'create-db':
      if (version == null) throw ArgumentError('--version required');
      final db = opts['db'] as String? ?? '';
      final role = opts['role'] as String? ?? '';
      final pass = opts['password'] as String? ?? '';
      if (db.isEmpty || role.isEmpty || pass.isEmpty) {
        throw ArgumentError('--db, --role and --password required');
      }
      final exts = (opts['extensions'] as String? ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await _pgCreateDatabase(version, db, role, pass, exts);

    case 'drop-db':
      if (version == null) throw ArgumentError('--version required');
      final db = opts['db'] as String? ?? '';
      final role = opts['role'] as String? ?? '';
      if (db.isEmpty || role.isEmpty) {
        throw ArgumentError('--db and --role required');
      }
      await _pgDropDatabase(version, db, role);

    case 'ensure-monitor':
      if (version == null) throw ArgumentError('--version required');
      final port = int.tryParse(opts['port'] as String? ?? '') ?? (5400 + version);
      final pass = opts['password'] as String? ?? '';
      if (pass.isEmpty) throw ArgumentError('--password required');
      await _pgEnsureMonitor(version, port, pass);

    case 'configure':
      if (version == null) throw ArgumentError('--version required');
      final port = int.tryParse(opts['port'] as String? ?? '') ?? (5400 + version);
      await _pgConfigure(version, port, opts['settings'] as String? ?? '{}');

    case 'backup':
      if (version == null) throw ArgumentError('--version required');
      final db = opts['db'] as String? ?? '';
      final output = opts['output'] as String? ?? '';
      if (db.isEmpty || output.isEmpty) {
        throw ArgumentError('--db and --output required');
      }
      await _pgBackup(version, db, output, opts['scope'] as String? ?? 'full');

    case 'restore':
      if (version == null) throw ArgumentError('--version required');
      final db = opts['db'] as String? ?? '';
      final input = opts['input'] as String? ?? '';
      if (db.isEmpty || input.isEmpty) {
        throw ArgumentError('--db and --input required');
      }
      await _pgRestore(version, db, input);

    default:
      throw ArgumentError('Unknown postgres subcommand: $sub');
  }
}

/// Install PostgreSQL from the official pgdg apt repository.
Future<void> _pgInstallInstance(int version, int port) async {
  // 1. Add pgdg repo if the signing key is missing.
  final keyFile = File('/etc/apt/keyrings/pgdg.gpg');
  if (!keyFile.existsSync()) {
    await _sudo('mkdir', ['-p', '/etc/apt/keyrings']);
    // Download and de-armour the pgdg signing key.
    final keyResult = await Process.run('curl', [
      '-fsSL',
      'https://www.postgresql.org/media/keys/ACCC4CF8.asc',
    ]);
    if (keyResult.exitCode != 0) {
      throw Exception('Failed to download pgdg key: ${keyResult.stderr}');
    }
    // gpg --dearmor writes binary to stdout; pipe into the keyring file.
    final gpgCmd =
        _priv('gpg', ['--dearmor', '-o', '/etc/apt/keyrings/pgdg.gpg']);
    final gpgProc =
        await Process.start(gpgCmd.first, gpgCmd.skip(1).toList());
    gpgProc.stdin.write(keyResult.stdout);
    await gpgProc.stdin.close();
    await gpgProc.stdout.drain<void>();
    final gpgExit = await gpgProc.exitCode;
    if (gpgExit != 0) throw Exception('gpg --dearmor failed');
  }

  // 2. Add pgdg source list.
  final sourceFile = File('/etc/apt/sources.list.d/pgdg.list');
  if (!sourceFile.existsSync()) {
    final os =
        (await Process.run('lsb_release', ['-cs'])).stdout.toString().trim();
    await _writeFileSudo(
        '/etc/apt/sources.list.d/pgdg.list',
        'deb [signed-by=/etc/apt/keyrings/pgdg.gpg] '
            'https://apt.postgresql.org/pub/repos/apt $os-pgdg main\n');
  }

  await _sudo('apt-get', ['update', '-qq']);
  await _aptInstall(['postgresql-$version']);

  // 3. Ensure the "$version/main" cluster exists.
  //
  // Installing the apt package does NOT reliably auto-create a cluster (e.g.
  // when other PostgreSQL versions are already present on the host — only the
  // first-installed version gets a "main" cluster). The systemd unit
  // `postgresql@$version-main.service` carries
  // `AssertPathExists=/etc/postgresql/$version/main/postgresql.conf`, so it
  // aborts with "Assertion failed on job" when the cluster is missing.
  // Create it explicitly on the requested port. Without `--start`,
  // pg_createcluster only lays down the config; the systemctl restart below
  // brings it online.
  final confPath = '/etc/postgresql/$version/main/postgresql.conf';
  if (!File(confPath).existsSync()) {
    await _sudo('pg_createcluster', ['$version', 'main', '-p', '$port']);
  }

  // 4. Configure port in postgresql.conf (enforce it even if the cluster
  // already existed on a different port).
  final conf = File(confPath);
  if (conf.existsSync()) {
    var content = await conf.readAsString();
    // Replace or append the port line.
    if (content.contains(RegExp(r'^port\s*=', multiLine: true))) {
      content = content.replaceAll(
          RegExp(r'^port\s*=.*$', multiLine: true), 'port = $port');
    } else {
      content += '\nport = $port\n';
    }
    await _writeFileSudo(confPath, content);
  }

  // 5. Enable + start the versioned service unit.
  await _sudo('systemctl', ['enable', 'postgresql@$version-main']);
  await _sudo('systemctl', ['restart', 'postgresql@$version-main']);
}

Future<void> _pgUninstallInstance(int version) async {
  await _sudo('systemctl', ['stop', 'postgresql@$version-main'], failOk: true);
  await _sudo('systemctl', ['disable', 'postgresql@$version-main'],
      failOk: true);
  await _sudo('apt-get', ['-y', 'remove', '--purge', 'postgresql-$version'],
      failOk: true);
  await _sudo(
      'rm', ['-rf', '/etc/postgresql/$version', '/var/lib/postgresql/$version'],
      failOk: true);
}

/// Create a Postgres role + database and optionally install extensions.
Future<void> _pgCreateDatabase(
  int version,
  String dbName,
  String role,
  String password,
  List<String> extensions,
) async {
  // Use `psql -p <port>` for the correct instance.
  final pgBin = '/usr/lib/postgresql/$version/bin/psql';

  Future<void> sql(String statement) =>
      _runAs('postgres', [pgBin, '-p', '${5400 + version}', '-c', statement]);

  // Idempotent role creation.
  await sql("DO \$\$ BEGIN "
      "IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$role') THEN "
      "CREATE ROLE $role WITH LOGIN PASSWORD '$password'; "
      "END IF; END \$\$;");
  // Idempotent database creation.
  await sql("SELECT 'CREATE DATABASE $dbName OWNER $role' "
      "WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$dbName')\\gexec");

  // Grant all privileges.
  await sql("GRANT ALL PRIVILEGES ON DATABASE $dbName TO $role;");

  // Install extensions (must connect to the target db).
  for (final ext in extensions) {
    await _runAs('postgres', [
      pgBin,
      '-p',
      '${5400 + version}',
      '-d',
      dbName,
      '-c',
      'CREATE EXTENSION IF NOT EXISTS "$ext";',
    ]);
  }
}

/// Create or update the read-only `gisila_monitor` role used by the panel to
/// read pg_stat_* metrics. Idempotent. The password is always alphanumeric
/// (panel-generated) so it is safe to embed in the SQL literal.
Future<void> _pgEnsureMonitor(int version, int port, String password) async {
  final pgBin = '/usr/lib/postgresql/$version/bin/psql';
  Future<void> sql(String statement) =>
      _runAs('postgres', [pgBin, '-p', '$port', '-c', statement]);

  await sql("DO \$\$ BEGIN "
      "IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'gisila_monitor') THEN "
      "ALTER ROLE gisila_monitor WITH LOGIN PASSWORD '$password'; "
      "ELSE "
      "CREATE ROLE gisila_monitor WITH LOGIN PASSWORD '$password'; "
      "END IF; END \$\$;");
  // pg_monitor (PG 10+) grants read access to pg_stat_* views.
  await sql('GRANT pg_monitor TO gisila_monitor;');
}

/// Apply tunable settings via `ALTER SYSTEM SET` then restart the cluster so
/// restart-only settings (max_connections, shared_buffers, …) take effect.
Future<void> _pgConfigure(int version, int port, String settingsJson) async {
  final pgBin = '/usr/lib/postgresql/$version/bin/psql';
  final settings = jsonDecode(settingsJson) as Map<String, dynamic>;
  final keyRe = RegExp(r'^[a-z_][a-z0-9_]*$');

  Future<void> sql(String statement) =>
      _runAs('postgres', [pgBin, '-p', '$port', '-c', statement]);

  for (final entry in settings.entries) {
    final key = entry.key;
    if (!keyRe.hasMatch(key)) {
      throw ArgumentError('Invalid setting key: $key');
    }
    final value = entry.value?.toString() ?? '';
    if (value.contains("'") || value.contains(r'\')) {
      throw ArgumentError('Invalid value for $key');
    }
    if (value.isEmpty) {
      await sql('ALTER SYSTEM RESET $key;');
    } else {
      await sql("ALTER SYSTEM SET $key = '$value';");
    }
  }

  await _sudo('systemctl', ['restart', 'postgresql@$version-main']);
}

Future<void> _pgDropDatabase(int version, String dbName, String role) async {
  final pgBin = '/usr/lib/postgresql/$version/bin/psql';

  Future<void> sql(String statement) =>
      _runAs('postgres', [pgBin, '-p', '${5400 + version}', '-c', statement]);

  // Terminate active connections then drop.
  await sql("SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
      "WHERE datname = '$dbName' AND pid <> pg_backend_pid();");
  await sql("DROP DATABASE IF EXISTS $dbName;");
  await sql("DROP ROLE IF EXISTS $role;");
}

/// Base directory for database backup artifacts. Owned by the unprivileged
/// `gisila` user so the API process can stream files for download and write
/// uploaded files for restore, while the root agent writes the dumps.
const _pgBackupBaseDir = '/var/lib/gisila/backups';
const _gisilaUser = 'gisila';

/// Single-quote a string for safe embedding in a `bash -c` command line.
String _shq(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// Run [db]'s `pg_dump` (scoped by [scope]) through gzip into [output].
///
/// The redirect runs in the root shell (so it can write into the gisila-owned
/// backups tree) while only `pg_dump` drops to the `postgres` user for peer
/// auth on the local socket. `set -o pipefail` ensures a pg_dump failure isn't
/// masked by gzip's success. Prints `{"sizeBytes": N}` on success.
Future<void> _pgBackup(
  int version,
  String dbName,
  String output,
  String scope,
) async {
  final dir = File(output).parent.path;
  await _sudo('mkdir', ['-p', dir]);

  final scopeFlag = switch (scope) {
    'schema' => '--schema-only ',
    'data' => '--data-only ',
    _ => '',
  };
  final pgDump = '/usr/lib/postgresql/$version/bin/pg_dump';
  final port = 5400 + version;
  final dropTo = _isRoot ? 'runuser -u postgres -- ' : 'sudo -u postgres ';

  final inner = 'set -o pipefail; '
      '$dropTo$pgDump -p $port ${scopeFlag}-d ${_shq(dbName)} '
      '| gzip -c > ${_shq(output)}';
  final cmd = _priv('bash', ['-c', inner]);
  final res = await Process.run(cmd.first, cmd.skip(1).toList());
  if (res.exitCode != 0) {
    throw Exception('pg_dump failed (${res.exitCode}): ${res.stderr}'.trim());
  }

  // Hand the whole tree to gisila so the API can read it for downloads.
  await _sudo('chown', ['-R', '$_gisilaUser:$_gisilaUser', _pgBackupBaseDir],
      failOk: true);
  await _sudo('chmod', ['640', output], failOk: true);

  final size = await File(output).length();
  stdout.writeln(jsonEncode({'sizeBytes': size}));
}

/// Restore [db] from a plain-SQL dump at [input] (`.sql` or `.sql.gz`).
///
/// Best-effort (ON_ERROR_STOP=0) so a full dump applied over an existing schema
/// still loads what it can; corruption is caught by pipefail on the decompressor.
Future<void> _pgRestore(int version, String dbName, String input) async {
  if (!await File(input).exists()) {
    throw Exception('Restore source not found: $input');
  }
  final psql = '/usr/lib/postgresql/$version/bin/psql';
  final port = 5400 + version;
  final dropTo = _isRoot ? 'runuser -u postgres -- ' : 'sudo -u postgres ';
  final decompress = input.endsWith('.gz') ? 'gunzip -c' : 'cat';

  final inner = 'set -o pipefail; '
      '$decompress ${_shq(input)} '
      '| $dropTo$psql -p $port -v ON_ERROR_STOP=0 -d ${_shq(dbName)}';
  final cmd = _priv('bash', ['-c', inner]);
  final res = await Process.run(cmd.first, cmd.skip(1).toList());
  if (res.exitCode != 0) {
    throw Exception('restore failed (${res.exitCode}): ${res.stderr}'.trim());
  }
}

/// Run a command as a different system user.
///
/// When already root we use `runuser -u <user> --` (util-linux) instead of
/// `sudo -u`: it drops privileges without invoking sudo, so it works even on
/// hosts that enforce the kernel `no_new_privileges` flag. When not root we
/// fall back to `sudo -u <user>`.
Future<void> _runAs(String user, List<String> command) async {
  final invocation = _isRoot
      ? ['runuser', '-u', user, '--', ...command]
      : ['sudo', '-u', user, ...command];
  final result =
      await Process.run(invocation.first, invocation.skip(1).toList());
  if (result.exitCode != 0) {
    throw Exception(
        '${command.first} exited ${result.exitCode}: ${result.stderr}');
  }
}

// =============================================================================
// python subcommand — pyenv version management
// =============================================================================

const _pyenvRoot = '/opt/pyenv';

Future<void> _pythonCmd(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: gisila-agent python <subcommand>\n'
        'Subcommands: install | uninstall | list | list-available');
    exitCode = 64;
    return;
  }

  final sub = args.first;

  switch (sub) {
    case 'install':
      final parser = ArgParser()
        ..addOption('version', abbr: 'v', mandatory: true);
      final opts = parser.parse(args.sublist(1));
      await _pyenvEnsureInstalled();
      await _pyenvInstallVersion(opts['version'] as String);

    case 'uninstall':
      final parser = ArgParser()
        ..addOption('version', abbr: 'v', mandatory: true);
      final opts = parser.parse(args.sublist(1));
      await _pyenvUninstallVersion(opts['version'] as String);

    case 'list':
      await _pyenvList();

    case 'list-available':
      await _pyenvListAvailable();

    default:
      throw ArgumentError('Unknown python subcommand: $sub');
  }
}

/// Bootstrap pyenv at [_pyenvRoot] if not present.
Future<void> _pyenvEnsureInstalled() async {
  if (Directory('$_pyenvRoot/bin').existsSync()) return;
  stdout.writeln('Installing pyenv at $_pyenvRoot…');
  await _run('git', [
    'clone',
    '--depth',
    '1',
    'https://github.com/pyenv/pyenv.git',
    _pyenvRoot,
  ]);
  // Compile the bash extension for speed (optional, failures are OK).
  await _run('bash', ['-c', 'cd $_pyenvRoot && src/configure && make -C src'],
      failOk: true);
  stdout.writeln('pyenv installed.');
}

/// Install a specific Python version.
Future<void> _pyenvInstallVersion(String version) async {
  final versionDir = '$_pyenvRoot/versions/$version';
  if (Directory(versionDir).existsSync()) {
    stdout.writeln('Python $version already installed at $versionDir.');
    return;
  }
  stdout.writeln('Installing Python $version via pyenv…');
  final env = {
    ...Platform.environment,
    'PYENV_ROOT': _pyenvRoot,
    'PATH':
        '$_pyenvRoot/bin:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
  };
  // pyenv needs build deps.
  await _aptInstall([
    'build-essential',
    'libssl-dev',
    'zlib1g-dev',
    'libbz2-dev',
    'libreadline-dev',
    'libsqlite3-dev',
    'libncursesw5-dev',
    'xz-utils',
    'tk-dev',
    'libxml2-dev',
    'libxmlsec1-dev',
    'libffi-dev',
    'liblzma-dev',
    'curl',
  ]);
  final result = await Process.run(
    '$_pyenvRoot/bin/pyenv',
    ['install', version],
    environment: env,
  );
  stdout.write(result.stdout);
  if (result.exitCode != 0) {
    throw Exception('pyenv install $version failed: ${result.stderr}');
  }
  stdout.writeln('Python $version installed.');
}

Future<void> _pyenvUninstallVersion(String version) async {
  final env = {
    ...Platform.environment,
    'PYENV_ROOT': _pyenvRoot,
    'PATH':
        '$_pyenvRoot/bin:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
  };
  final result = await Process.run(
    '$_pyenvRoot/bin/pyenv',
    ['uninstall', '-f', version],
    environment: env,
  );
  if (result.exitCode != 0) {
    throw Exception('pyenv uninstall $version failed: ${result.stderr}');
  }
  stdout.writeln('Python $version removed.');
}

/// Print JSON array of installed versions.
Future<void> _pyenvList() async {
  final versionsDir = Directory('$_pyenvRoot/versions');
  final versions = versionsDir.existsSync()
      ? versionsDir
          .listSync()
          .whereType<Directory>()
          .map((d) => d.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
          .toList()
      : <String>[];
  stdout.writeln(jsonEncode({'versions': versions}));
}

/// Print JSON array of installable versions (pyenv install --list).
Future<void> _pyenvListAvailable() async {
  if (!Directory('$_pyenvRoot/bin').existsSync()) {
    stdout.writeln(jsonEncode({'versions': []}));
    return;
  }
  final env = {
    ...Platform.environment,
    'PYENV_ROOT': _pyenvRoot,
    'PATH':
        '$_pyenvRoot/bin:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
  };
  final result = await Process.run(
    '$_pyenvRoot/bin/pyenv',
    ['install', '--list'],
    environment: env,
  );
  // Filter to CPython versions only (e.g. 3.10.14, 3.12.4).
  final re = RegExp(r'^\s*(3\.\d+\.\d+)\s*$', multiLine: true);
  final versions =
      re.allMatches(result.stdout.toString()).map((m) => m.group(1)!).toList();
  stdout.writeln(jsonEncode({'versions': versions}));
}

void _ok(Map<String, Object?> data) =>
    stdout.writeln(jsonEncode({'ok': true, ...data}));
void _err(Map<String, Object?> data) =>
    stdout.writeln(jsonEncode({'ok': false, ...data}));

void _usage() {
  stdout.writeln('''
gisila-agent — privileged host-side deployment agent.

Subcommands:
  provision     --app-id ID --user app_xxx --work-dir PATH --port N
  build         --app-id ID --user app_xxx --work-dir PATH \\
                --runtime RT --source-type SRC \\
                [--git-url URL] [--git-branch B] \\
                [--build-command CMD] [--artifact-path PATH]
  apply-unit    --app-id ID --user app_xxx --work-dir PATH --port N \\
                [--start-command CMD] [--env-json JSON] \\
                [--memory-mb MB] [--cpu-quota PCT] [--tasks-max N]
  apply-vhost   --app-id ID --port N [--hostname host …]
  issue-cert    --hostname HOSTNAME
  start|stop|restart  --user app_xxx
  uninstall     --user app_xxx [--app-id ID]
  logs          --user app_xxx [--work-dir PATH] [--lines N] [--follow]
  stat          --user app_xxx | --unit UNIT   (prints resource-usage JSON)
  exec          --user app_xxx --work-dir PATH --command CMD \\
                [--runtime RT] [--timeout SECONDS]
  service       install|configure|start|stop|uninstall \\
                --type redis|memcached|smtp|mailpit|postfix|dovecot [--config JSON]
  mail          setup
                sync --domains JSON --accounts JSON
                  (--domains: [{domain, hostname, selector, dmarc}],
                   emits {domains:{d:{selector,publicKey}}, publicIp} on stdout)
  postgres      install-instance --version VER [--port PORT]
                uninstall-instance --version VER
                start-instance|stop-instance --version VER
                create-db --version VER --db DB --role ROLE --password PASS
                          [--extensions ext1,ext2,…]
                drop-db   --version VER --db DB --role ROLE
                ensure-monitor --version VER --port PORT --password PASS
                configure --version VER --port PORT --settings JSON
''');
}
