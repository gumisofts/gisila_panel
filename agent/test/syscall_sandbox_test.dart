import 'package:gisila_agent/generators/systemd_unit.dart';
import 'package:test/test.dart';

/// Every per-app unit gets the seccomp filter and empty capability sets
/// (PNL-05), and GISILA_SYSCALL_FILTER=off drops the filter for one app.
void main() {
  const workDir = '/srv/apps/app_abc123';
  const user = 'app_abc123';

  Map<String, String> units(Map<String, String> env) => {
        'web': SystemdUnit(
          appId: 1,
          linuxUser: user,
          workDir: workDir,
          startCommand: '/usr/bin/node server.js',
          envVars: env,
        ).render(),
        'worker': CeleryWorkerUnit(
          appId: 1,
          linuxUser: user,
          workDir: workDir,
          celeryApp: 'proj',
          workerIndex: 1,
          envVars: env,
        ).render(),
        'beat': CeleryBeatUnit(
          appId: 1,
          linuxUser: user,
          workDir: workDir,
          celeryApp: 'proj',
          envVars: env,
        ).render(),
        'flower': CeleryFlowerUnit(
          appId: 1,
          linuxUser: user,
          workDir: workDir,
          celeryApp: 'proj',
          port: 5555,
          envVars: env,
        ).render(),
      };

  test('every unit type filters system calls and drops capabilities', () {
    for (final MapEntry(key: kind, value: unit) in units(const {}).entries) {
      expect(unit, contains('SystemCallFilter=@system-service\n'),
          reason: kind);
      expect(
          unit, contains('SystemCallFilter=~@privileged @resources @mount\n'),
          reason: kind);
      expect(unit, contains('SystemCallErrorNumber=EPERM\n'), reason: kind);
      expect(unit, contains('CapabilityBoundingSet=\n'), reason: kind);
      expect(unit, contains('AmbientCapabilities=\n'), reason: kind);
      // Inside [Service], next to the other sandboxing lines.
      final service = unit.indexOf('[Service]');
      final install = unit.indexOf('[Install]');
      final filter = unit.indexOf('SystemCallFilter=');
      expect(filter, greaterThan(service), reason: kind);
      expect(filter, lessThan(install), reason: kind);
    }
  });

  test('GISILA_SYSCALL_FILTER=off drops the filter, keeps the caps', () {
    for (final MapEntry(key: kind, value: unit)
        in units(const {syscallFilterEnvVar: 'OFF'}).entries) {
      expect(unit, isNot(contains('SystemCallFilter=')), reason: kind);
      expect(unit, isNot(contains('SystemCallErrorNumber=')), reason: kind);
      expect(unit, contains('CapabilityBoundingSet=\n'), reason: kind);
      expect(unit, contains('GISILA_SYSCALL_FILTER=off'), reason: kind);
    }
  });

  test('other values keep the filter on', () {
    final unit = units(const {syscallFilterEnvVar: 'no'})['web']!;
    expect(unit, contains('SystemCallFilter=@system-service'));
  });
}
