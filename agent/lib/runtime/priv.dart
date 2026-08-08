import 'dart:io';

/// Privileged-command helpers shared by the modular engine/service handlers
/// (e.g. `databases/mongodb.dart`, `services/mongo_express.dart`).
///
/// These mirror the private helpers in `bin/gisila-agent.dart` so a new engine
/// or service can live in its own library file without re-implementing the
/// root-vs-sudo dance. The key subtlety [isRoot] captures: when the worker
/// launches the agent directly as root we must NOT use `sudo` — many hosts set
/// the kernel `no_new_privileges` flag, which blocks sudo even for root.
class Priv {
  Priv._();

  static final bool isRoot = () {
    try {
      final r = Process.runSync('id', ['-u']);
      return r.exitCode == 0 && (r.stdout as String).trim() == '0';
    } catch (_) {
      return false;
    }
  }();

  /// Build a command list, prepending `sudo` only when not already root.
  static List<String> wrap(String exe, List<String> args) =>
      isRoot ? [exe, ...args] : ['sudo', exe, ...args];

  /// Run a privileged command — directly when root, otherwise via sudo.
  static Future<void> sudo(String exe, List<String> args,
      {bool failOk = false}) async {
    final cmd = wrap(exe, args);
    final res = await Process.run(cmd.first, cmd.skip(1).toList());
    if (res.exitCode != 0 && !failOk) {
      throw Exception('$exe exited ${res.exitCode}: ${res.stderr}'.trim());
    }
  }

  /// Run a privileged command and return its trimmed stdout.
  static Future<String> capture(String exe, List<String> args,
      {bool failOk = false}) async {
    final cmd = wrap(exe, args);
    final res = await Process.run(cmd.first, cmd.skip(1).toList());
    if (res.exitCode != 0 && !failOk) {
      throw Exception('$exe exited ${res.exitCode}: ${res.stderr}'.trim());
    }
    return (res.stdout as String? ?? '').trim();
  }

  /// `apt-get update` with [DEBIAN_FRONTEND]=noninteractive.
  ///
  /// Always set the frontend: the agent has no TTY, and Debian otherwise
  /// dumps Dialog/Readline/Teletype fallback noise into stderr.
  static Future<void> aptUpdate({bool failOk = false}) async {
    final cmd = wrap('sh', [
      '-c',
      'DEBIAN_FRONTEND=noninteractive apt-get update -qq',
    ]);
    final res = await Process.run(cmd.first, cmd.skip(1).toList());
    if (res.exitCode != 0 && !failOk) {
      throw Exception('apt-get update failed: ${res.stderr}'.trim());
    }
  }

  /// Install one or more apt packages non-interactively.
  static Future<void> aptInstall(List<String> packages) async {
    if (packages.isEmpty) return;
    final cmd = wrap('sh', [
      '-c',
      'DEBIAN_FRONTEND=noninteractive apt-get -qq -y '
          '-o Dpkg::Options::=--force-confdef '
          '-o Dpkg::Options::=--force-confold '
          'install ${packages.join(' ')}',
    ]);
    final res = await Process.run(cmd.first, cmd.skip(1).toList());
    if (res.exitCode != 0) {
      throw Exception('apt-get install failed: ${res.stderr}'.trim());
    }
  }

  /// Map of common CLI tools → apt package names on Debian/Ubuntu.
  static const hostToolPackages = <String, String>{
    'git': 'git',
    'curl': 'curl',
    'wget': 'wget',
    'unzip': 'unzip',
    'tar': 'tar',
    'make': 'make',
    'gcc': 'build-essential',
    'g++': 'build-essential',
    'gpg': 'gnupg',
    'ca-certificates': 'ca-certificates',
  };

