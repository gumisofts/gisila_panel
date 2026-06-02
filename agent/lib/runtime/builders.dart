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
  ///   1. Ensure Python C-extension build dependencies are installed.
  ///   2. Ensure pyenv is installed at [pyenvRoot] (default /opt/pyenv).
  ///   3. Install the requested [pythonVersion] if not present.
  ///   4. Create a virtualenv at `<src>/.venv` using that Python.
  ///   5. `pip install` deps from requirements.txt (if present).
  ///   6. Install gunicorn + uvicorn[standard] for serving.
  ///   7. Symlink `.venv` → `<workDir>/current/.venv` so the systemd unit
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

    final version = pythonVersion?.trim();

    // 1. Install Python build-time system libraries before pyenv compiles
    //    Python.  If these are absent when `pyenv install` runs, CPython
    //    silently skips the corresponding C extension modules (_sqlite3, _ssl,
    //    _lzma, etc.), leaving them permanently missing from that installation.
    //    apt-get install is idempotent, so this is safe to run every build.
    await _ensurePythonBuildDeps();

    // 2 + 3. Ensure pyenv and the requested version.
    await _ensurePyenv(pyenvRoot);
    final pythonBin = version != null
        ? await _pyenvPython(pyenvRoot, version)
        : 'python3'; // fallback to system python3

    // 3. Create virtualenv (always, even for custom build commands, so that
    //    bare `pip install` calls inside the buildCommand work without hitting
    //    PEP 668's "externally-managed-environment" restriction).
    //
    // --copies is required: without it the venv's bin/python is a symlink to
    // the pyenv binary.  On Linux, Python uses /proc/self/exe to find its real
    // path, which resolves the symlink to /opt/pyenv/…/bin/python3.x.  Python
    // then searches for pyvenv.cfg relative to that resolved path — which has
    // none — so it falls back to treating the pyenv prefix as sys.prefix,
    // leaving the venv's site-packages off sys.path entirely and causing
    // gunicorn / app dependencies to be missing at runtime.
    await _runAsUser(user, src, '$pythonBin -m venv --copies .venv');

    if (buildCommand != null) {
      // 4a. Custom build command — run it with the venv activated so that
      //     plain `pip install` / `python` references resolve into the venv.
      await _runAsUser(user, src, 'source .venv/bin/activate && $buildCommand');
    } else {
      // 4b. Install app dependencies.
      final hasDeps = File('$src/requirements.txt').existsSync();
      if (hasDeps) {
        await _runAsUser(user, src,
            '.venv/bin/pip install --no-cache-dir -q -r requirements.txt');
      }
    }

    // 5. Install server dependencies (always needed for the gunicorn start
    //    command generated by apply-unit).
    await _runAsUser(
        user,
        src,
        '.venv/bin/pip install --no-cache-dir -q '
        '"gunicorn>=21.0" "uvicorn[standard]>=0.29"');

    // 5b. Django out-of-the-box support. A Django project ships a manage.py at
    //     its root; detect it and run the two management commands every Django
    //     deployment needs so the app boots cleanly with no manual steps:
    //       - migrate      → creates/updates the database schema (without this
    //                        the very first request that touches the ORM — admin,
    //                        auth, sessions — raises OperationalError and the
    //                        worker 500s / fails to boot under --preload).
    //       - collectstatic → gathers static assets into STATIC_ROOT.
    //     Both run with the venv active so `python` resolves to the project's
    //     interpreter. They are best-effort: collectstatic is skipped silently
    //     when STATIC_ROOT is not configured, and migrate failures are surfaced
    //     in the build log without aborting the whole deployment.
    await _runDjangoManagementCommands(user, src);

    // 6. Symlink the venv into <workDir>/current so the systemd ExecStart
    //    path is stable across deployments.
    await ShellExec.run('mkdir', ['-p', '$workDir/current']);
    final link = Link(currentVenv);
    if (link.existsSync()) link.deleteSync();
    await ShellExec.run('ln', ['-sfn', venv, currentVenv]);
    await ShellExec.run('chown', ['-hR', '$user:$user', venv]);
  }

  /// Detect a Django project and run its standard deploy-time management
  /// commands. No-op for non-Django Python apps.
  static Future<void> _runDjangoManagementCommands(
      String user, String src) async {
    if (!File('$src/manage.py').existsSync()) return;

    // Confirm Django is actually installed in the venv before invoking
    // manage.py (a stray manage.py without the framework should not fail here).
    final hasDjango = await _runAsUserStatus(
      user,
      src,
      '.venv/bin/python -c "import django"',
    );
    if (hasDjango != 0) return;

    stdout.writeln('[agent] Django project detected — running migrate');
    // migrate is idempotent. Best-effort: a deliberately external DB that is
    // unreachable at build time should not block the release.
    await ShellExec.run(
      'runuser',
      ['-u', user, '--', 'bash', '-lc',
        'source .venv/bin/activate && python manage.py migrate --noinput'],
      cwd: src,
      requireSuccess: false,
    );

    stdout.writeln('[agent] Django project detected — running collectstatic');
    // collectstatic exits non-zero when STATIC_ROOT is unset; that is a valid
    // configuration (e.g. DEBUG=True dev serving), so failures are ignored.
    await ShellExec.run(
      'runuser',
      ['-u', user, '--', 'bash', '-lc',
        'source .venv/bin/activate && '
            'python manage.py collectstatic --noinput'],
      cwd: src,
      requireSuccess: false,
    );
  }

  /// Run a command as [user] in [cwd] and return its exit code without throwing.
  static Future<int> _runAsUserStatus(String user, String cwd, String command) =>
      ShellExec.run(
        'runuser',
        ['-u', user, '--', 'bash', '-lc', command],
        cwd: cwd,
        requireSuccess: false,
      );

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

  /// Ensure [version] is installed via pyenv AND has its core C extension
  /// modules, returning the Python binary path.
  ///
  /// A version directory existing is NOT enough: if Python was compiled when
  /// the build libraries were missing, extensions like `_sqlite3`, `_ssl`, and
  /// `_lzma` are silently omitted and stay broken on every reuse. We therefore
  /// verify the interpreter can import the critical modules and force a rebuild
  /// (`pyenv install --force`) when it cannot — by this point
  /// [_ensurePythonBuildDeps] has already installed the required headers.
  static Future<String> _pyenvPython(String root, String version) async {
    final versionDir = '$root/versions/$version';
    final pythonBin = '$versionDir/bin/python';
    final env = {
      ...Platform.environment,
      'PYENV_ROOT': root,
      'PATH': '$root/bin:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
    };

    final installed = Directory(versionDir).existsSync();
    final healthy = installed && await _pythonExtensionsOk(pythonBin);

    if (!healthy) {
      // Force a clean rebuild when a broken install already exists; otherwise
      // a plain install is enough.
      final result = await Process.run(
        '$root/bin/pyenv',
        ['install', if (installed) '--force' else '--skip-existing', version],
        environment: env,
      );
      stdout.write(result.stdout);
      if (result.exitCode != 0) {
        throw Exception('pyenv install $version failed: ${result.stderr}');
      }
      // Sanity-check the freshly built interpreter so a still-broken build
      // fails the deployment loudly instead of looping at runtime.
      if (!await _pythonExtensionsOk(pythonBin)) {
        throw Exception(
          'Python $version was rebuilt but still lacks required C extension '
          'modules (e.g. _sqlite3). Ensure the build libraries '
          '(libsqlite3-dev, libssl-dev, liblzma-dev, …) are installed on the '
          'host, then redeploy.',
        );
      }
    }
    return pythonBin;
  }

  /// Whether [pythonBin] can import the C extension modules apps commonly need.
  /// Returns false if the binary is missing or any import fails.
  static Future<bool> _pythonExtensionsOk(String pythonBin) async {
    if (!File(pythonBin).existsSync()) return false;
    final result = await Process.run(
      pythonBin,
      ['-c', 'import sqlite3, ssl, lzma, ctypes, zlib, bz2'],
    );
    return result.exitCode == 0;
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

  /// Install the system libraries that CPython needs to compile its C extension
  /// modules (sqlite3, ssl, lzma, readline, etc.).  When these are absent
  /// during `pyenv install`, CPython silently omits the corresponding `.so`
  /// files, producing hard-to-diagnose "No module named '_sqlite3'" errors at
  /// runtime.  Running this before every pyenv call is safe — apt-get is a
  /// no-op when packages are already at the latest version.
  static Future<void> _ensurePythonBuildDeps() async {
    // Refresh package lists first so the install below can't fail because of a
    // stale/empty apt cache (common on minimal VPS images). Best-effort: a
    // failing mirror should not abort the build outright.
    await ShellExec.run('apt-get', ['update', '-qq'], requireSuccess: false);
    await ShellExec.run(
      'apt-get',
      [
        'install', '-y', '-qq',
        'libsqlite3-dev',
        'libssl-dev',
        'zlib1g-dev',
        'libbz2-dev',
        'libreadline-dev',
        'libncursesw5-dev',
        'xz-utils',
        'libxml2-dev',
        'libxmlsec1-dev',
        'libffi-dev',
        'liblzma-dev',
      ],
      requireSuccess: false,
    );
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
