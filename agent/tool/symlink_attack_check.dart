/// Root-only check that the agent's file operations in an app's work dir can't
/// be redirected by symlinks the tenant plants (PNL-13, PNL-24).
///
/// DESTRUCTIVE: creates the user app_test01 and writes under /srv/apps and
/// /var/lib/gisila. Run it only in a throwaway container, as root:
///
///   docker run --rm -v "$PWD":/app -w /app dart:stable \
///     sh -c 'dart pub get && dart run tool/symlink_attack_check.dart'
///
/// Prints PASS/FAIL per case and exits non-zero on a failure.
library;

import 'dart:io';
import 'package:gisila_agent/runtime/build_cache.dart';
import 'package:gisila_agent/runtime/builders.dart';

const user = 'app_test01';
const home = '/srv/apps/app_test01';

Future<void> sh(String c) async {
  final r = await Process.run('sh', ['-c', c]);
  if (r.exitCode != 0) throw 'setup failed: $c\n${r.stderr}';
}

String owner(String p) =>
    (Process.runSync('stat', ['-c', '%U', p]).stdout as String).trim();

Future<void> check(String name, Future<void> Function() body) async {
  try {
    await body();
    print('PASS $name');
  } catch (e) {
    print('FAIL $name: $e');
    exitCode = 1;
  }
}

Future<bool> throws(Future<void> Function() f) async {
  try {
    await f();
    return false;
  } catch (_) {
    return true;
  }
}

Future<void> main() async {
  if ((Process.runSync('id', ['-u']).stdout as String).trim() != '0' ||
      !File('/.dockerenv').existsSync()) {
    stderr.writeln('Refusing to run outside a root container (see top).');
    exitCode = 2;
    return;
  }
  await sh('useradd -r -M -d $home -s /usr/sbin/nologin $user');
  await sh(
      'mkdir -p $home/releases/current_build/build && chown -R $user:$user $home && chmod 750 $home');
  await sh(
      'mkdir -p /srv/apps/app_victim1/releases/7 && echo SECRET > /srv/apps/app_victim1/releases/7/secret && chmod 600 /srv/apps/app_victim1/releases/7/secret');
  await sh(
      'printf "#!/bin/sh\\necho hi\\n" > $home/releases/current_build/build/app && echo code > $home/releases/current_build/main.txt && chown -R $user:$user $home/releases');
  // Simulate an older deploy: current/ made by root.
  await sh('mkdir -p $home/current');

  await check('tenant build output installed as current/app', () async {
    await Builders.binaryArtifact(
        workDir: home,
        user: user,
        artifactPath: '$home/releases/current_build/build/app');
    if (owner('$home/current/app') != user)
      throw 'owner ${owner('$home/current/app')}';
    if (owner('$home/current') != user) throw 'current not handed over';
  });

  await check('publish + rollback as the user', () async {
    final r1 = await Builders.publishRelease(
        workDir: home, user: user, releaseId: '1');
    if (Link('$home/current/src').targetSync() != r1) throw 'link';
    if (owner('$r1/main.txt') != user) throw 'release owner';
    await Builders.publishRelease(workDir: home, user: user, releaseId: '2');
    await Builders.activateRelease(workDir: home, user: user, releaseId: '1');
    if (Link('$home/current/src').targetSync() != '$home/releases/1')
      throw 'rollback link';
  });

  await check('trusted upload (root-only file) still installs', () async {
    await sh(
        'mkdir -p /var/lib/gisila/artifacts/apps/7 && printf "#!/bin/sh\\necho up\\n" > /var/lib/gisila/artifacts/apps/7/x.bin && chmod 600 /var/lib/gisila/artifacts/apps/7/x.bin');
    await Builders.binaryArtifact(
        workDir: home,
        user: user,
        artifactPath: '/var/lib/gisila/artifacts/apps/7/x.bin');
    if (!File('$home/current/app').readAsStringSync().contains('echo up'))
      throw 'content';
  });

  await check('ATTACK: artifact symlinked to /etc/shadow is not copied',
      () async {
    await sh(
        'ln -sf /etc/shadow $home/releases/current_build/build/evil && chown -h $user:$user $home/releases/current_build/build/evil');
    final failed = await throws(() => Builders.binaryArtifact(
        workDir: home,
        user: user,
        artifactPath: '$home/releases/current_build/build/evil'));
    if (!failed) throw 'install succeeded';
    if (File('$home/current/app').readAsStringSync().contains('root:'))
      throw 'shadow leaked';
  });

  await check('ATTACK: .build-cache symlinked to /etc does not chown /etc',
      () async {
    await sh(
        'ln -s /etc $home/.build-cache && chown -h $user:$user $home/.build-cache');
    final failed = await throws(() => BuildCache.store(home, user, 'x', 'fp'));
    if (!failed) throw 'store went through';
    if (owner('/etc') != 'root' || owner('/etc/passwd') != 'root')
      throw '/etc chowned!';
    if (File('/etc/x').existsSync()) throw 'wrote /etc/x';
    await sh('rm $home/.build-cache');
  });

  await check('ATTACK: releases/ symlinked to another app is refused',
      () async {
    await sh(
        'mv $home/releases $home/releases.real && ln -s /srv/apps/app_victim1/releases $home/releases && chown -h $user:$user $home/releases');
    final failed = await throws(() =>
        Builders.publishRelease(workDir: home, user: user, releaseId: '9'));
    if (!failed) throw 'publish went through';
    if (owner('/srv/apps/app_victim1/releases/7/secret') != 'root')
      throw 'victim chowned';
    if (Directory('/srv/apps/app_victim1/releases/9').existsSync())
      throw 'wrote into victim';
  });
}
