import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:gisila_panel/services/webhooks_service.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'hook-secret';
  final body = utf8.encode('{"ref":"refs/heads/main"}');
  final mac = Hmac(sha256, utf8.encode(secret)).convert(body).toString();

  group('WebhooksService.verify', () {
    test('GitHub signs with X-Hub-Signature-256', () {
      expect(
          WebhooksService.verify(
              {'x-hub-signature-256': 'sha256=$mac', 'x-github-event': 'push'},
              body,
              secret),
          'github');
    });

    test('Gitea and Forgejo, with either header', () {
      expect(
          WebhooksService.verify(
              {'x-hub-signature-256': 'sha256=$mac', 'x-gitea-event': 'push'},
              body,
              secret),
          'gitea');
      expect(
          WebhooksService.verify({'x-gitea-signature': mac}, body, secret),
          'gitea');
    });

    test('GitLab sends the secret as X-Gitlab-Token', () {
      expect(WebhooksService.verify({'x-gitlab-token': secret}, body, secret),
          'gitlab');
      expect(WebhooksService.verify({'x-gitlab-token': 'nope'}, body, secret),
          isNull);
    });

    test('a wrong secret, a changed body or no signature fail', () {
      final other =
          Hmac(sha256, utf8.encode('other')).convert(body).toString();
      expect(
          WebhooksService.verify(
              {'x-hub-signature-256': 'sha256=$other'}, body, secret),
          isNull);
      expect(
          WebhooksService.verify({'x-hub-signature-256': 'sha256=$mac'},
              utf8.encode('{"ref":"refs/heads/evil"}'), secret),
          isNull);
      expect(WebhooksService.verify({'x-hub-signature-256': mac}, body, secret),
          isNull, reason: 'GitHub signatures carry the sha256= prefix');
      expect(WebhooksService.verify({}, body, secret), isNull);
    });
  });

  group('WebhooksService.statusUrl', () {
    const sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    test('GitHub uses the payload statuses_url on api.<git host>', () {
      final url = WebhooksService.statusUrl(
          'github',
          {
            'repository': {
              'statuses_url': 'https://api.github.com/repos/o/r/statuses/{sha}'
            }
          },
          sha,
          'git@github.com:o/r.git');
      expect(url.toString(), 'https://api.github.com/repos/o/r/statuses/$sha');
    });

    test('Gitea and GitLab build it from the repository URL', () {
      expect(
          WebhooksService.statusUrl(
                  'gitea',
                  {
                    'repository': {
                      'html_url': 'https://git.example.com/o/r',
                      'full_name': 'o/r'
                    }
                  },
                  sha,
                  'https://git.example.com/o/r.git')
              .toString(),
          'https://git.example.com/api/v1/repos/o/r/statuses/$sha');
      expect(
          WebhooksService.statusUrl(
                  'gitlab',
                  {
                    'project': {
                      'web_url': 'https://gitlab.example.com:8443/g/p',
                      'id': 42
                    }
                  },
                  sha,
                  'ssh://git@gitlab.example.com:2222/g/p.git')
              .toString(),
          'https://gitlab.example.com:8443/api/v4/projects/42/statuses/$sha');
    });

    test('refuses other hosts, plain http and credentials in the URL', () {
      Map<String, Object?> gh(String u) => {
            'repository': {'statuses_url': u}
          };
      for (final u in [
        'https://evil.example.com/repos/o/r/statuses/{sha}',
        'http://api.github.com/repos/o/r/statuses/{sha}',
        'https://user:pw@api.github.com/repos/o/r/statuses/{sha}',
        'https://api.github.com.evil.io/statuses/{sha}',
        'https://127.0.0.1/statuses/{sha}',
      ]) {
        expect(
            WebhooksService.statusUrl(
                'github', gh(u), sha, 'https://github.com/o/r'),
            isNull,
            reason: u);
      }
      expect(
          WebhooksService.statusUrl('github',
              gh('https://api.github.com/repos/o/r/statuses/{sha}'), sha, null),
          isNull,
          reason: 'no git URL to compare with');
    });
  });
}
