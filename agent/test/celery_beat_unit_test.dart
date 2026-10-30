import 'package:gisila_agent/generators/systemd_unit.dart';
import 'package:test/test.dart';

void main() {
  test('beat gets room to import the app', () {
    final unit = CeleryBeatUnit(
      appId: 1,
      linuxUser: 'app_abcdef',
      workDir: '/srv/apps/app_abcdef',
      celeryApp: 'core.celery:app',
    );
    expect(unit.render(), contains('MemoryMax=512M'));
  });
}
