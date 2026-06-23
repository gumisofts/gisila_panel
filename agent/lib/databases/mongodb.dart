import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:gisila_agent/runtime/applier.dart';
import 'package:gisila_agent/runtime/priv.dart';

/// Modular MongoDB engine handler for the agent.
///
/// Adding a database engine is now: write a `runX` here and add a `case 'x'`
/// in `bin/gisila-agent.dart`. All host mutation goes through [Priv] so this
/// file needs none of the bin's private helpers.
///
/// Multi-instance model: each instance is a dedicated `gisila-mongod-<version>`
/// systemd unit with its own config, data dir and port — the standard MongoDB
/// pattern. Note that all instances share the single `/usr/bin/mongod` binary
/// installed by apt, so installing a *different* major version upgrades that
/// shared binary; instances still run independently (own data/port/unit).
Future<void> runMongo(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: gisila-agent mongo <subcommand> [options]\n'
        'Subcommands: install-instance | uninstall-instance | start-instance | '
        'stop-instance | create-db | drop-db | update-roles | ensure-monitor | '
        'configure | backup | restore | expose | unexpose');
    exitCode = 64;
    return;
  }

  final sub = args.first;
  final parser = ArgParser()
    ..addOption('version', abbr: 'v', help: 'MongoDB version (e.g. 7.0)')
    ..addOption('port', help: 'Port to run this instance on')
    ..addOption('db', help: 'Database name')
    ..addOption('user', help: 'User name')
    ..addOption('password', help: 'User / monitor password')
    ..addOption('root-password', help: 'Root admin password (install only)')
    ..addOption('roles', help: 'Comma-separated built-in roles to grant')
    ..addOption('settings', help: 'JSON object of tunable mongod settings')
    ..addOption('output', help: 'Backup destination path (.archive.gz)')
    ..addOption('input', help: 'Backup source path to restore')
    ..addOption('domain', help: 'Public domain for TLS exposure');

  final opts = parser.parse(args.sublist(1));
  final version = (opts['version'] as String? ?? '').trim();
  if (version.isEmpty) throw ArgumentError('--version required');
  _validateVersion(version);
  final port = int.tryParse(opts['port'] as String? ?? '') ?? 27017;

  switch (sub) {
    case 'install-instance':
      final rootPw = opts['root-password'] as String? ?? '';
      if (rootPw.isEmpty) throw ArgumentError('--root-password required');
      await _install(version, port, rootPw);

    case 'uninstall-instance':
      await _uninstall(version);

    case 'start-instance':
      await Priv.sudo('systemctl', ['start', _unitName(version)]);

    case 'stop-instance':
      await Priv.sudo('systemctl', ['stop', _unitName(version)]);

    case 'ensure-monitor':
      final pass = opts['password'] as String? ?? '';
      if (pass.isEmpty) throw ArgumentError('--password required');
      await _ensureMonitor(version, port, pass);

    case 'create-db':
      final db = _need(opts, 'db');
      final user = _need(opts, 'user');
      final pass = _need(opts, 'password');
      await _createDatabase(version, port, db, user, pass, _roles(opts));

    case 'update-roles':
      final db = _need(opts, 'db');
      final user = _need(opts, 'user');
      await _updateRoles(version, port, db, user, _roles(opts));

    case 'drop-db':
      final db = _need(opts, 'db');
      final user = _need(opts, 'user');
      await _dropDatabase(version, port, db, user);

    case 'configure':
      await _configure(version, port, opts['settings'] as String? ?? '{}');

    case 'backup':
      final db = _need(opts, 'db');
      final output = _need(opts, 'output');
      await _backup(version, port, db, output);

    case 'restore':
      final db = _need(opts, 'db');
      final input = _need(opts, 'input');
      await _restore(version, port, db, input);

    case 'expose':
      final domain = _need(opts, 'domain');
      await _expose(version, port, domain);

    case 'unexpose':
      await _unexpose(version, port);

    default:
      throw ArgumentError('Unknown mongo subcommand: $sub');
  }
}

// ── Layout helpers ────────────────────────────────────────────────────────────

