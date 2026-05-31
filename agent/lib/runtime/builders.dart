import 'dart:io';

import 'package:gisila_agent/runtime/exec.dart';

/// Per-runtime build / fetch routines. Each helper leaves the latest source
/// in `<workDir>/releases/current_build/` and (for compiled runtimes) the
/// final executable under `<workDir>/current/app`.
class Builders {
  static Future<void> fromGit({
    required String workDir,
    required String user,
    required String url,
    String? branch,
    String? deployKeyPath,
  }) async {
    final src = '$workDir/releases/current_build';
    await ShellExec.run('rm', ['-rf', src]);

    // Build the environment; if a deploy key is provided, configure ssh-agent
    // wrapper so `git clone` authenticates with that key.
    final Map<String, String> env;
    if (deployKeyPath != null && File(deployKeyPath).existsSync()) {
      env = {
        ...Platform.environment,
        'GIT_SSH_COMMAND':
            'ssh -i $deployKeyPath -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null',
      };
    } else {
      env = Platform.environment;
    }

    await ShellExec.run(
        'git',
        [
          'clone',
          '--depth',
          '1',
          if (branch != null) ...['--branch', branch],
          url,
          src,
        ],
        env: env);
    await ShellExec.run('chown', ['-R', '$user:$user', src]);
  }

  static Future<void> fromZip({
    required String workDir,
    required String user,
    required String zipPath,
  }) async {
    final src = '$workDir/releases/current_build';
    await ShellExec.run('rm', ['-rf', src]);
    Directory(src).createSync(recursive: true);
    await ShellExec.run('unzip', ['-q', '-d', src, zipPath]);
    await ShellExec.run('chown', ['-R', '$user:$user', src]);
  }

  static Future<void> buildDart({
    required String workDir,
    required String user,
    String? buildCommand,
  }) async {
    final src = '$workDir/releases/current_build';
    final cmd = buildCommand ??
        'dart pub get && dart compile exe bin/server.dart -o build/app';
    await _runAsUser(user, src, cmd);
    await ShellExec.run('install', [
      '-m',
      '0755',
      '-o',
      user,
      '-g',
      user,
      '$src/build/app',
      '$workDir/current/app',
    ]);
  }

  static Future<void> buildGo({
    required String workDir,
    required String user,
    String? buildCommand,
  }) async {
    final src = '$workDir/releases/current_build';
    final cmd = buildCommand ?? 'go build -o build/app ./...';
    await _runAsUser(user, src, cmd);
    await ShellExec.run('install', [
      '-m',
      '0755',
      '-o',
      user,
      '-g',
      user,
      '$src/build/app',
      '$workDir/current/app',
    ]);
  }

  static Future<void> buildRust({
    required String workDir,
    required String user,
    String? buildCommand,
  }) async {
    final src = '$workDir/releases/current_build';
    final cmd = buildCommand ?? 'cargo build --release';
    await _runAsUser(user, src, cmd);
    // Cargo emits binaries under target/release/<crate-name>; we expect the
    // start_command to point at the right one.
  }

  static Future<void> buildNode({
    required String workDir,
    required String user,
    String? buildCommand,
  }) async {
    final src = '$workDir/releases/current_build';
    final cmd = buildCommand ?? 'npm ci';
    await _runAsUser(user, src, cmd);
  }

  /// Build a Python app using pyenv + venv.
  ///
  /// Steps (when no [buildCommand] override is supplied):
  ///   1. Ensure pyenv is installed at [pyenvRoot] (default /opt/pyenv).
  ///   2. Install the requested [pythonVersion] if not present.
  ///   3. Create a virtualenv at `<src>/.venv` using that Python.
  ///   4. `pip install` deps from requirements.txt (if present).
  ///   5. Install gunicorn + uvicorn[standard] for serving.
  ///   6. Symlink `.venv` → `<workDir>/current/.venv` so the systemd unit
  ///      can always reference `<workDir>/current/.venv/bin/gunicorn`.
  static Future<void> buildPython({
    required String workDir,
    required String user,
    String? buildCommand,
    String? pythonVersion,
    String pyenvRoot = '/opt/pyenv',
  }) async {
    final src = '$workDir/releases/current_build';
    final venv = '$src/.venv';
    final currentVenv = '$workDir/current/.venv';

    if (buildCommand != null) {
      // Custom build command — run it verbatim and assume the user knows what
      // they're doing (venv setup included).
      await _runAsUser(user, src, buildCommand);
    } else {
      final version = pythonVersion?.trim();

      // 1 + 2. Ensure pyenv and the requested version.
      await _ensurePyenv(pyenvRoot);
      final pythonBin = version != null
          ? await _pyenvPython(pyenvRoot, version)
          : 'python3'; // fallback to system python3

      // 3. Create virtualenv.
      await _runAsUser(user, src, '$pythonBin -m venv .venv');

      // 4. Install app dependencies.
      final hasDeps = File('$src/requirements.txt').existsSync();
      if (hasDeps) {
        await _runAsUser(user, src,
            '.venv/bin/pip install --no-cache-dir -q -r requirements.txt');
      }

      // 5. Install server dependencies.
      await _runAsUser(
          user,
          src,
          '.venv/bin/pip install --no-cache-dir -q '
          '"gunicorn>=21.0" "uvicorn[standard]>=0.29"');
    }

    // 6. Symlink the venv into <workDir>/current so the systemd ExecStart
    //    path is stable across deployments.
    await ShellExec.run('mkdir', ['-p', '$workDir/current']);
    final link = Link(currentVenv);
    if (link.existsSync()) link.deleteSync();
    await ShellExec.run('ln', ['-sfn', venv, currentVenv]);
    await ShellExec.run('chown', ['-hR', '$user:$user', venv]);
  }

  /// Install pyenv at [root] if absent.
  static Future<void> _ensurePyenv(String root) async {
    if (Directory('$root/bin').existsSync()) return;
    // Clone pyenv.
    await ShellExec.run('git', [
      'clone',
      '--depth',
      '1',
      'https://github.com/pyenv/pyenv.git',
      root,
    ]);
    // Build the bash extension for speed.
    await ShellExec.run(
        'bash', ['-c', 'cd $root && src/configure && make -C src'],
        requireSuccess: false);
  }

  /// Install [version] via pyenv if not present and return the Python binary.
  static Future<String> _pyenvPython(String root, String version) async {
    final versionDir = '$root/versions/$version';
    if (!Directory(versionDir).existsSync()) {
      final env = {
        ...Platform.environment,
        'PYENV_ROOT': root,
        'PATH': '$root/bin:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
      };
      final result = await Process.run(
        '$root/bin/pyenv',
        ['install', '--skip-existing', version],
        environment: env,
      );
      if (result.exitCode != 0) {
        throw Exception('pyenv install $version failed: ${result.stderr}');
      }
    }
    return '$versionDir/bin/python';
  }

  static Future<void> binaryArtifact({
    required String workDir,
    required String user,
    required String artifactPath,
  }) async {
    await ShellExec.run('install', [
      '-m',
      '0755',
      '-o',
      user,
      '-g',
      user,
      artifactPath,
      '$workDir/current/app',
    ]);
  }

  static Future<void> _runAsUser(String user, String cwd, String command) =>
      ShellExec.run(
          'runuser',
          [
            '-u',
            user,
            '--',
            'bash',
            '-lc',
            command,
          ],
          cwd: cwd);
}