  /// Ensure [commands] are on PATH, installing the matching apt packages when
  /// missing. Idempotent and safe on headless Debian/Ubuntu hosts.
  static Future<void> ensureCmds(List<String> commands) async {
    final needed = <String>{};
    for (final cmd in commands) {
      final pkg = hostToolPackages[cmd] ?? cmd;
      if (cmd == 'ca-certificates') {
        final has = await Process.run('sh', [
          '-c',
          'dpkg-query -W -f=\${Status} ca-certificates 2>/dev/null | grep -q "install ok installed"',
        ]);
        if (has.exitCode != 0) needed.add(pkg);
        continue;
      }
      final has = await Process.run('sh', ['-c', 'command -v ${shq(cmd)}']);
      if (has.exitCode != 0) needed.add(pkg);
    }
    if (needed.isEmpty) return;
    await aptUpdate(failOk: true);
    await aptInstall(needed.toList());
  }

  /// Read a single KEY from `/etc/os-release` without polluting the environment.
  static Future<String> osReleaseGet(String key) async {
    final file = File('/etc/os-release');
    if (!file.existsSync()) return '';
    for (final line in await file.readAsLines()) {
      final i = line.indexOf('=');
      if (i <= 0) continue;
      if (line.substring(0, i) != key) continue;
      var val = line.substring(i + 1).trim();
      if (val.length >= 2 && val.startsWith('"') && val.endsWith('"')) {
        val = val.substring(1, val.length - 1);
      } else if (val.length >= 2 && val.startsWith("'") && val.endsWith("'")) {
        val = val.substring(1, val.length - 1);
      }
      return val;
    }
    return '';
  }

  /// Debian/Ubuntu apt-repo target derived from `/etc/os-release`.
  ///
  /// Used for third-party repos (MongoDB, PGDG, …) so we never depend on
  /// `lsb_release` (often missing on minimal images) and never source
  /// `/etc/os-release` into the process environment.
  static Future<({String id, String codename})> aptOsTarget() async {
    final id = (await osReleaseGet('ID')).toLowerCase();
    final idLike = (await osReleaseGet('ID_LIKE')).toLowerCase();
    final codename = (await osReleaseGet('VERSION_CODENAME')).trim();
    if (codename.isEmpty) {
      throw Exception('Cannot detect OS codename from /etc/os-release');
    }
    // Ubuntu lists ID_LIKE=debian, so check ubuntu first.
    if (id == 'ubuntu' || idLike.contains('ubuntu')) {
      return (id: 'ubuntu', codename: codename);
    }
    if (id == 'debian' || idLike.contains('debian')) {
      return (id: 'debian', codename: codename);
    }
    throw Exception(
      'Unsupported OS for apt third-party repos (need Debian/Ubuntu); got ID=$id',
    );
  }

  /// Write [content] to a privileged [path] using `tee`.
  static Future<void> writeFile(String path, String content) async {
    final cmd = wrap('tee', [path]);
    final proc = await Process.start(cmd.first, cmd.skip(1).toList());
    proc.stdin.write(content);
    await proc.stdin.close();
    await proc.stdout.drain<void>();
    final exit = await proc.exitCode;
    if (exit != 0) throw Exception('tee $path failed with exit $exit');
  }

  /// Read a privileged file, or null when it cannot be read.
  static Future<String?> readFile(String path) async {
    final cmd = wrap('cat', [path]);
    final res = await Process.run(cmd.first, cmd.skip(1).toList());
    if (res.exitCode != 0) return null;
    return res.stdout as String?;
  }

  /// Open a TCP port on the host firewall (no-op when ufw is absent).
  static Future<void> ufwAllow(int port) async {
    final has = await Process.run('sh', ['-c', 'command -v ufw']);
    if (has.exitCode != 0) return;
    await sudo('ufw', ['allow', '$port/tcp'], failOk: true);
  }

  /// Close a previously-opened TCP port on the host firewall.
  static Future<void> ufwDeny(int port) async {
    final has = await Process.run('sh', ['-c', 'command -v ufw']);
    if (has.exitCode != 0) return;
    await sudo('ufw', ['delete', 'allow', '$port/tcp'], failOk: true);
  }

  /// Single-quote a string for safe embedding in a `bash -c` command line.
  static String shq(String s) => "'${s.replaceAll("'", r"'\''")}'";
}