String _unitName(String version) => 'gisila-mongod-$version';
String _confPath(String version) => '/etc/gisila/mongod-$version.conf';
String _dataDir(String version) => '/var/lib/mongo/$version';
String _logPath(String version) => '/var/log/mongodb/gisila-mongod-$version.log';
String _rootPwFile(String version) => '/etc/gisila/mongod-$version.root';
String _certDir(String version) => '/etc/gisila/mongo-tls/$version';

// ── Install / uninstall ─────────────────────────────────────────────────────

/// Install MongoDB Community [version] from the official apt repo and bring up a
/// dedicated `gisila-mongod-<version>` instance on [port] with auth enabled.
Future<void> _install(String version, int port, String rootPw) async {
  // 1. Add the MongoDB apt repo + signing key for this version.
  final keyring = '/usr/share/keyrings/mongodb-server-$version.gpg';
  if (!File(keyring).existsSync()) {
    final key = await Process.run('curl', [
      '-fsSL',
      'https://www.mongodb.org/static/pgp/server-$version.asc',
    ]);
    if (key.exitCode != 0) {
      throw Exception('Failed to download MongoDB key: ${key.stderr}');
    }
    final gpgCmd = Priv.wrap('gpg', ['--dearmor', '-o', keyring]);
    final gpg = await Process.start(gpgCmd.first, gpgCmd.skip(1).toList());
    gpg.stdin.add(key.stdout is String
        ? utf8.encode(key.stdout as String)
        : key.stdout as List<int>);
    await gpg.stdin.close();
    await gpg.stdout.drain<void>();
    if (await gpg.exitCode != 0) throw Exception('gpg --dearmor failed');
  }

  final codename =
      (await Process.run('lsb_release', ['-cs'])).stdout.toString().trim();
  await Priv.writeFile(
    '/etc/apt/sources.list.d/mongodb-org-$version.list',
    'deb [ signed-by=$keyring ] '
        'https://repo.mongodb.org/apt/ubuntu $codename/mongodb-org/$version multiverse\n',
  );

  await Priv.sudo('apt-get', ['update', '-qq']);
  await Priv.aptInstall(
      ['mongodb-org', 'mongodb-mongosh', 'mongodb-database-tools']);

  // 2. The stock package ships a `mongod` unit on 27017 — disable it so it can't
  // race our dedicated instances for the port.
  await Priv.sudo('systemctl', ['disable', '--now', 'mongod'], failOk: true);

  // 3. Data + log dirs, owned by the mongodb service user.
  await Priv.sudo('mkdir', ['-p', _dataDir(version), '/var/log/mongodb']);
  await Priv.sudo('chown', ['-R', 'mongodb:mongodb', _dataDir(version)]);
  await Priv.sudo('mkdir', ['-p', '/etc/gisila']);

  // 4. Config + unit, then start.
  await Priv.writeFile(_confPath(version), _buildConf(version, port));
  await _writeUnit(version);
  await Priv.sudo('systemctl', ['daemon-reload']);
  await Priv.sudo('systemctl', ['enable', _unitName(version)]);
  await Priv.sudo('systemctl', ['restart', _unitName(version)]);

  // 5. Create the authenticated root user via the localhost exception (allowed
  // only while no users exist yet), then persist the password for later admin
  // operations (root-only file).
  await _waitForMongo(port);
  await _eval(port, null,
      "db.getSiblingDB('admin').createUser({user:'root',pwd:'$rootPw',roles:['root']})");
  await Priv.writeFile(_rootPwFile(version), rootPw);
  await Priv.sudo('chmod', ['600', _rootPwFile(version)], failOk: true);
  stdout.writeln('[agent] MongoDB $version running on port $port');
}

Future<void> _uninstall(String version) async {
  await Priv.sudo('systemctl', ['stop', _unitName(version)], failOk: true);
  await Priv.sudo('systemctl', ['disable', _unitName(version)], failOk: true);
  await Priv.sudo('rm', ['-f', '/etc/systemd/system/${_unitName(version)}.service'],
      failOk: true);
  await Priv.sudo('systemctl', ['daemon-reload'], failOk: true);
  await Priv.sudo('rm', [
    '-rf',
    _dataDir(version),
    _confPath(version),
    _rootPwFile(version),
    _certDir(version),
  ], failOk: true);
}

