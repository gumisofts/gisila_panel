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

}
