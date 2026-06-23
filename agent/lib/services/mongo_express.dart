import 'dart:io';

import 'package:gisila_agent/runtime/applier.dart';
import 'package:gisila_agent/runtime/priv.dart';
import 'package:gisila_agent/services/handler.dart';

/// mongo-express — a web-based MongoDB admin UI, the Mongo analogue of pgAdmin.
///
/// Installed globally via npm and run as the `gisila-mongo-express` systemd unit
/// on 127.0.0.1:<port>, optionally exposed at a domain via nginx + Let's Encrypt.
class MongoExpressHandler extends ServiceHandler {
  @override
  String get type => 'mongo-express';

  static const _envFile = '/etc/gisila/mongo-express.env';
  static const _unit = '/etc/systemd/system/gisila-mongo-express.service';

  @override
  Future<void> install(Map<String, dynamic> config) async {
    if (Platform.environment['DOCKER_DEPLOY'] == 'true') {
      throw Exception('mongo-express install is only supported on systemd hosts.');
    }
    // Ensure npm is available, then install mongo-express globally.
    final hasNpm = await Process.run('sh', ['-c', 'command -v npm']);
    if (hasNpm.exitCode != 0) {
      await Priv.aptInstall(['nodejs', 'npm']);
    }
    await Priv.sudo('npm', ['install', '-g', 'mongo-express']);

    await Priv.sudo('mkdir', ['-p', '/etc/gisila']);
    await configure(config);
    await Priv.sudo('systemctl', ['daemon-reload']);
    await Priv.sudo('systemctl', ['enable', unitName]);
    await Priv.sudo('systemctl', ['restart', unitName]);
  }

  @override
  Future<void> configure(Map<String, dynamic> config) async {
    final host = _str(config['mongo_host'], '127.0.0.1');
    final mongoPort = _str(config['mongo_port'], '27017');
    final adminUser = _str(config['admin_user'], 'root');
    final adminPassword = _str(config['admin_password'], '');
    final webUser = _str(config['web_user'], 'admin');
    final webPassword = _str(config['web_password'], '');
    final port = _str(config['port'], '8081');

    final cred = adminPassword.isNotEmpty
        ? '${Uri.encodeComponent(adminUser)}:${Uri.encodeComponent(adminPassword)}@'
        : '';
    final mongoUrl = 'mongodb://$cred$host:$mongoPort/?authSource=admin';

    // Values are written as KEY=value lines (no shell parsing), so they are
    // embedded verbatim; mongo-express reads its whole config from these.
    final env = <String, String>{
      'ME_CONFIG_MONGODB_URL': mongoUrl,
      'ME_CONFIG_MONGODB_ENABLE_ADMIN': 'true',
      'ME_CONFIG_BASICAUTH': webPassword.isNotEmpty ? 'true' : 'false',
      'ME_CONFIG_BASICAUTH_USERNAME': webUser,
      'ME_CONFIG_BASICAUTH_PASSWORD': webPassword,
      'VCAP_APP_HOST': '127.0.0.1',
      'VCAP_APP_PORT': port,
      'PORT': port,
    };
    final body =
        env.entries.map((e) => '${e.key}=${e.value}').join('\n') + '\n';
    await Priv.writeFile(_envFile, body);

    await _writeUnit();

    // Optional public exposure via nginx + Let's Encrypt.
    final domain = _str(config['domain'], '').toLowerCase();
    if (domain.isNotEmpty) {
      await _exposeDomain(domain, port, tls: config['tls'] != 'false');
    }

    // Apply (no-op on first install before the unit is enabled).
    await Priv.sudo('systemctl', ['daemon-reload'], failOk: true);
    await Priv.sudo('systemctl', ['restart', unitName], failOk: true);
  }

  @override
  Future<void> uninstall() async {
    await Priv.sudo('rm', ['-f', _unit], failOk: true);
    await Priv.sudo('rm', ['-f', _envFile], failOk: true);
    await Priv.sudo('systemctl', ['daemon-reload'], failOk: true);
    await Priv.sudo('npm', ['uninstall', '-g', 'mongo-express'], failOk: true);
    await Priv.sudo(
        'rm', ['-f', '/etc/nginx/sites-enabled/gisila-mongo-express.conf'],
        failOk: true);
    await Priv.sudo('systemctl', ['reload', 'nginx'], failOk: true);
  }

  Future<void> _writeUnit() async {
    // mongo-express is installed by npm at a global bin path; resolve it so the
    // unit's ExecStart is correct regardless of the npm prefix.
    final resolved = await Process.run('sh', ['-c', 'command -v mongo-express']);
    final bin = (resolved.stdout as String? ?? '').trim().isNotEmpty
        ? (resolved.stdout as String).trim()
        : '/usr/local/bin/mongo-express';
    await Priv.writeFile(_unit, '''[Unit]
Description=gisila mongo-express (MongoDB web admin)
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=$_envFile
ExecStart=$bin
Restart=on-failure
RestartSec=5
DynamicUser=yes

[Install]
WantedBy=multi-user.target
''');
  }

  Future<void> _exposeDomain(String domain, String port,
      {required bool tls}) async {
    final conf = '/etc/nginx/sites-enabled/gisila-mongo-express.conf';
    await Priv.writeFile(conf, '''server {
    listen 80;
    server_name $domain;
    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
''');
    await Priv.sudo('systemctl', ['reload', 'nginx'], failOk: true);
    if (tls) {
      // Installer mode upgrades the vhost to HTTPS with a redirect.
      await Applier().issueCertInstaller(domain);
    }
  }

  static String _str(Object? v, String fallback) {
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }
}
