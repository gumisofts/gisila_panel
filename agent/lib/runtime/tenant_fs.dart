import 'dart:convert';
import 'dart:io';

import 'package:gisila_agent/runtime/exec.dart';

/// File operations inside an app's work dir (`/srv/apps/app_*`), done as the
/// app's own Linux user.
///
/// The tenant owns that tree and can replace any directory in it with a
/// symlink at any moment. The agent runs as root, so a root `mkdir`,
/// `chown -R`, `cp` or file write through such a link reaches `/etc` or
/// another tenant's files. Running the operation as the tenant gives it
/// exactly the tenant's own reach, whatever the links point at.
class TenantFs {
  const TenantFs(this.user);

  /// The app's Linux user.
  final String user;

  static final String runuserPath = const [
    '/usr/sbin/runuser',
    '/sbin/runuser',
    '/usr/bin/runuser',
  ].firstWhere((p) => File(p).existsSync(), orElse: () => '/usr/sbin/runuser');

  /// Whether the agent runs as root. Without root it is already an
  /// unprivileged user and can't switch to another (tests, dev mode), so
  /// commands run as it is.
  static final bool _isRoot = () {
    try {
      return (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
    } on Object {
      return false;
    }
  }();

  List<String> _as(List<String> args) =>
      _isRoot ? [runuserPath, '-u', user, '--', ...args] : args;

  /// Runs [args] (`mkdir`, `rm`, `ln`, `cp`, `mv`, …) as [user].
  Future<int> run(List<String> args, {bool requireSuccess = true}) {
    final cmd = _as(args);
    return ShellExec.run(cmd.first, cmd.skip(1).toList(),
        requireSuccess: requireSuccess);
  }

  /// Writes [contents] to [path] as [user].
  Future<void> writeFile(String path, String contents) async {
    final cmd = _as(['sh', '-c', r'cat > "$1"', 'sh', path]);
    final p = await Process.start(cmd.first, cmd.skip(1).toList());
    p.stdin.add(utf8.encode(contents));
    await p.stdin.close();
    final err = await p.stderr.transform(utf8.decoder).join();
    await p.stdout.drain<void>();
    final code = await p.exitCode;
    if (code != 0) {
      throw StateError('Could not write $path as $user: ${err.trim()}');
    }
  }

  /// Hands [dir] itself (not its contents) to [user] when root made it on an
  /// older deploy, so [run] can create entries in it. Refuses a symlink. A
  /// missing [dir] is left alone.
  Future<void> claim(String dir) async {
    final type = FileSystemEntity.typeSync(dir, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory) {
      throw StateError('$dir must be a plain directory, not a symlink.');
    }
    if (_isRoot) await ShellExec.run('chown', ['-h', '$user:$user', dir]);
  }
}
