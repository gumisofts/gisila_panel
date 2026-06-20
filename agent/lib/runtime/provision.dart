import 'dart:io';

import 'package:gisila_agent/generators/env_file.dart';
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

  /// Create /srv/apps/<user>/{current,releases,shared,tmp,logs,.corepack} with
  /// 0750.
  ///
  /// `.corepack` is the COREPACK_HOME for Node/pnpm apps and is listed in the
  /// systemd unit's `ReadWritePaths=`. systemd requires every `ReadWritePaths=`
  /// target to exist before it sets up the mount namespace, so a missing
  /// `.corepack` makes the service fail with `status=226/NAMESPACE`. Creating
  /// it for every app is harmless for non-Node runtimes (it stays empty).
  static Future<void> ensureWorkDir(String workDir, String user) async {
    final root = Directory(workDir);
    if (!root.existsSync()) root.createSync(recursive: true);
    for (final sub in ['current', 'releases', 'shared', 'tmp', 'logs', '.corepack']) {
      final d = Directory('${root.path}/$sub');
      if (!d.existsSync()) d.createSync(recursive: true);
    }
    await ShellExec.run('chown', ['-R', '$user:$user', workDir]);
    await ShellExec.run('chmod', ['-R', '0750', workDir]);

    // The apps root (parent of workDir, e.g. /srv/apps) must be traversable by
    // the unprivileged app user so that absolute paths into its own work dir
    // resolve — both during the build (python -m venv resolves abs paths) and
    // at runtime (systemd ExecStart uses absolute paths). Granting only the
    // execute bit (o+x → 0751) allows traversal without letting app users list
    // or read sibling apps' directories (each is 0750, owner-only).
    final parent = root.parent.path;
    await ShellExec.run('chmod', ['o+x', parent]);
  }

  /// Write the app's env file referenced by each unit's `EnvironmentFile=`.
  ///
  /// Holds every user-defined env var so the running service — and a developer
  /// running `manage.py` by hand after `set -a; source .env` — see the same
  /// configuration. Owned by the app user and 0640 (readable by the user, not
  /// world). Called with an empty map during provisioning (so the
  /// `EnvironmentFile=` reference never dangles before the first deploy) and
  /// with the real vars during apply-unit.
  ///
  /// [onlyIfMissing] makes the write a no-op when `.env` already exists. The
  /// provisioning step passes this so it lays down a placeholder ONLY on the
  /// very first deploy and never clobbers an env file that a previous
  /// apply-unit already populated. Without it, every redeploy would reset
  /// `.env` to empty between provision and apply-unit — and if the build failed
  /// in between (so apply-unit never ran), the app would be left with an empty
  /// `.env`, breaking console management commands that source it.
  static Future<void> ensureEnvFile(
      String workDir, String user, Map<String, String> envVars,
      {bool onlyIfMissing = false}) async {
    final file = File('$workDir/.env');
    if (onlyIfMissing && file.existsSync()) return;
    file.writeAsStringSync(renderEnvFile(envVars));
    await ShellExec.run('chown', ['$user:$user', file.path]);
    await ShellExec.run('chmod', ['0640', file.path]);
  }
}
