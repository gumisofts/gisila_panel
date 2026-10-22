import 'package:gisila_agent/generators/supervisor_conf.dart';
import 'package:gisila_agent/generators/systemd_unit.dart';
import 'package:test/test.dart';

/// Celery identifies a worker by its node name, and Flower keys its dashboard
/// on that name. Two apps on one host that share a broker must therefore not
/// generate the same names, or their workers collapse into one another.
void main() {
  String workerExec(String linuxUser, int index) => CeleryWorkerUnit(
        appId: 1,
        linuxUser: linuxUser,
        workDir: '/srv/apps/$linuxUser',
        celeryApp: 'proj.celery:app',
        workerIndex: index,
      ).render().split('\n').firstWhere((l) => l.startsWith('ExecStart='));

  group('CeleryWorkerUnit node name', () {
    test('is scoped to the app so two apps on one host do not collide', () {
      final a = workerExec('app_aaa111', 1);
      final b = workerExec('app_bbb222', 1);

      expect(a, contains('-n app_aaa111-worker-1@'));
      expect(b, contains('-n app_bbb222-worker-1@'));
      expect(a, isNot(equals(b)));
    });

    test('is distinct per worker index within an app', () {
      expect(workerExec('app_aaa111', 1),
          isNot(equals(workerExec('app_aaa111', 2))));
    });

    test('escapes the hostname specifier so systemd leaves it for celery', () {
      // A bare `%h` is a systemd specifier expanding to the service manager's
      // home (`/root` for system units) — celery would never see a hostname.
      expect(workerExec('app_aaa111', 1), contains('@%%h '));
    });
  });

  group('CeleryWorkerSupervisorConf node name', () {
    final conf = CeleryWorkerSupervisorConf(
      appId: 1,
      linuxUser: 'app_aaa111',
      workDir: '/srv/apps/app_aaa111',
      celeryApp: 'proj.celery:app',
      port: 8000,
      workerCount: 2,
    ).render();

    test('is scoped to the app and to the worker index', () {
      expect(conf, contains('-n app_aaa111-worker-1@'));
      expect(conf, contains('-n app_aaa111-worker-2@'));
    });

    test('escapes the percent so supervisor accepts the program block', () {
      // Supervisor `%`-expands `command=` and rejects the block outright on an
      // unknown specifier, so `%h` has to reach it doubled.
      expect(conf, contains('@%%h '));
      expect(conf, isNot(contains('@%h ')));
    });
  });
}
