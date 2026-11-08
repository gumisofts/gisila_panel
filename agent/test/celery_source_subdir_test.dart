import 'package:gisila_agent/generators/supervisor_conf.dart';
import 'package:gisila_agent/generators/systemd_unit.dart';
import 'package:gisila_agent/runtime/builders.dart';
import 'package:test/test.dart';

// A Celery project kept in a monorepo subdirectory must start there, where
// `celery -A <app>` can import it, not at the repo root of the release.
void main() {
  const workDir = '/srv/apps/app_abcdef';
  final subdirSrc = Builders.resolveRunSrc(workDir, 'backend');

  Map<String, String> units(String? workingDirectory) => {
        'worker': CeleryWorkerUnit(
          appId: 1,
          linuxUser: 'app_abcdef',
          workDir: workDir,
          celeryApp: 'core',
          workerIndex: 1,
          workingDirectory: workingDirectory,
        ).render(),
        'beat': CeleryBeatUnit(
          appId: 1,
          linuxUser: 'app_abcdef',
          workDir: workDir,
          celeryApp: 'core',
          workingDirectory: workingDirectory,
        ).render(),
        'flower': CeleryFlowerUnit(
          appId: 1,
          linuxUser: 'app_abcdef',
          workDir: workDir,
          celeryApp: 'core',
          port: 5555,
          workingDirectory: workingDirectory,
        ).render(),
      };

  test('systemd units start in the source subdirectory', () {
    units(subdirSrc).forEach((name, unit) {
      expect(unit, contains('WorkingDirectory=$workDir/current/src/backend\n'),
          reason: name);
    });
  });

  test('systemd units default to the release root', () {
    units(null).forEach((name, unit) {
      expect(unit, contains('WorkingDirectory=$workDir/current/src\n'),
          reason: name);
    });
  });

  test('supervisor programs start in the source subdirectory', () {
    final conf = CeleryWorkerSupervisorConf(
      appId: 1,
      linuxUser: 'app_abcdef',
      workDir: workDir,
      celeryApp: 'core',
      port: 5555,
      beatEnabled: true,
      workingDirectory: subdirSrc,
    ).render();
    final dirs = RegExp(r'^directory=(.*)$', multiLine: true)
        .allMatches(conf)
        .map((m) => m.group(1))
        .toSet();
    expect(dirs, {'$workDir/current/src/backend'});
  });
}
