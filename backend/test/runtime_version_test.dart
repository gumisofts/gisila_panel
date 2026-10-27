import 'package:gisila_panel/forms/runtime_version.dart';
import 'package:test/test.dart';

void main() {
  test('accepts real pins and an empty value', () {
    for (final v in ['', '22.12.0', '3.12', 'stable', 'nightly-2024-01-01']) {
      expect(validRuntimeVersion(v), isNull, reason: v);
    }
  });

  test('refuses values the agent would reject', () {
    for (final v in ['../../etc', '22..1', '/opt/x', '-rf', r'22;$(id)']) {
      expect(validRuntimeVersion(v), isNotNull, reason: v);
    }
  });
}
