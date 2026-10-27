import 'dart:io';

import 'package:gisila_agent/runtime/applier.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('apparmor_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Applier applierWith(String? enabled) {
    final flag = File('${tmp.path}/enabled');
    if (enabled != null) flag.writeAsStringSync('$enabled\n');
    return Applier(apparmorDir: tmp.path, apparmorEnabledPath: flag.path);
  }

  test('reads the kernel flag', () {
    expect(applierWith('Y').apparmorEnabled, isTrue);
    expect(applierWith('N').apparmorEnabled, isFalse);
    expect(applierWith(null).apparmorEnabled, isFalse);
  });

  test('skips loading where AppArmor is off', () async {
    await applierWith('N').loadApparmorProfile('${tmp.path}/gisila-x');
  });

  test('a profile that fails to load fails the deploy', () async {
    // Not a valid profile, and loading needs root: apparmor_parser (or its
    // absence) fails either way.
    final profile = File('${tmp.path}/gisila-x')..writeAsStringSync('nope {');
    await expectLater(
      applierWith('Y').loadApparmorProfile(profile.path),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('Could not load AppArmor'))),
    );
  });
}
