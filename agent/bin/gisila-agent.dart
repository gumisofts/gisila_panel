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
      case 'service':
        await _service(rest);
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
    // Python-specific
    p.addOption('python-mode', defaultsTo: 'wsgi');
    p.addOption('wsgi-app');
    p.addOption('workers', defaultsTo: '4');
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
    // Auto-generate the gunicorn start command.
    final mode = r['python-mode'] as String; // wsgi | asgi
    final wsgiApp = r['wsgi-app'] as String? ?? 'app:application';
    final workers = r['workers'] as String;
    final venv = '$workDir/current/.venv';
    final logs = '$workDir/logs';
    final workerClass =
        mode == 'asgi' ? '--worker-class uvicorn.workers.UvicornWorker ' : '';
    startCommand = '$venv/bin/gunicorn '
        '--workers $workers '
        '${workerClass}'
        '--bind 0.0.0.0:\$PORT '
        '--timeout 120 '
        '--access-logfile $logs/access.log '
        '--error-logfile $logs/error.log '
        '$wsgiApp';
  } else {
    startCommand = '$workDir/current/app';
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
  final catResult = await Process.run('sudo', ['cat', dovecotConfPath]);
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
  await _run('sudo', [
    'sh',
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

/// Run a command with sudo.
Future<void> _sudo(String exe, List<String> args, {bool failOk = false}) =>
    _run('sudo', [exe, ...args], failOk: failOk);

/// Install one or more apt packages non-interactively.
Future<void> _aptInstall(List<String> packages) =>
    _sudo('apt-get', ['-qq', '-y', 'install', ...packages]);

/// Write [content] to a privileged [path] using `sudo tee`.
Future<void> _writeFileSudo(String path, String content) async {
  final proc = await Process.start('sudo', ['tee', path]);
  proc.stdin.write(content);
  await proc.stdin.close();
  // tee echoes to stdout — drain it so the process can finish.
  await proc.stdout.drain<void>();
  final exit = await proc.exitCode;
  if (exit != 0) throw Exception('sudo tee $path failed with exit $exit');
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
        help: 'Comma-separated extension names to CREATE EXTENSION');

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
    // gpg --dearmor writes binary to stdout; pipe into the keyring file via sudo tee.
    final gpgProc = await Process.start(
        'sudo', ['gpg', '--dearmor', '-o', '/etc/apt/keyrings/pgdg.gpg']);
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

/// Run a command as a different system user via `sudo -u <user>`.
Future<void> _runAs(String user, List<String> command) async {
  final result = await Process.run('sudo', ['-u', user, ...command]);
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
                [--start-command CMD] \\
                [--memory-mb MB] [--cpu-quota PCT] [--tasks-max N]
  apply-vhost   --app-id ID --port N [--hostname host …]
  issue-cert    --hostname HOSTNAME
  start|stop|restart  --user app_xxx
  uninstall     --user app_xxx [--app-id ID]
  service       install|configure|start|stop|uninstall \\
                --type redis|memcached|smtp|mailpit|postfix|dovecot [--config JSON]
  postgres      install-instance --version VER [--port PORT]
                uninstall-instance --version VER
                start-instance|stop-instance --version VER
                create-db --version VER --db DB --role ROLE --password PASS
                          [--extensions ext1,ext2,…]
                drop-db   --version VER --db DB --role ROLE
''');
}
