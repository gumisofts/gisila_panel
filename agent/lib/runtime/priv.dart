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

  /// Install one or more apt packages non-interactively.
  static Future<void> aptInstall(List<String> packages) async {
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
