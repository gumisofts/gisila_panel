import 'dart:io';

import 'package:gisila_agent/runtime/exec.dart';

/// Idempotently provisions the Linux user + work dir + base layout for an
/// app. Safe to call repeatedly.
class Provisioner {
  /// Create a system user (no login shell) if it doesn't exist yet.
  static Future<void> ensureLinuxUser(String user) async {
    final result = await Process.run('id', ['-u', user]);
    if (result.exitCode == 0) return;
    await ShellExec.run('useradd', [
      '--system',
      '--no-create-home',
      '--shell',
      '/usr/sbin/nologin',
      user,
    ]);
  }

  /// Create /srv/apps/<user>/{current,releases,shared,tmp} with 0750.
  static Future<void> ensureWorkDir(String workDir, String user) async {
    final root = Directory(workDir);
    if (!root.existsSync()) root.createSync(recursive: true);
    for (final sub in ['current', 'releases', 'shared', 'tmp', 'logs']) {
      final d = Directory('${root.path}/$sub');
      if (!d.existsSync()) d.createSync(recursive: true);
    }
    await ShellExec.run('chown', ['-R', '$user:$user', workDir]);
    await ShellExec.run('chmod', ['-R', '0750', workDir]);
  }

  /// Touch the env file so EnvironmentFile= references don't break the unit.
  static Future<void> ensureEnvFile(String workDir, String user) async {
    final file = File('$workDir/.env');
    if (!file.existsSync())
      file.writeAsStringSync('# managed by gisila-agent\n');
    await ShellExec.run('chown', ['$user:$user', file.path]);
    await ShellExec.run('chmod', ['0640', file.path]);
  }
}
