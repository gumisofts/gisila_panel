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
}
