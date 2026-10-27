import 'dart:io';

import 'package:gisila/gisila.dart' show FormValidationException;
import 'package:gisila_panel/forms/app_forms.dart';
import 'package:test/test.dart';

Future<Map<String, String>> _errors(Map<String, Object?> body) async {
  try {
    await UpdateAppForm().bind(body);
    return const {};
  } on FormValidationException catch (e) {
    return e.errors;
  }
}

void main() {
  test('memory above the host RAM is refused', () async {
    final line = File('/proc/meminfo')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('MemTotal:'));
    final hostMb = int.parse(RegExp(r'(\d+)').firstMatch(line)![1]!) ~/ 1024;
    expect(await _errors({'memoryMbLimit': hostMb * 2}),
        contains('memoryMbLimit'));
    expect(await _errors({'memoryMbLimit': 512}), isEmpty);
    expect(await _errors({'memoryMbLimit': 8}), contains('memoryMbLimit'));
  }, skip: File('/proc/meminfo').existsSync() ? false : 'needs Linux');

  test('task limits are bounded', () async {
    expect(await _errors({'tasksLimit': 100}), isEmpty);
    expect(await _errors({'tasksLimit': 0}), contains('tasksLimit'));
    expect(await _errors({'tasksLimit': 1000000}), contains('tasksLimit'));
  });
}
