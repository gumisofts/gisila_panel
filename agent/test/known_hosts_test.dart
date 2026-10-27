import 'package:gisila_agent/runtime/known_hosts.dart';
import 'package:test/test.dart';

void main() {
  test('reads the SSH host from scp-style and ssh:// URLs', () {
    expect(sshHostOf('git@github.com:org/repo.git'), 'github.com');
    expect(sshHostOf('git@GitLab.com:org/repo.git'), 'gitlab.com');
    expect(sshHostOf('ssh://git@github.com/org/repo.git'), 'github.com');
    expect(sshHostOf('ssh://git@git.example.com:2222/r.git'),
        '[git.example.com]:2222');
    expect(sshHostOf('ssh://git@git.example.com:22/r.git'), 'git.example.com');
    expect(sshHostOf('https://github.com/org/repo.git'), isNull);
  });

  test('pinned hosts accept only the pinned keys', () {
    final opts = sshHostKeyOptions('git@github.com:o/r.git',
        pinnedFile: '/p', appKnownHostsFile: '/a');
    expect(opts, containsAllInOrder(['-o', 'StrictHostKeyChecking=yes']));
    expect(opts, contains('GlobalKnownHostsFile=/p'));
    expect(opts, contains('UserKnownHostsFile=/dev/null'));
    expect(opts.join(' '), isNot(contains('StrictHostKeyChecking=no')));
  });

  test('other hosts are trusted on first use and remembered per app', () {
    final opts = sshHostKeyOptions('git@git.example.com:o/r.git',
        pinnedFile: '/p',
        appKnownHostsFile: '/srv/apps/app_x/.ssh/known_hosts');
    expect(opts, contains('StrictHostKeyChecking=accept-new'));
    expect(
        opts, contains('UserKnownHostsFile=/srv/apps/app_x/.ssh/known_hosts'));
  });

  test('every pinned line is "host type key"', () {
    for (final l in pinnedKnownHosts) {
      expect(l.split(' '), hasLength(3), reason: l);
    }
    expect(pinnedHosts, {'github.com', 'gitlab.com'});
  });
}
