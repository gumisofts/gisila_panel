import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:gisila_agent/runtime/applier.dart';
import 'package:gisila_agent/runtime/builders.dart';
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
    p.addOption('port', mandatory: true);
  });
  final user = AgentValidators.requireUser(r['user'] as String?);
  final workDir = AgentValidators.requireWorkDir(r['work-dir'] as String?);
  AgentValidators.requirePort(r['port'] as String?);
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
    // Python-specific
    p.addOption('python-version');
    p.addOption('wsgi-app');
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
          workDir: workDir, user: user, buildCommand: buildCommand);
      break;
    case 'go':
      await Builders.buildGo(
          workDir: workDir, user: user, buildCommand: buildCommand);
      break;
    case 'rust':
      await Builders.buildRust(
          workDir: workDir, user: user, buildCommand: buildCommand);
      break;
    case 'node':
    case 'bun':
      await Builders.buildNode(
          workDir: workDir, user: user, buildCommand: buildCommand);
      break;
    case 'python':
      await Builders.buildPython(
        workDir: workDir,
        user: user,
        buildCommand: buildCommand,
        pythonVersion: r['python-version'] as String?,
      );
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
    p.addOption('port', mandatory: true);
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
  });
  final appId = int.parse(r['app-id'] as String);
  final user = AgentValidators.requireUser(r['user'] as String?);
  final workDir = AgentValidators.requireWorkDir(r['work-dir'] as String?);
  final port = AgentValidators.requirePort(r['port'] as String?);
  final runtime = r['runtime'] as String;
  final isPython = runtime == 'python';

  String startCommand;
  if (r['start-command'] != null && (r['start-command'] as String).isNotEmpty) {
    startCommand =
        AgentValidators.optionalCommand(r['start-command'] as String)!;
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
  } else {
    startCommand = '$workDir/current/app';
  }

  final envJson = r['env-json'] as String;
  final envVars = (jsonDecode(envJson) as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, (v as String?) ?? ''));

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
    envVars: envVars,
  );
}

Future<void> _applyVhost(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('app-id', mandatory: true);
    p.addOption('port', mandatory: true);
    p.addMultiOption('hostname');
  });
  final appId = int.parse(r['app-id'] as String);
  final port = AgentValidators.requirePort(r['port'] as String?);
  final hostnames = (r['hostname'] as List<String>? ?? <String>[])
      .map(AgentValidators.requireHostname)
      .toList();
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
  });
  final user = AgentValidators.requireUser(r['user'] as String?);
  final applier = Applier();
  switch (action) {
    case 'start':
      await applier.start(user);
      break;
    case 'stop':
      await applier.stop(user);
      break;
    case 'restart':
      await applier.restart(user);
      break;
  }
}

Future<void> _uninstall(List<String> args) async {
  final r = _parse(args, (p) {
    p.addOption('user', mandatory: true);
    p.addOption('app-id');
  });
  final user = AgentValidators.requireUser(r['user'] as String?);
  final appId = int.tryParse((r['app-id'] as String?) ?? '');
  await Applier().uninstall(user, appId);
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
    p.addFlag('follow', defaultsTo: false);
  });
  final user = AgentValidators.requireUser(r['user'] as String?);
  final lines = r['lines'] as String;
  final follow = r['follow'] as bool;
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
    stderr.writeln('Usage: gisila-agent mail <setup|sync> [flags]');
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
    'smtpd_milters=inet:localhost:8891',
    'non_smtpd_milters=inet:localhost:8891',
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
  final dovecotConf = '''
# Generated by gisila-agent — virtual mailbox hosting. Do not edit by hand.
protocols = imap pop3 lmtp
mail_location = maildir:/var/mail/vhosts/%d/%n
mail_privileged_group = vmail
disable_plaintext_auth = no
auth_mechanisms = plain login

# TLS — self-signed cert by default; point these at a real cert in production.
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

service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
''';
  await _sudo('mkdir', ['-p', '/etc/dovecot/conf.d'], failOk: true);
  await _writeFileSudo('/etc/dovecot/conf.d/99-gisila-mail.conf', dovecotConf);

  // OpenDKIM base config + runtime dir. Per-domain key tables are written on
  // sync; this lays down the daemon configuration once.
  const opendkimConf = '''
# Generated by gisila-agent — do not edit by hand.
Syslog                  yes
UMask                   002
Mode                    sv
Canonicalization        relaxed/simple
Socket                  inet:8891@localhost
PidFile                 /run/opendkim/opendkim.pid
OversignHeaders         From
TrustedHostsFile        /etc/opendkim/TrustedHosts
KeyTable                /etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
UserID                  opendkim
''';
  await _sudo('mkdir', ['-p', '/etc/opendkim/keys'], failOk: true);
  await _sudo('mkdir', ['-p', '/run/opendkim'], failOk: true);
  await _sudo('chown', ['opendkim:opendkim', '/run/opendkim'], failOk: true);
  await _writeFileSudo('/etc/opendkim.conf', opendkimConf);
  await _writeFileSudo(
    '/etc/opendkim/TrustedHosts',
    '127.0.0.1\n::1\nlocalhost\n',
  );
  // Ensure the key/signing tables exist (empty until sync) so the daemon can
  // start even before any domain has been added.
  for (final f in <String>['/etc/opendkim/KeyTable', '/etc/opendkim/SigningTable']) {
    if (!await _privFileExists(f)) await _writeFileSudo(f, '');
  }
  // Ubuntu's opendkim systemd unit reads the socket from /etc/default/opendkim,
  // which (if present) overrides the Socket line in opendkim.conf. Keep them in
  // sync so the daemon actually listens on the milter port Postfix talks to.
  await _writeFileSudo(
    '/etc/default/opendkim',
    'RUNDIR=/run/opendkim\nSOCKET="inet:8891@localhost"\nUSER=opendkim\n'
        'GROUP=opendkim\nPIDFILE=\$RUNDIR/\$NAME.pid\n',
  );

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
  // Ensure the `ssl-cert` group exists and both Postfix and Dovecot are
  // members so they can read the private key (mode 640, group ssl-cert).
  await _sudo('groupadd', ['--force', '--system', 'ssl-cert'], failOk: true);
  for (final user in <String>['postfix', 'dovecot']) {
    await _sudo('usermod', ['-aG', 'ssl-cert', user], failOk: true);
  }

  await _sudo('mkdir', ['-p', _mailCertDir], failOk: true);
  await _sudo('chmod', ['755', _mailCertDir], failOk: true);

  final names = hostnames.where((h) => h.trim().isNotEmpty).toSet().toList();
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

  await _sudo('chmod', ['644', _mailCertPath], failOk: true);
  await _sudo('chmod', ['640', _mailKeyPath], failOk: true);
  await _sudo('chown', ['root:ssl-cert', _mailKeyPath], failOk: true);
  await _writeFileSudo(stamp, desired);
  await _sudo('rm', ['-f', tmpConf], failOk: true);
}