// ── Users & databases ─────────────────────────────────────────────────────────

Future<void> _ensureMonitor(String version, int port, String password) async {
  final root = await _rootPw(version);
  // Idempotent: update if present, else create. clusterMonitor covers
  // serverStatus/getCmdLineOpts; readAnyDatabase lets listDatabases report sizes.
  final js = "var a = db.getSiblingDB('admin'); "
      "if (a.getUser('gisila_monitor')) { "
      "a.updateUser('gisila_monitor', {pwd:'$password', "
      "roles:['clusterMonitor','readAnyDatabase']}); } else { "
      "a.createUser({user:'gisila_monitor', pwd:'$password', "
      "roles:['clusterMonitor','readAnyDatabase']}); }";
  await _eval(port, root, js);
}

Future<void> _createDatabase(String version, int port, String db, String user,
    String password, List<String> roles) async {
  final root = await _rootPw(version);
  final roleArray = _roleArrayJs(roles.isEmpty ? ['readWrite'] : roles, db);
  // Create the user scoped to the target db, then touch a collection so the
  // database materialises and is visible in listDatabases.
  final js = "var d = db.getSiblingDB('$db'); "
      "if (d.getUser('$user')) { "
      "d.updateUser('$user', {pwd:'$password', roles:$roleArray}); } else { "
      "d.createUser({user:'$user', pwd:'$password', roles:$roleArray}); } "
      "d.createCollection('_gisila_init');";
  await _eval(port, root, js);
}

Future<void> _updateRoles(
    String version, int port, String db, String user, List<String> roles) async {
  final root = await _rootPw(version);
  final roleArray = _roleArrayJs(roles, db);
  await _eval(port, root,
      "db.getSiblingDB('$db').updateUser('$user', {roles:$roleArray})");
}

Future<void> _dropDatabase(
    String version, int port, String db, String user) async {
  final root = await _rootPw(version);
  final js = "var d = db.getSiblingDB('$db'); "
      "try { d.dropUser('$user'); } catch (e) {} "
      "d.dropDatabase();";
  await _eval(port, root, js);
}

/// Build a MongoDB roles array literal, scoping cluster/any-database roles to
/// `admin` and everything else to the target [db]. Names are allowlisted by the
/// backend, so they are safe to embed.
String _roleArrayJs(List<String> roles, String db) {
  final items = roles.map((r) {
    final adminScoped = r == 'clusterMonitor' || r.endsWith('AnyDatabase');
    return "{role:'$r',db:'${adminScoped ? 'admin' : db}'}";
  }).join(',');
  return '[$items]';
}

// ── Configuration ──────────────────────────────────────────────────────────────

Future<void> _configure(String version, int port, String settingsJson) async {
  final settings = jsonDecode(settingsJson) as Map<String, dynamic>;
  double? cacheSizeGB;
  int? maxConns;
  final cache = settings['cacheSizeGB'];
  if (cache != null) cacheSizeGB = double.tryParse(cache.toString());
  final mc = settings['maxIncomingConnections'];
  if (mc != null) maxConns = int.tryParse(mc.toString());

  // Preserve current exposure state (bindIp / TLS) while rewriting the config.
  final current = await Priv.readFile(_confPath(version)) ?? '';
  final exposed = current.contains('0.0.0.0');
  await Priv.writeFile(
    _confPath(version),
    _buildConf(version, port,
        cacheSizeGB: cacheSizeGB,
        maxConns: maxConns,
        publicCertDir: exposed ? _certDir(version) : null),
  );
  await Priv.sudo('systemctl', ['restart', _unitName(version)]);
}

