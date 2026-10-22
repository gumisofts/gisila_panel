import 'dart:io';

import 'package:gisila_agent/generators/systemd_unit.dart';
import 'package:gisila_agent/runtime/exec_resolver.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String workDir;
  late String src;
  late String nodeBin;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gisila-exec-');
    workDir = tmp.path;
    src = '$workDir/current/src';
    nodeBin = '$workDir/current/.runtime/bin';
    Directory(nodeBin).createSync(recursive: true);
    Directory('$src/node_modules/.bin').createSync(recursive: true);
    // ELF-like dummy: no shebang, so it is not wrapped in another interpreter.
    File('$nodeBin/node').writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46]);
    File('$nodeBin/npm').writeAsStringSync('#!/usr/bin/env node\n');
    File('$src/node_modules/.bin/next').writeAsStringSync('#!/usr/bin/env node\n');
    File('$src/node_modules/.bin/esbuild').writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46]);
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  ExecResolver nodeResolver({List<String> extraBinDirs = const []}) =>
      ExecResolver.forRuntime(
        'node',
        workDir: workDir,
        src: src,
        extraBinDirs: extraBinDirs,
      );

  test('rewrites bare node to the pinned runtime binary', () {
    final got = nodeResolver().resolve(
      'node $src/node_modules/.bin/next start -p 3040',
      workingDirectory: src,
    );
    expect(
      got,
      '$nodeBin/node $src/node_modules/.bin/next start -p 3040',
    );
  });

  test('hands next shim to the absolute node interpreter', () {
    final got = nodeResolver().resolve(
      'next start -p 3000',
      workingDirectory: src,
    );
    expect(got, '$nodeBin/node $src/node_modules/.bin/next start -p 3000');
  });

  test('rewrites npm start through the pinned node (env shebang)', () {
    final got = nodeResolver().resolve(
      'npm start',
      workingDirectory: src,
    );
    expect(got, '$nodeBin/node $nodeBin/npm start');
  });

  test('leaves a compiled node_modules binary as an absolute path', () {
    final got = nodeResolver().resolve(
      'esbuild --serve',
      workingDirectory: src,
    );
    expect(got, '$src/node_modules/.bin/esbuild --serve');
  });

  test('resolves pnpm from extraBinDirs', () {
    final pnpmDir = '$workDir/.pnpm/bin';
    Directory(pnpmDir).createSync(recursive: true);
    File('$pnpmDir/pnpm').writeAsStringSync('#!/usr/bin/env node\n');
    final got = nodeResolver(extraBinDirs: [pnpmDir]).resolve(
      'pnpm start',
      workingDirectory: src,
    );
    expect(got, '$nodeBin/node $pnpmDir/pnpm start');
  });

  test('leaves an unknown bare name untouched', () {
    expect(
      nodeResolver().resolve('some-unknown-tool --flag', workingDirectory: src),
      'some-unknown-tool --flag',
    );
  });

  test('rewrites bun to the .runtime binary', () {
    final bunTmp = Directory.systemTemp.createTempSync('gisila-bun-');
    addTearDown(() => bunTmp.deleteSync(recursive: true));
    final bunWork = bunTmp.path;
    final bunSrc = '$bunWork/current/src';
    Directory(bunSrc).createSync(recursive: true);
    File('$bunWork/current/.runtime').writeAsBytesSync([0x7f, 0x45, 0x4c, 0x46]);
    final got = ExecResolver.forRuntime('bun', workDir: bunWork, src: bunSrc)
        .resolve('bun run start', workingDirectory: bunSrc);
    expect(got, '$bunWork/current/.runtime run start');
  });

  test('systemd unit ExecStart is absolute and sets ExecSearchPath', () {
    final unit = SystemdUnit(
      appId: 1,
      linuxUser: 'app_jicx78',
      workDir: workDir,
      startCommand: 'node $src/node_modules/.bin/next start -p 3040',
      port: 3040,
      isJit: true,
      runtimeBinDir: nodeBin,
      execResolver: nodeResolver(),
    ).render();
    expect(
      unit,
      contains(
        'ExecStart=$nodeBin/node $src/node_modules/.bin/next start -p 3040',
      ),
    );
    expect(unit, contains('ExecSearchPath=$nodeBin'));
    expect(unit, contains('Environment=PATH=$nodeBin:'));
    expect(unit, isNot(contains('ExecStart=node ')));
  });
}