/// Open the standard SMTP/IMAP/POP3 ports when `ufw` is present. Harmless
/// (failOk) when ufw is not installed or not active.
Future<void> _mailOpenFirewall() async {
  final has = await Process.run('sh', ['-c', 'command -v ufw']);
  if (has.exitCode != 0) return; // ufw not installed — nothing to open
  for (final port in <String>['25', '465', '587', '143', '993', '110', '995']) {
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

  // Which domains we are authoritative for (handled by the virtual transport).
  await _sudo(
      'postconf', ['-e', 'virtual_mailbox_domains=${domainNames.join(' ')}']);
  await _sudo('postconf', ['-e', 'mydestination=localhost']);

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

  // Report DKIM public keys + the detected public IP back to the backend.
  final publicIp = await _detectPublicIp();
  stdout.writeln(jsonEncode({
    'domains': dkimResults,
    if (publicIp != null) 'publicIp': publicIp,
  }));
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

    // Generate the keypair only when it does not already exist.
    if (!await _privFileExists(privatePath)) {
      await _sudo('opendkim-genkey', [
        '-b', '2048',
        '-d', domain,
        '-s', selector,
        '-D', keyDir,
      ]);
      await _sudo('chown', ['-R', 'opendkim:opendkim', keyDir], failOk: true);
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
    'redis': 'redis-server',
    'memcached': 'memcached',
  };
  final pkg = packages[type];
  const handledTypes = {'mailpit', 'postfix', 'dovecot'};
  if (pkg == null && !handledTypes.contains(type)) {
    // smtp and other config-only services — nothing to install on the host.
    stdout.writeln('Service $type is config-only — nothing to install.');
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

  // apt install (redis, memcached, …).
  await _aptInstall([pkg!]);
  await _serviceConfigure(type, config);
  await _serviceCtl('enable', type);
  await _serviceCtl('start', type);
}

Future<void> _serviceConfigure(String type, Map<String, dynamic> config) async {
  switch (type) {
    case 'redis':
      final lines = [
        'bind ${config['bind'] ?? '127.0.0.1'}',
        'port ${config['port'] ?? '6379'}',
        if ((config['maxmemory'] as String?)?.isNotEmpty ?? false)
          'maxmemory ${config['maxmemory']}',
        'maxmemory-policy ${config['maxmemory_policy'] ?? 'allkeys-lru'}',
        if ((config['password'] as String?)?.isNotEmpty ?? false)
          'requirepass ${config['password']}',
        'appendonly ${config['appendonly'] == 'false' ? 'no' : 'yes'}',
      ];
      await _writeFileSudo('/etc/redis/redis.conf', lines.join('\n') + '\n');
      await _serviceCtl('restart', 'redis-server');

    case 'memcached':
      final port = config['port'] ?? '11211';
      final mem = config['memory_mb'] ?? '64';
      final conn = config['connections'] ?? '1024';
      final content = '-p $port\n-m $mem\n-c $conn\n-u memcache\n';
      await _writeFileSudo('/etc/memcached.conf', content);
      await _serviceCtl('restart', 'memcached');

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
      await _sudo(
          'apt-get', ['-qq', '-y', 'remove', '--purge', 'redis-server']);
    case 'memcached':
      await _sudo('apt-get', ['-qq', '-y', 'remove', '--purge', 'memcached']);
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
      'redis' => 'redis-server',
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
        'start-instance | stop-instance | create-db | drop-db');
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
        help: 'JSON object of postgresql.conf settings to ALTER SYSTEM SET');

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