/// Render a mongod YAML config for [version] on [port]. Optional tunables and
/// public-TLS exposure are layered in when supplied.
String _buildConf(
  String version,
  int port, {
  double? cacheSizeGB,
  int? maxConns,
  String? publicCertDir,
}) {
  final bindIp = publicCertDir != null ? '127.0.0.1,0.0.0.0' : '127.0.0.1';
  final buf = StringBuffer()
    ..writeln('# Managed by gisila-panel — do not edit by hand.')
    ..writeln('storage:')
    ..writeln('  dbPath: ${_dataDir(version)}');
  if (cacheSizeGB != null) {
    buf
      ..writeln('  wiredTiger:')
      ..writeln('    engineConfig:')
      ..writeln('      cacheSizeGB: $cacheSizeGB');
  }
  buf
    ..writeln('systemLog:')
    ..writeln('  destination: file')
    ..writeln('  path: ${_logPath(version)}')
    ..writeln('  logAppend: true')
    ..writeln('net:')
    ..writeln('  port: $port')
    ..writeln('  bindIp: $bindIp');
  if (maxConns != null) {
    buf.writeln('  maxIncomingConnections: $maxConns');
  }
  if (publicCertDir != null) {
    buf
      ..writeln('  tls:')
      ..writeln('    mode: requireTLS')
      ..writeln('    certificateKeyFile: $publicCertDir/mongo.pem');
  }
  buf
    ..writeln('security:')
    ..writeln('  authorization: enabled');
  return buf.toString();
}

Future<void> _writeUnit(String version) async {
  await Priv.writeFile(
    '/etc/systemd/system/${_unitName(version)}.service',
    '''[Unit]
Description=gisila MongoDB $version
After=network-online.target
Wants=network-online.target

[Service]
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongod --config ${_confPath(version)}
Restart=on-failure
RestartSec=5
LimitNOFILE=64000
LimitNPROC=64000

[Install]
WantedBy=multi-user.target
''',
  );
}

// ── Backup / restore ─────────────────────────────────────────────────────────

Future<void> _backup(String version, int port, String db, String output) async {
  final root = await _rootPw(version);
  final dir = File(output).parent.path;
  await Priv.sudo('mkdir', ['-p', dir]);

  final uri =
      'mongodb://root:$root@127.0.0.1:$port/?authSource=admin';
  // mongodump --archive --gzip writes a single compressed archive of one db.
  final inner = 'set -o pipefail; mongodump --uri=${Priv.shq(uri)} '
      '--db=${Priv.shq(db)} --archive=${Priv.shq(output)} --gzip';
  final cmd = Priv.wrap('bash', ['-c', inner]);
  final res = await Process.run(cmd.first, cmd.skip(1).toList());
  if (res.exitCode != 0) {
    throw Exception('mongodump failed (${res.exitCode}): ${res.stderr}'.trim());
  }
  // Hand the artifact to the gisila user so the API can stream it for download.
  await Priv.sudo('chown', ['gisila:gisila', output], failOk: true);
  await Priv.sudo('chmod', ['640', output], failOk: true);
  final size = await File(output).length();
  stdout.writeln(jsonEncode({'sizeBytes': size}));
}

Future<void> _restore(String version, int port, String db, String input) async {
  if (!await File(input).exists()) {
    throw Exception('Restore source not found: $input');
  }
  final root = await _rootPw(version);
  final uri = 'mongodb://root:$root@127.0.0.1:$port/?authSource=admin';
  final gzip = input.endsWith('.gz') ? '--gzip ' : '';
  // --drop replaces existing collections so a restore is a clean overwrite.
  final inner = 'mongorestore --uri=${Priv.shq(uri)} --nsInclude=${Priv.shq('$db.*')} '
      '--drop $gzip--archive=${Priv.shq(input)}';
  final cmd = Priv.wrap('bash', ['-c', inner]);
  final res = await Process.run(cmd.first, cmd.skip(1).toList());
  if (res.exitCode != 0) {
    throw Exception('mongorestore failed (${res.exitCode}): ${res.stderr}'.trim());
  }
}

// ── Public exposure ───────────────────────────────────────────────────────────

Future<void> _expose(String version, int port, String domain) async {
  // Certificate first — a public DB must be TLS-protected, so if cert issuance
  // fails (DNS/port 80) nothing else changes.
  await Applier().issueCert(domain);

  // mongod wants a single PEM (cert + key concatenated). Build it from the live
  // Let's Encrypt files into a mongodb-readable location, refreshed on renewal.
  final dest = _certDir(version);
  await _installCert(version, domain, dest);

  await Priv.writeFile(
    _confPath(version),
    _buildConf(version, port, publicCertDir: dest),
  );
  await Priv.ufwAllow(port);
  await Priv.sudo('systemctl', ['restart', _unitName(version)]);
  stdout.writeln('[agent] MongoDB $version exposed at $domain:$port (TLS)');
}

