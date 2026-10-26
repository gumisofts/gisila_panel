import 'dart:io' hide HttpException;
import 'dart:typed_data';

import 'package:gisila/gisila.dart' show HttpException;
import 'package:gisila_panel/services/artifact_store.dart';
import 'package:test/test.dart';

final _zip = [0x50, 0x4b, 0x03, 0x04, 1, 2, 3];
final _elf = [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1];

/// The body as dart:io delivers it: Uint8List chunks.
Stream<List<int>> _body(List<int> bytes, {int chunk = 3}) async* {
  for (var i = 0; i < bytes.length; i += chunk) {
    yield Uint8List.fromList(
        bytes.sublist(i, i + chunk > bytes.length ? bytes.length : i + chunk));
  }
}

Matcher _status(int code) =>
    isA<HttpException>().having((e) => e.statusCode, 'statusCode', code);

void main() {
  late Directory root;
  late ArtifactStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('gisila_artifact_store_');
    store = ArtifactStore(root: root.path, maxBytes: 16, keep: 2);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('stores a ZIP and resolves it for the same app and kind only', () async {
    final id = await store.save(7, 'zip', _body(_zip));
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    final path = store.resolve(7, id, 'zip');
    expect(path, '${root.path}/apps/7/$id.zip');
    expect(File(path!).readAsBytesSync(), _zip);
    expect(store.resolve(8, id, 'zip'), isNull);
    expect(store.resolve(7, id, 'binary'), isNull);
  });

  test('accepts an ELF binary or a #! script', () async {
    final elf = await store.save(7, 'binary', _body(_elf));
    expect(store.resolve(7, elf, 'binary'), endsWith('$elf.bin'));
    await store.save(7, 'binary', _body('#!/bin/sh\necho'.codeUnits));
  });

  test('rejects content that is not the declared kind', () async {
    await expectLater(store.save(7, 'zip', _body(_elf)), throwsA(_status(400)));
    await expectLater(
        store.save(7, 'binary', _body(_zip)), throwsA(_status(400)));
    await expectLater(store.save(7, 'zip', _body([])), throwsA(_status(400)));
    expect(Directory('${root.path}/apps/7').listSync(), isEmpty);
  });

  test('counts the size itself and leaves nothing behind when over', () async {
    await expectLater(store.save(7, 'zip', _body([..._zip, ...List.filled(10, 0)])),
        throwsA(_status(413)));
    expect(Directory('${root.path}/apps/7').listSync(), isEmpty);
  });

  test('git apps cannot upload', () async {
    await expectLater(store.save(7, 'git', _body(_zip)), throwsA(_status(400)));
  });

  test('rejects malformed ids, including path tricks', () {
    for (final id in ['', '../../etc/passwd', 'ABCDEF', '${'a' * 31}/']) {
      expect(store.resolve(7, id, 'zip'), isNull, reason: id);
    }
  });

  test('ignores a symlink planted under the app directory', () {
    final id = 'b' * 32;
    Directory('${root.path}/apps/7').createSync(recursive: true);
    Link('${root.path}/apps/7/$id.zip').createSync('/etc/hostname');
    expect(store.resolve(7, id, 'zip'), isNull);
  });

  test('keeps only the newest uploads per app', () async {
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      ids.add(await store.save(7, 'zip', _body(_zip)));
      // Distinct modification times for the ordering.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(store.resolve(7, ids[0], 'zip'), isNull);
    expect(store.resolve(7, ids[1], 'zip'), isNotNull);
    expect(store.resolve(7, ids[2], 'zip'), isNotNull);
  });

  test('reports unwritable storage as 503', () async {
    final blocked = ArtifactStore(root: '${root.path}/file/sub');
    File('${root.path}/file').writeAsStringSync('');
    await expectLater(
        blocked.save(7, 'zip', _body(_zip)), throwsA(_status(503)));
  });
}
