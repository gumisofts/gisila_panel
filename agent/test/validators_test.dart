import 'dart:io';

import 'package:gisila_agent/runtime/validators.dart';
import 'package:test/test.dart';

void main() {
  group('optionalCommand', () {
    test('accepts an ordinary start command', () {
      expect(AgentValidators.optionalCommand('node server.js --port 4000'),
          'node server.js --port 4000');
    });

    test('rejects a newline that would add a unit directive', () {
      expect(
        () => AgentValidators.optionalCommand(
            'node server.js\nExecStartPre=+/bin/sh -c id'),
        throwsArgumentError,
      );
    });

    test('rejects a carriage return', () {
      expect(() => AgentValidators.optionalCommand('node a.js\rUser=root'),
          throwsArgumentError);
    });
  });

  group('rejectControlChars', () {
    test('passes plain values and null', () {
      AgentValidators.rejectControlChars('celery-queues', 'default,emails');
      AgentValidators.rejectControlChars('celery-queues', null);
    });

    test('rejects a celery app that would inject User=root', () {
      expect(
        () =>
            AgentValidators.rejectControlChars('celery-app', 'proj\nUser=root'),
        throwsArgumentError,
      );
    });
  });

  group('requireEnvVars', () {
    test('accepts identifier names with any value', () {
      final vars = {'DATABASE_URL': 'postgres://x', '_X1': 'a\nb'};
      expect(AgentValidators.requireEnvVars(vars), vars);
    });

    test('rejects a name that is not a plain identifier', () {
      for (final name in ['A=B', 'A\nB', '1ABC', 'A B', r'$(id)', '']) {
        expect(() => AgentValidators.requireEnvVars({name: 'v'}),
            throwsArgumentError,
            reason: name);
      }
    });
  });

  group('requireGitUrl', () {
    test('accepts remote URLs', () {
      for (final url in [
        'https://github.com/gumisofts/gisila.git',
        'http://gitea.lan:3000/team/app.git',
        'ssh://git@github.com:22/org/repo.git',
        'git://example.com/repo.git',
        'git@github.com:org/repo.git',
        'deploy@git.example.com:team/app',
      ]) {
        expect(AgentValidators.requireGitUrl(url), url, reason: url);
      }
    });

    test('rejects local paths, file:// and option-like values', () {
      for (final url in [
        'file:///srv/apps/app_abcdef/releases/current_build',
        '/srv/apps/app_abcdef',
        '../other',
        'ext::sh -c touch% /tmp/pwned',
        '--upload-pack=touch /tmp/x',
        'ssh://-oProxyCommand=id/x',
        'git@-oProxyCommand=id:x',
        'git@github.com:-x',
        'https://github.com/a\nb',
        'https://github.com/a b',
        '',
      ]) {
        expect(() => AgentValidators.requireGitUrl(url), throwsArgumentError,
            reason: url);
      }
      expect(() => AgentValidators.requireGitUrl(null), throwsArgumentError);
    });
  });

  group('optionalGitRef', () {
    test('accepts branch and tag names', () {
      for (final ref in ['main', 'release/1.2', 'feature/x_y-z', 'v1.0.0']) {
        expect(AgentValidators.optionalGitRef(ref), ref, reason: ref);
      }
      expect(AgentValidators.optionalGitRef(null), isNull);
      expect(AgentValidators.optionalGitRef(''), isNull);
    });

    test('rejects option-like and malformed refs', () {
      for (final ref in [
        '--upload-pack=id',
        '-b',
        'a..b',
        'main@{1}',
        'x.lock',
        '/main',
        'main/',
        'a b',
        'a\nb',
        r'$(id)',
      ]) {
        expect(() => AgentValidators.optionalGitRef(ref), throwsArgumentError,
            reason: ref);
      }
    });
  });

  group('requireArtifactPath', () {
    late Directory root;
    late String upload;
    const id = '0123456789abcdef0123456789abcdef';

    setUp(() {
      root = Directory.systemTemp.createTempSync('gisila_artifacts_');
      Directory('${root.path}/apps/7').createSync(recursive: true);
      upload = '${root.path}/apps/7/$id.zip';
      File(upload).writeAsStringSync('PK');
    });
    tearDown(() => root.deleteSync(recursive: true));

    String check(String? path, {String appId = '7', String type = 'zip'}) =>
        AgentValidators.requireArtifactPath(path,
            appId: appId, sourceType: type, root: root.path);

    test("accepts this app's upload", () {
      expect(check(upload), upload);
    });

    test('rejects paths outside the artifact root', () {
      for (final p in [null, '', '/etc/shadow', '${root.path}/apps/7/../../x']) {
        expect(() => check(p), throwsArgumentError, reason: p);
      }
    });

    test("rejects another app's upload", () {
      expect(() => check(upload, appId: '8'), throwsArgumentError);
    });

    test('rejects an extension that does not match the source type', () {
      expect(() => check(upload, type: 'binary'), throwsArgumentError);
    });

    test('rejects a missing file', () {
      expect(() => check('${root.path}/apps/7/${'f' * 32}.zip'),
          throwsArgumentError);
    });

    test('rejects a symlink, even to a real file', () {
      final link = '${root.path}/apps/7/${'a' * 32}.zip';
      Link(link).createSync('/etc/hostname');
      expect(() => check(link), throwsArgumentError);
    });

    test('rejects a symlinked app directory', () {
      Directory('${root.path}/elsewhere').createSync();
      File('${root.path}/elsewhere/$id.zip').writeAsStringSync('PK');
      Link('${root.path}/apps/9').createSync('${root.path}/elsewhere');
      expect(() => check('${root.path}/apps/9/$id.zip', appId: '9'),
          throwsArgumentError);
    });
  });

  group('requireWorkDir', () {
    test('accepts the app home and paths under it', () {
      for (final d in [
        '/srv/apps/app_abc123',
        '/srv/apps/app_abc123/',
        '/srv/apps/app_abc123/current/.runtime',
      ]) {
        expect(AgentValidators.requireWorkDir(d), d);
      }
    });

    test('rejects . and .. segments', () {
      for (final d in [
        '/srv/apps/app_abc123/..',
        '/srv/apps/app_abc123/../app_other99',
        '/srv/apps/app_abc123/../../../etc',
        '/srv/apps/app_abc123/./x',
      ]) {
        expect(() => AgentValidators.requireWorkDir(d), throwsArgumentError,
            reason: d);
      }
    });
  });

  group('optionalVersion', () {
    test('accepts the pins each runtime uses', () {
      for (final v in [
        '22.12.0',
        '3.12',
        '1',
        'stable',
        'nightly-2024-01-01',
        '3.6.0-216.1.beta',
        'v20',
      ]) {
        expect(AgentValidators.optionalVersion('node-version', v), v);
      }
      expect(AgentValidators.optionalVersion('node-version', null), isNull);
      expect(AgentValidators.optionalVersion('node-version', ' '), isNull);
    });

    test('rejects paths, URLs and shell syntax', () {
      for (final v in [
        '../../etc',
        '22..1',
        '/opt/x',
        '22/../../x',
        '-rf',
        r'22;$(id)',
        '22 12',
        '22\nExecStartPre=+/bin/id',
        'a' * 65,
      ]) {
        expect(() => AgentValidators.optionalVersion('node-version', v),
            throwsArgumentError,
            reason: v);
      }
    });
  });

  group('resource limits', () {
    test('memory is clamped to the host, not refused', () {
      final host = AgentValidators.hostMemoryMb();
      expect(AgentValidators.requireMemoryMb('256'), 256);
      if (host != null) {
        expect(AgentValidators.requireMemoryMb('${host * 4}'), host);
      }
    });

    test('CPU quota is clamped to the cores this host has', () {
      final max = Platform.numberOfProcessors * 100;
      expect(AgentValidators.requireCpuQuota('${max + 500}'), max);
      expect(AgentValidators.requireCpuQuota('50'), 50);
    });

    test('nonsense is refused', () {
      for (final v in [null, '', 'x', '0', '-5']) {
        expect(() => AgentValidators.requireMemoryMb(v), throwsArgumentError,
            reason: '$v');
        expect(() => AgentValidators.requireTasksMax(v), throwsArgumentError,
            reason: '$v');
      }
      expect(AgentValidators.requireTasksMax('10'), 10); // older apps deploy
      expect(AgentValidators.requireTasksMax('999999'), 16384);
    });
  });
}
