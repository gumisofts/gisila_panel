import 'dart:io';

import 'package:gisila_agent/runtime/builders.dart';
import 'package:test/test.dart';

/// Exercises the real publish → activate → prune cycle on a scratch work dir.
/// Runs as the current user, so ownership changes are no-ops.
void main() {
  late Directory tmp;
  late String workDir;
  final user = Platform.environment['USER'] ?? 'root';

  String read(String path) => File(path).readAsStringSync();
  String link(String path) => Link(path).targetSync();

  /// Simulate a build: new source in the staging tree, a fresh venv
  /// generation behind current/.venv and a new executable at current/app.
  void build(String version) {
    // Unlink-and-create like git/unzip do: releases are hardlinked copies of
    // the staging tree, so writing the old inode in place would change them.
    final src = File('$workDir/releases/current_build/app.txt');
    if (src.existsSync()) src.deleteSync();
    src
      ..createSync(recursive: true)
      ..writeAsStringSync(version);
    final venv = Directory('$workDir/venv/${version.hashCode.abs()}')
      ..createSync(recursive: true);
    Directory('$workDir/current').createSync(recursive: true);
    final venvLink = Link('$workDir/current/.venv');
    if (venvLink.existsSync()) venvLink.deleteSync();
    venvLink.createSync(venv.path);
    // Replace by rename, as _installExecutable does.
    File('$workDir/current/.app.new').writeAsStringSync('bin-$version');
    File('$workDir/current/.app.new').renameSync('$workDir/current/app');
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gisila_release_test_');
    workDir = tmp.path;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('rollback restores code, executable and venv without a rebuild',
      () async {
    build('v1');
    await Builders.publishRelease(
        workDir: workDir, user: user, releaseId: '1', keepIds: {'1'});
    final venv1 = link('$workDir/current/.venv');

    build('v2');
    await Builders.publishRelease(
        workDir: workDir, user: user, releaseId: '2', keepIds: {'2', '1'});
    expect(read('$workDir/current/src/app.txt'), 'v2');
    expect(read('$workDir/current/app'), 'bin-v2');

    await Builders.activateRelease(
        workDir: workDir, user: user, releaseId: '1');
    expect(link('$workDir/current/src'), '$workDir/releases/1');
    expect(read('$workDir/current/src/app.txt'), 'v1');
    expect(read('$workDir/current/app'), 'bin-v1');
    expect(link('$workDir/current/.venv'), venv1);
    // The snapshot itself is untouched by the restore.
    expect(read('$workDir/releases/1/${Builders.releaseMetaDir}/app'),
        'bin-v1');
  });

  test('prune keeps only the listed releases plus the previously live one',
      () async {
    for (final id in ['1', '2', '3']) {
      build('v$id');
      await Builders.publishRelease(
          workDir: workDir, user: user, releaseId: id, keepIds: {id});
    }
    // Release 2 was live until 3 was published, so it survives that prune.
    expect(Directory('$workDir/releases/1').existsSync(), isFalse);
    expect(Directory('$workDir/releases/2').existsSync(), isTrue);
    expect(Directory('$workDir/releases/3').existsSync(), isTrue);
    expect(Directory('$workDir/releases/current_build').existsSync(), isTrue);

    await expectLater(
      Builders.activateRelease(workDir: workDir, user: user, releaseId: '1'),
      throwsA(isA<StateError>()),
    );
  });

  test('a release whose venv was pruned is refused before anything changes',
      () async {
    build('v1');
    await Builders.publishRelease(
        workDir: workDir, user: user, releaseId: '1', keepIds: {'1'});
    build('v2');
    await Builders.publishRelease(
        workDir: workDir, user: user, releaseId: '2', keepIds: {'2', '1'});
    Directory(link('$workDir/releases/1/${Builders.releaseMetaDir}/venv'))
        .deleteSync(recursive: true);

    await expectLater(
      Builders.activateRelease(workDir: workDir, user: user, releaseId: '1'),
      throwsA(isA<StateError>()),
    );
    expect(link('$workDir/current/src'), '$workDir/releases/2');
    expect(read('$workDir/current/app'), 'bin-v2');
  });
}
