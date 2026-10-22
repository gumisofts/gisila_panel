import 'package:gisila_agent/generators/nginx_vhost.dart';
import 'package:test/test.dart';

void main() {
  group('uniqueHostnames', () {
    test('trims, lower-cases and drops duplicates', () {
      expect(
        uniqueHostnames([
          'App.Example.com',
          'app.example.com',
          '  other.example.com  ',
          '',
        ]),
        ['app.example.com', 'other.example.com'],
      );
    });
  });

  group('stripHostnamesFromNginxConfig', () {
    test('removes one name from a shared server_name list', () {
      const src = '''
server {
    listen 80;
    server_name first.example.com vse.playbetman.pro;
    return 301 https://\$host\$request_uri;
}
''';
      final out = stripHostnamesFromNginxConfig(src, ['vse.playbetman.pro']);
      expect(out, isNotNull);
      expect(out, contains('server_name first.example.com;'));
      expect(out, isNot(contains('vse.playbetman.pro')));
    });

    test('drops a server block that only served the claimed name', () {
      const src = '''
# leftover
server {
    listen 80;
    server_name vse.playbetman.pro;
    return 301 https://\$host\$request_uri;
}

server {
    listen 80;
    server_name first.example.com;
}
''';
      final out = stripHostnamesFromNginxConfig(src, ['vse.playbetman.pro']);
      expect(out, isNotNull);
      expect(out, contains('first.example.com'));
      expect(out, isNot(contains('vse.playbetman.pro')));
      expect(RegExp(r'\bserver\s*\{').allMatches(out!).length, 1);
    });

    test('returns null when only comments remain', () {
      const src = '''
# Managed by certbot
server {
    listen 80;
    server_name vse.playbetman.pro;
}
''';
      expect(stripHostnamesFromNginxConfig(src, ['vse.playbetman.pro']), isNull);
    });
  });

  group('NginxVhost', () {
    test('emits one HTTP server block per unique hostname', () {
      final conf = NginxVhost(
        appId: 7,
        port: 4100,
        hostnames: [
          'first.example.com',
          'vse.playbetman.pro',
          'VSE.playbetman.pro',
        ],
      ).render();
      expect(
        RegExp(r'server_name first\.example\.com;').allMatches(conf).length,
        1,
      );
      expect(
        RegExp(r'server_name vse\.playbetman\.pro;').allMatches(conf).length,
        1,
      );
      expect(conf, isNot(contains('VSE.playbetman.pro')));
    });
  });
}
