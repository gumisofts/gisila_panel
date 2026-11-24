import 'package:gisila_panel/services/stacks_service.dart';
import 'package:test/test.dart';

void main() {
  test('an app gets its stack\'s vars plus its own', () {
    expect(
      mergeStackEnv({'DATABASE_URL': 'pg://shared'}, {'PORT': '8080'}),
      {'DATABASE_URL': 'pg://shared', 'PORT': '8080'},
    );
  });

  test('the app\'s own value wins on a name clash', () {
    expect(
      mergeStackEnv(
        {'LOG_LEVEL': 'info', 'REDIS_URL': 'redis://shared'},
        {'LOG_LEVEL': 'debug'},
      ),
      {'LOG_LEVEL': 'debug', 'REDIS_URL': 'redis://shared'},
    );
  });

  test('an app\'s empty value still overrides the stack', () {
    expect(mergeStackEnv({'SENTRY_DSN': 'https://x'}, {'SENTRY_DSN': ''}),
        {'SENTRY_DSN': ''});
  });

  test('no stack leaves the app env untouched', () {
    expect(mergeStackEnv(const {}, {'A': '1'}), {'A': '1'});
  });
}
