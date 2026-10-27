/// SSH host keys for the big git hosts, so deploy-key clones from them are
/// verified against keys we know rather than whatever the network presents.
///
/// GitHub's come from https://api.github.com/meta (`ssh_keys`); GitLab.com's
/// match the SHA256 fingerprints on https://docs.gitlab.com/user/gitlab_com/.
/// Both were checked against `ssh-keyscan` on 2026-10-28. If a host rotates
/// its keys, update this list: clones from it fail until then.
const pinnedKnownHosts = <String>[
  'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl',
  'github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=',
  'github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=',
  'gitlab.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY=',
  'gitlab.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf',
  'gitlab.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSpIYDEGk9KxsGh3mySTRgMtXL583qmBpzeQ+jqCMRgBqB98u3z++J1sKlXHWfM9dyhSevkMwSbhoR8XIq/U0tCNyokEi/ueaBMCvbcTHhO7FcwzY92WK4Yt0aGROY5qX2UKSeOvuP4D6TPqKF1onrSzH9bx9XUf2lEdWT/ia1NEKjunUqu1xOB/StKDHMoX4/OKyIzuS0q/T1zOATthvasJFoPrAjkohTyaDUz2LN5JoH839hViyEG82yB+MjcFV5MU3N1l1QL3cVUCh93xSaua1N85qivl+siMkPGbO5xR/En4iEY6K2XPASUEMaieWVNTRCtJ4S8H+9',
];

/// Hosts listed in [pinnedKnownHosts].
final pinnedHosts = {for (final l in pinnedKnownHosts) l.split(' ').first};

/// The host a git URL connects to over SSH (`git@host:path`,
/// `ssh://[user@]host[:port]/path`), lowercased; null for other URLs. A
/// non-default port is kept as `[host]:port`, the way known_hosts writes it.
String? sshHostOf(String url) {
  final scp =
      RegExp(r'^[A-Za-z0-9._-]+@([A-Za-z0-9.-]+):(?!//)').firstMatch(url);
  if (scp != null) return scp[1]!.toLowerCase();
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'ssh' || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  return uri.hasPort && uri.port != 22 ? '[$host]:${uri.port}' : host;
}

/// `ssh` options for a clone of [url] with a deploy key.
///
/// Pinned hosts accept only their pinned keys. Any other host is trusted on
/// first use and remembered in [appKnownHostsFile], so a later change of key
/// (someone in the middle) makes the clone fail instead of going through.
List<String> sshHostKeyOptions(
  String url, {
  required String pinnedFile,
  required String appKnownHostsFile,
}) {
  final host = sshHostOf(url);
  if (host != null && pinnedHosts.contains(host)) {
    return [
      '-o',
      'StrictHostKeyChecking=yes',
      '-o',
      'GlobalKnownHostsFile=$pinnedFile',
      '-o',
      'UserKnownHostsFile=/dev/null',
    ];
  }
  return [
    '-o',
    'StrictHostKeyChecking=accept-new',
    '-o',
    'UserKnownHostsFile=$appKnownHostsFile',
  ];
}