Future<void> _unexpose(String version, int port) async {
  await Priv.writeFile(_confPath(version), _buildConf(version, port));
  await Priv.ufwDeny(port);
  await Priv.sudo('rm',
      ['-f', '/etc/letsencrypt/renewal-hooks/deploy/gisila-mongo-$version.sh'],
      failOk: true);
  await Priv.sudo('systemctl', ['restart', _unitName(version)]);
  stdout.writeln('[agent] MongoDB $version is private again (localhost only)');
}

/// Concatenate the live LE cert + key into a mongodb-owned PEM and install a
/// certbot renewal deploy hook that rebuilds it + reloads on renew.
Future<void> _installCert(String version, String domain, String dest) async {
  await Priv.sudo('mkdir', ['-p', dest]);
  final live = '/etc/letsencrypt/live/$domain';
  final pem = '$dest/mongo.pem';
  await Priv.sudo('bash', [
    '-c',
    'cat ${Priv.shq('$live/fullchain.pem')} ${Priv.shq('$live/privkey.pem')} > ${Priv.shq(pem)}'
  ]);
  await Priv.sudo('chown', ['-R', 'mongodb:mongodb', dest]);
  await Priv.sudo('chmod', ['600', pem]);

  await Priv.sudo('mkdir', ['-p', '/etc/letsencrypt/renewal-hooks/deploy']);
  final hook = '/etc/letsencrypt/renewal-hooks/deploy/gisila-mongo-$version.sh';
  await Priv.writeFile(hook, '''#!/bin/sh
set -e
D="$domain"
DEST="$dest"
mkdir -p "\$DEST"
cat "/etc/letsencrypt/live/\$D/fullchain.pem" "/etc/letsencrypt/live/\$D/privkey.pem" > "\$DEST/mongo.pem"
chown -R mongodb:mongodb "\$DEST"
chmod 600 "\$DEST/mongo.pem"
systemctl reload ${_unitName(version)} || systemctl restart ${_unitName(version)} || true
''');
  await Priv.sudo('chmod', ['755', hook]);
}

// ── mongosh helpers ────────────────────────────────────────────────────────────

/// Run a JS snippet via mongosh. When [rootPw] is null we connect without auth
/// (used once at install via the localhost exception); otherwise we authenticate
/// as root.
Future<void> _eval(int port, String? rootPw, String js) async {
  final args = <String>['--quiet', '--port', '$port'];
  if (rootPw != null) {
    args
      ..add('--username')
      ..add('root')
      ..add('--password')
      ..add(rootPw)
      ..add('--authenticationDatabase')
      ..add('admin');
  }
  args
    ..add('--eval')
    ..add(js);
  final res = await Process.run('mongosh', args);
  if (res.exitCode != 0) {
    throw Exception('mongosh failed (${res.exitCode}): ${res.stderr}'.trim());
  }
}

/// Poll until mongod accepts connections (up to ~30s after a fresh start).
Future<void> _waitForMongo(int port) async {
  for (var i = 0; i < 30; i++) {
    final res = await Process.run('mongosh', [
      '--quiet',
      '--port',
      '$port',
      '--eval',
      'db.runCommand({ping:1})',
    ]);
    if (res.exitCode == 0) return;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw Exception('MongoDB on port $port did not become ready in time');
}

Future<String> _rootPw(String version) async {
  final pw = (await Priv.readFile(_rootPwFile(version)))?.trim();
  if (pw == null || pw.isEmpty) {
    throw Exception('Root password for MongoDB $version not found on host.');
  }
  return pw;
}

// ── Validation ────────────────────────────────────────────────────────────────

void _validateVersion(String v) {
  if (!RegExp(r'^\d+\.\d+$').hasMatch(v)) {
    throw ArgumentError('Invalid MongoDB version: $v');
  }
}

String _need(ArgResults opts, String name) {
  final v = (opts[name] as String? ?? '').trim();
  if (v.isEmpty) throw ArgumentError('--$name required');
  return v;
}

List<String> _roles(ArgResults opts) => (opts['roles'] as String? ?? '')
    .split(',')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();
