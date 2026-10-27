import 'dart:io';

import 'package:gisila_agent/generators/nginx_vhost.dart';
import 'package:gisila_agent/runtime/applier.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String home;

  setUp(() {
    root = Directory.systemTemp.createTempSync('apps_');
    home = '${root.path}/app_abc123';
    Directory('$home/shared/static').createSync(recursive: true);
    Directory('$home/shared/real').createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  bool plain(String p) => Applier.isPlainAppDir(p, appsRoot: root.path);

  test('a real directory inside an app home is accepted', () {
    expect(plain('$home/shared/static'), isTrue);
  });

  test('a symlink anywhere below the home is refused (PNL-13)', () {
    Link('$home/shared/media').createSync('/etc');
    expect(plain('$home/shared/media'), isFalse);
    Link('$home/linked').createSync('$home/shared');
    expect(plain('$home/linked/real'), isFalse);
  });

  test('paths outside an app home, or with odd segments, are refused', () {
    expect(plain('/etc'), isFalse);
    expect(plain('$home/../app_other1/x'), isFalse);
    expect(plain('$home/shared/static/..'), isFalse);
    expect(plain('${root.path}/not_an_app/x'), isFalse);
    expect(plain('$home/missing'), isFalse);
    Directory('$home/a;b').createSync();
    expect(plain('$home/a;b'), isFalse, reason: 'written into nginx config');
  });

  test('served locations refuse symlinks to files the tenant does not own', () {
    final proxy = NginxVhost(
      appId: 1,
      port: 4000,
      hostnames: ['a.example.com'],
      staticRoot: '/srv/apps/app_abc123/shared/static',
      mediaRoot: '/srv/apps/app_abc123/shared/media',
      protectedMedia: true,
    ).render();
    expect('disable_symlinks if_not_owner;'.allMatches(proxy).length, 3);
    final site = StaticNginxVhost(
      appId: 1,
      staticDir: '/srv/apps/app_abc123/current/web',
      hostnames: ['a.example.com'],
    ).render();
    expect(site, contains('disable_symlinks if_not_owner;'));
  });

  test('a build refuses a work dir whose releases/ was swapped for a link', () {
    // requirePlainAppTree checks /srv/apps paths; exercise the same rule
    // through isPlainAppDir on a temp app home.
    Link('$home/releases').createSync('${root.path}/app_victim1/releases');
    expect(plain('$home/releases'), isFalse);
    expect(() => Applier.requirePlainAppTree('/srv/apps/app_zz9999'),
        returnsNormally,
        reason: 'missing directories are fine (first deploy)');
  });
}
