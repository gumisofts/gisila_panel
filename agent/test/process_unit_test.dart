import 'package:gisila_agent/generators/supervisor_conf.dart';
import 'package:gisila_agent/generators/systemd_unit.dart';
import 'package:test/test.dart';

/// A background process (`expose_mode = process`) has no port: its unit must
/// not export one, while a port-bound app keeps getting PORT as before.
void main() {
  const workDir = '/srv/apps/app_abc123';

  test('systemd unit for a background process exports no PORT', () {
    final unit = SystemdUnit(
      appId: 7,
      linuxUser: 'app_abc123',
      workDir: workDir,
      startCommand: '/usr/bin/python3 worker.py',
    ).render();
    expect(unit, isNot(contains('Environment=PORT=')));
    expect(unit, contains('Environment=GISILA_APP_ID=7'));
    expect(unit, contains('Restart=always'));
  });

  test('systemd unit for a port-bound app still exports PORT', () {
    final unit = SystemdUnit(
      appId: 7,
      linuxUser: 'app_abc123',
      workDir: workDir,
      startCommand: '/usr/bin/python3 server.py',
      port: 4100,
    ).render();
    expect(unit, contains('Environment=PORT=4100\nEnvironment=GISILA_APP_ID=7'));
  });

  test('supervisor conf for a background process exports no PORT', () {
    final conf = SupervisorConf(
      appId: 7,
      linuxUser: 'app_abc123',
      workDir: workDir,
      startCommand: '/usr/bin/python3 worker.py',
    ).render();
    expect(conf, isNot(contains('PORT=')));
    expect(conf, contains('GISILA_APP_ID="7"'));
  });
}
