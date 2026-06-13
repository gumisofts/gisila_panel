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
    String? dartVersion,
  }) async {
    final src = '$workDir/releases/current_build';
    final dart = dartVersion != null
        ? await _ensureDartSdk(dartVersion)
        : 'dart';
    final cmd = buildCommand ??
        '$dart pub get && $dart compile exe bin/server.dart -o build/app';
    await _runAsUser(user, src, cmd);
    await ShellExec.run('install', [
      '-m', '0755', '-o', user, '-g', user,
      '$src/build/app',
      '$workDir/current/app',
    ]);
  }

  static Future<void> buildGo({
    required String workDir,
    required String user,
    String? buildCommand,
    String? goVersion,
  }) async {
    final src = '$workDir/releases/current_build';
    final goEnv = goVersion != null ? await _ensureGo(goVersion) : null;
    // When a versioned Go is available, prepend its bin dir to PATH.
    final cmd = buildCommand ?? 'go build -o build/app ./...';
    if (goEnv != null) {
      await _runAsUserWithEnv(user, src, cmd, goEnv);
    } else {
      await _runAsUser(user, src, cmd);
    }
    await ShellExec.run('install', [
      '-m', '0755', '-o', user, '-g', user,
      '$src/build/app',
      '$workDir/current/app',
    ]);
  }

  static Future<void> buildRust({
    required String workDir,
    required String user,
    String? buildCommand,
    String? rustVersion,
  }) async {
    final src = '$workDir/releases/current_build';
    await _ensureRustup();
    final toolchain = (rustVersion != null && rustVersion.isNotEmpty)
        ? rustVersion
        : 'stable';
    // Install / update the toolchain
    await ShellExec.run('rustup', ['toolchain', 'install', toolchain],
        requireSuccess: false);
    final cmd = buildCommand ??
        'rustup run $toolchain cargo build --release';
    await _runAsUser(user, src, cmd);
    // Cargo emits binaries under target/release/<crate-name>; start_command
    // must point at the right one.
  }

  static Future<void> buildNode({
    required String workDir,
    required String user,
    String? buildCommand,
    String? nodeVersion,
  }) async {
    final src = '$workDir/releases/current_build';

    // 1. Detect the package manager from lock files before the build starts.
    //    This determines the default install command and whether corepack is
    //    needed.  If the caller supplies a buildCommand we still log the
    //    detected manager for observability.
    final pkgMgr = _detectNodePackageManager(src);
    stdout.writeln('[agent] detected Node.js package manager: $pkgMgr');

    // 2. Optionally set up a pinned Node.js version via fnm.
    Map<String, String>? env;
    if (nodeVersion != null) {
      env = await _ensureFnmNode(nodeVersion);
      // Stable symlink so the systemd unit can prepend the right bin dir to PATH.
      final nodeInstallDir =
          '/opt/fnm/node-versions/v$nodeVersion/installation';
      await ShellExec.run('mkdir', ['-p', '$workDir/current']);
      await ShellExec.run('ln', [
        '-sfn', nodeInstallDir, '$workDir/current/.runtime'
      ], requireSuccess: false);
    }

    // 3. Neutralise corepack.  Its shims intercept package-manager calls and
    //    try to download the version pinned in package.json's `packageManager`
    //    field into the user's home cache, which the unprivileged app user may
    //    not be able to write to.  We defuse it without removing any shims:
    //      COREPACK_ENABLE_STRICT=0          — fall back to the system PM rather
    //                                          than erroring when `packageManager`
    //                                          doesn't match.
    //      COREPACK_ENABLE_AUTO_PIN=0         — do NOT write/modify the
    //                                          `packageManager` field in
    //                                          package.json during the build.
    //                                          Without this, corepack silently
    //                                          mutates the project's package.json
    //                                          with the latest pnpm version tag,
    //                                          which may require a newer Node than
    //                                          what is installed (e.g. pnpm@11.5.2
    //                                          requires Node ≥22.13 but the host
    //                                          may be on 22.12).
    //      COREPACK_HOME=$workDir/.corepack  — cache under the app's workdir.
    final nodeEnv = <String, String>{
      'COREPACK_ENABLE_STRICT': '0',
      'COREPACK_ENABLE_AUTO_PIN': '0',
      'COREPACK_HOME': '$workDir/.corepack',
    };
    final installEnv = env != null
        ? {...env, ...nodeEnv}
        : {...Platform.environment, ...nodeEnv};

    // 4. pnpm 10+ ignores dependency build scripts (Prisma, esbuild, sharp, …)
    //    by default and aborts with ERR_PNPM_IGNORED_BUILDS.  Approving them
    //    non-interactively is the only viable path for an automated deploy.
    //
    //    The setting must live in `pnpm-workspace.yaml` as `dangerouslyAllowAllBuilds`:
    //      - pnpm 11 reads pnpm-specific settings ONLY from pnpm-workspace.yaml;
    //        `.npmrc` is auth/registry-only and env vars use the pnpm_config_*
    //        (not npm_config_*) prefix — which is why earlier attempts no-oped.
    //      - pnpm 10.9+ also honours this key in pnpm-workspace.yaml, so a single
    //        file works across both major versions.
    //
    //    We merge rather than overwrite: a repo may already ship a
    //    pnpm-workspace.yaml defining workspace packages.  Appending a
    //    top-level key (at column 0, on its own line) is valid YAML.
    //
    //    Guard: dangerouslyAllowAllBuilds is MUTUALLY EXCLUSIVE with
    //    onlyBuiltDependencies and neverBuiltDependencies — pnpm errors if
    //    more than one build-approval mechanism is present (across all config
    //    sources including .npmrc).  When a project already ships its own
    //    policy we leave it alone; pnpm will honour it without our override.
    if (pkgMgr == 'pnpm') {
      // pnpm merges build-approval config from THREE sources:
      //   1. pnpm-workspace.yaml   (top-level YAML keys)
      //   2. .npmrc                (key=value)
      //   3. package.json          (under the "pnpm" key)
      //
      // dangerouslyAllowAllBuilds, onlyBuiltDependencies, and neverBuiltDependencies
      // are ALL mutually exclusive.  We must check every source before adding
      // dangerouslyAllowAllBuilds, otherwise we trigger
      // ERR_PNPM_CONFIG_CONFLICT_BUILT_DEPENDENCIES.
      //
      // We also clean up stale dangerouslyAllowAllBuilds lines we may have
      // written on a prior deploy (the clone is fresh but the script is re-run
      // during retries / same-session rebuilds), and resolve any
      // onlyBuiltDependencies vs neverBuiltDependencies conflict that the
      // project itself may have left in pnpm-workspace.yaml by keeping the
      // more permissive key (onlyBuiltDependencies = explicit whitelist).
      await _runAsUserWithEnv(
        user,
        src,
        // 1. Remove any dangerouslyAllowAllBuilds line we injected previously
        //    so we start from a clean state on each attempt.
        "sed -i '/^[[:space:]]*dangerouslyAllowAllBuilds/d' pnpm-workspace.yaml 2>/dev/null; "
        // 2. If the workspace yaml has both onlyBuiltDependencies AND
        //    neverBuiltDependencies (project-level misconfiguration), remove
        //    neverBuiltDependencies — the whitelist takes precedence.
        "if grep -qF 'onlyBuiltDependencies' pnpm-workspace.yaml 2>/dev/null && "
        "   grep -qF 'neverBuiltDependencies' pnpm-workspace.yaml 2>/dev/null; then "
        "  sed -i '/neverBuiltDependencies/d' pnpm-workspace.yaml; "
        "fi; "
        // 3. Now add dangerouslyAllowAllBuilds only when no build-approval
        //    policy exists in any of the three config sources pnpm reads.
        "grep -qF 'onlyBuiltDependencies'  pnpm-workspace.yaml 2>/dev/null || "
        "grep -qF 'neverBuiltDependencies' pnpm-workspace.yaml 2>/dev/null || "
        "grep -qF 'onlyBuiltDependencies'  .npmrc 2>/dev/null || "
        "grep -qF 'neverBuiltDependencies' .npmrc 2>/dev/null || "
        "grep -qF 'onlyBuiltDependencies'  package.json 2>/dev/null || "
        "grep -qF 'neverBuiltDependencies' package.json 2>/dev/null || "
        "printf '\\ndangerouslyAllowAllBuilds: true\\n' >> pnpm-workspace.yaml",
        installEnv,
      );
    }

    // 4b. Provide a real, version-pinned pnpm so corepack never runs — neither
    //     during this build nor at service start.
    //
    //     corepack (the `pnpm` shim Node ships) downloads the version pinned in
    //     package.json's `packageManager` field on first use, into a writable
    //     cache. At runtime that fails: the hardened unit has ProtectHome=true,
    //     ProtectSystem=strict and an AppArmor profile, so the download has
    //     nowhere to go and the service crash-loops (EACCES / 226 NAMESPACE).
    //
    //     Instead we resolve the desired pnpm version HERE (build time has
    //     network + no sandbox), install it as a standalone binary into a
    //     shared, version-keyed store, and record its bin dir. `apply-unit`
    //     then prepends that dir to the service PATH, so `pnpm start` invokes
    //     this exact pnpm directly. Multiple apps pinning different versions
    //     coexist in the store and are installed once each.
    if (pkgMgr == 'pnpm') {
      final pnpmVersion = _resolvePnpmVersion(src);
      stdout.writeln('[agent] pnpm $pnpmVersion (corepack-free, shared store)');
      final pnpmBinDir = await _ensurePnpm(pnpmVersion, installEnv);
      // Put the real pnpm first on PATH for the install + build steps below.
      final basePath = installEnv['PATH'] ?? '/usr/local/bin:/usr/bin:/bin';
      installEnv['PATH'] = '$pnpmBinDir:$basePath';
      // Hand the resolved bin dir to apply-unit (separate agent invocation) so
      // the runtime PATH points at the same pnpm. Read back in _applyUnit.
      File('$workDir/.pnpm-bin').writeAsStringSync('$pnpmBinDir\n');
    }

    // 5. Install dependencies.
    final installCmd = _nodeInstallCommand(pkgMgr);
    await _runAsUserWithEnv(user, src, installCmd, installEnv);

    // 5b. Generate Prisma client when a schema is present.
    //
    //     pnpm 10+ skips postinstall scripts unless the package is listed in
    //     onlyBuiltDependencies (or dangerouslyAllowAllBuilds is set).  Many
    //     projects whitelist sharp or esbuild there but forget prisma, so the
    //     generated .prisma/client/ directory is never created and the Next.js
    //     build fails with "Can't resolve '.prisma/client/default'".
    //
    //     We detect the two conventional schema locations and run
    //     `prisma generate` explicitly so it always runs regardless of how the
    //     project configured its build-script policy.
    final schemaPrisma = File('$src/prisma/schema.prisma').existsSync()
        ? '$src/prisma/schema.prisma'
        : File('$src/schema.prisma').existsSync()
            ? '$src/schema.prisma'
            : null;
    if (schemaPrisma != null) {
      stdout.writeln('[agent] Prisma schema found — running prisma generate');
      await _runAsUserWithEnv(
        user,
        src,
        'node_modules/.bin/prisma generate --schema=$schemaPrisma',
        installEnv,
      );
    }

    // 6. Run the caller-supplied build command on top of the freshly installed
    //    node_modules (e.g. `pnpm build`, `npm run build`, `tsc`).
    //    Reuse installEnv so corepack stays neutralised for this step too.
    if (buildCommand != null && buildCommand.trim().isNotEmpty) {
      await _runAsUserWithEnv(user, src, buildCommand, installEnv);
    }
  }

  /// Sniff the source directory for well-known lock files and return the name
  /// of the package manager that owns them.
  ///
  /// Detection order (most-specific first):
  ///  1. `bun.lockb` / `bun.lock`  → **bun**
  ///  2. `pnpm-lock.yaml`          → **pnpm**
  ///  3. `yarn.lock`               → **yarn**
  ///  4. *(fallback)*              → **npm**
  static String _detectNodePackageManager(String srcDir) {
    if (File('$srcDir/bun.lockb').existsSync() ||
        File('$srcDir/bun.lock').existsSync()) {
      return 'bun';
    }
    if (File('$srcDir/pnpm-lock.yaml').existsSync()) return 'pnpm';
    if (File('$srcDir/yarn.lock').existsSync()) return 'yarn';
    return 'npm';
  }

  /// Returns the CI-safe install command for [pkgMgr].
  ///
  /// Each command installs exactly the versions recorded in the lock file and
  /// refuses to modify it (equivalent to `npm ci`).
  static String _nodeInstallCommand(String pkgMgr) {
    switch (pkgMgr) {
      case 'bun':
        return 'bun install --frozen-lockfile';
      case 'pnpm':
        // --frozen-lockfile: refuse to update the lock file (CI-safe).
        // Dependency build scripts (Prisma, esbuild, sharp, …) that pnpm 10+
        // blocks with ERR_PNPM_IGNORED_BUILDS are approved via the
        // npm_config_dangerously_allow_all_builds env var set in buildNode,
        // which also covers the nested install run by `pnpm build`.
        return 'pnpm install --frozen-lockfile';
      case 'yarn':
        // yarn v1 uses --frozen-lockfile; yarn v2+ (Berry) uses --immutable.
        // --frozen-lockfile is universally understood by both versions.
        return 'yarn install --frozen-lockfile';
      default:
        return 'npm ci';
    }
  }

  /// pnpm spec used when a project does not pin one via the package.json
  /// `packageManager` field. pnpm 10 supports Node ≥18.12, so it runs on both
  /// the panel-default Node 22.12 and newer pins. `npm` resolves the bare major
  /// to the latest 10.x at install time.
  static const String _defaultPnpmSpec = '10';

  /// Resolve which pnpm version to install for the project in [src].
  ///
  /// Honors a `"packageManager": "pnpm@X.Y.Z"` pin in package.json so each app
  /// gets exactly the version it expects (this is what corepack would have
  /// fetched); falls back to [_defaultPnpmSpec] when unpinned or unparseable.
  /// A regex avoids a full JSON parse so a malformed package.json never breaks
  /// the deploy — we simply use the default.
  static String _resolvePnpmVersion(String src) {
    final pkg = File('$src/package.json');
    if (pkg.existsSync()) {
      try {
        final m = RegExp(r'"packageManager"\s*:\s*"pnpm@([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.]+)?)')
            .firstMatch(pkg.readAsStringSync());
        if (m != null) return m.group(1)!;
      } catch (_) {/* fall through to the default */}
    }
    return _defaultPnpmSpec;
  }

  /// Ensure a standalone (non-corepack) pnpm [version] exists in the shared
  /// store and return its bin directory (`/opt/pnpm-versions/<version>/bin`).
  ///
  /// Idempotent: an already-installed version is reused, so this is cheap on
  /// repeat deploys and shared across every app pinning the same version. The
  /// install happens at build time (network available, no sandbox); `--prefix`
  /// pins the location regardless of any global npm prefix override.
  static Future<String> _ensurePnpm(
      String version, Map<String, String> env) async {
    final prefix = '/opt/pnpm-versions/$version';
    final binDir = '$prefix/bin';
    if (!File('$binDir/pnpm').existsSync()) {
      await ShellExec.run('mkdir', ['-p', prefix]);
      await ShellExec.run(
        'npm',
        ['install', '-g', '--prefix', prefix, 'pnpm@$version'],
        env: env,
        requireSuccess: false,
      );
    }
    return binDir;
  }

  /// Build a Bun application with optional version pinning.
  ///
  /// Called for runtime=bun. A versioned Bun binary is downloaded once to
  /// `/opt/bun-versions/{version}/bun` and symlinked at
  /// `workDir/current/.runtime` (single binary, no bin/ subdirectory).
  static Future<void> buildBun({
    required String workDir,
    required String user,
    String? buildCommand,
    String? bunVersion,
  }) async {
    final src = '$workDir/releases/current_build';
    Map<String, String>? env;
    if (bunVersion != null) {
      final bunBin = await _ensureBun(bunVersion);
      env = {
        ...Platform.environment,
        'PATH': '${bunBin.parent.path}:${Platform.environment['PATH'] ?? '/usr/local/bin:/usr/bin:/bin'}',
      };
      // Stable symlink for runtime
      await ShellExec.run('mkdir', ['-p', '$workDir/current']);
      await ShellExec.run('ln', [
        '-sfn', bunBin.path, '$workDir/current/.runtime'
      ], requireSuccess: false);
    }
    final cmd = buildCommand ?? 'bun install';
    if (env != null) {
      await _runAsUserWithEnv(user, src, cmd, env);
    } else {
      await _runAsUser(user, src, cmd);
    }
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
      //
      // python-build downloads the CPython source tarball from python.org with
      // a single-shot curl that has no retries, so a transient TCP reset
      // ("curl: (56) Recv failure: Connection reset by peer") aborts the whole
      // deployment. Retry the install a few times with backoff, and tell curl
      // to retry on its own via CURLOPT-style env so partial downloads recover.
      final installEnv = {
        ...env,
        // Honoured by python-build's curl invocation.
        'PYTHON_BUILD_CURL_OPTS': '--retry 5 --retry-delay 2 --retry-all-errors',
        'PYTHON_BUILD_WGET_OPTS': '--tries=5 --waitretry=2',
      };
      const maxAttempts = 3;
      ProcessResult? result;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        result = await Process.run(
          '$root/bin/pyenv',
          ['install', if (installed) '--force' else '--skip-existing', version],
          environment: installEnv,
        );
        stdout.write(result.stdout);
        if (result.exitCode == 0) break;

        final isLast = attempt == maxAttempts;
        if (isLast) {
          throw Exception('pyenv install $version failed after $maxAttempts '
              'attempts: ${result.stderr}');
        }
        stderr.writeln('[agent] pyenv install $version attempt $attempt/'
            '$maxAttempts failed; retrying in ${attempt * 5}s');
        await Future<void>.delayed(Duration(seconds: attempt * 5));
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

  /// Build a Celery app using pyenv + venv.
  ///
  /// Identical to [buildPython] in the setup phase, but installs Celery and
  /// Flower instead of (or in addition to) gunicorn/uvicorn. Django management
  /// commands are still run automatically when `manage.py` is found.
  static Future<void> buildCelery({
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

    await _ensurePythonBuildDeps();
    await _ensurePyenv(pyenvRoot);
    final pythonBin = version != null
        ? await _pyenvPython(pyenvRoot, version)
        : 'python3';

    await _runAsUser(user, src, '$pythonBin -m venv --copies .venv');

    if (buildCommand != null) {
      await _runAsUser(user, src, 'source .venv/bin/activate && $buildCommand');
    } else {
      final hasDeps = File('$src/requirements.txt').existsSync();
      if (hasDeps) {
        await _runAsUser(user, src,
            '.venv/bin/pip install --no-cache-dir -q -r requirements.txt');
      }
    }

    // Always install celery and flower so the generated unit commands work.
    await _runAsUser(
        user,
        src,
        '.venv/bin/pip install --no-cache-dir -q '
        '"celery>=5.3" "flower>=2.0"');

    // Run Django management commands if applicable.
    await _runDjangoManagementCommands(user, src);

    // Symlink venv for stable path in systemd units.
    await ShellExec.run('mkdir', ['-p', '$workDir/current']);
    final link = Link(currentVenv);
    if (link.existsSync()) link.deleteSync();
    await ShellExec.run('ln', ['-sfn', venv, currentVenv]);
    await ShellExec.run('chown', ['-hR', '$user:$user', venv]);
  }

  /// "Build" a static site deployment.
  ///
  /// If a [buildCommand] is provided (e.g. `npm run build`) it is run inside
  /// a Node.js / Bun context after dependencies are installed via [buildNode].
  /// Without a build command the source tree is used as-is (plain HTML/CSS/JS).
  static Future<void> buildStatic({
    required String workDir,
    required String user,
    String? buildCommand,
  }) async {
    if (buildCommand != null && buildCommand.trim().isNotEmpty) {
      // Install deps first (npm ci / bun install), then run the build.
      await buildNode(workDir: workDir, user: user, buildCommand: buildCommand);
    }
    // No compiled binary to install — Nginx will serve the files directly
    // from releases/current_build/<static_root>.
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

  // ── Dart SDK version management ──────────────────────────────────────────

  static const _dartBase = '/opt/dart-versions';

  /// Ensure a specific Dart SDK version is available and return its `dart`
  /// binary path. Downloads and extracts from the official archive if absent.
  static Future<String> _ensureDartSdk(String version) async {
    final dir = '$_dartBase/$version';
    final bin = '$dir/dart-sdk/bin/dart';
    if (File(bin).existsSync()) return bin;

    Directory(dir).createSync(recursive: true);
    stdout.writeln('[agent] Downloading Dart SDK $version…');
    final archive = '$dir/dart-sdk.zip';
    await ShellExec.run('curl', [
      '-fSL', '--output', archive,
      'https://storage.googleapis.com/dart-archive/channels/stable/release/$version/sdk/dartsdk-linux-x64-release.zip',
    ]);
    await ShellExec.run('unzip', ['-q', '-d', dir, archive]);
    await ShellExec.run('rm', ['-f', archive]);
    return bin;
  }

  // ── Go version management ─────────────────────────────────────────────────

  static const _goBase = '/opt/go-versions';

  /// Ensure a specific Go version is installed under [_goBase] and return an
  /// env map with PATH prepended so `go` resolves to that version.
  static Future<Map<String, String>> _ensureGo(String version) async {
    final dir = '$_goBase/$version';
    final bin = '$dir/go/bin/go';
    if (!File(bin).existsSync()) {
      Directory(dir).createSync(recursive: true);
      stdout.writeln('[agent] Downloading Go $version…');
      final archive = '$dir/go.tar.gz';
      await ShellExec.run('curl', [
        '-fSL', '--output', archive,
        'https://go.dev/dl/go$version.linux-amd64.tar.gz',
      ]);
      await ShellExec.run('tar', ['-C', dir, '-xzf', archive]);
      await ShellExec.run('rm', ['-f', archive]);
    }
    final goBin = '$dir/go/bin';
    return {
      ...Platform.environment,
      'PATH': '$goBin:${Platform.environment['PATH'] ?? '/usr/local/bin:/usr/bin:/bin'}',
      'GOROOT': '$dir/go',
    };
  }

  // ── Rust / rustup version management ─────────────────────────────────────

  /// Ensure rustup is installed system-wide (at `/usr/local/rustup`).
  static Future<void> _ensureRustup() async {
    final result = await Process.run('which', ['rustup']);
    if (result.exitCode == 0) return;
    stdout.writeln('[agent] Installing rustup…');
    await ShellExec.run('bash', [
      '-c',
      'curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path',
    ], requireSuccess: false);
  }

  // ── Node.js / fnm version management ─────────────────────────────────────

  static const _fnmDir = '/opt/fnm';
  static const _fnmBin = '/usr/local/bin/fnm';

  /// Ensure fnm is installed at [_fnmBin] and the requested Node version is
  /// available. Returns an env map suitable for `_runAsUserWithEnv`.
  static Future<Map<String, String>> _ensureFnmNode(String version) async {
    // 1. Install fnm if absent.
    if (!File(_fnmBin).existsSync()) {
      stdout.writeln('[agent] Installing fnm…');
      await ShellExec.run('bash', [
        '-c',
        'curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /usr/local/bin --skip-shell',
      ]);
    }

    // 2. Install the requested Node version if absent.
    final nodeDir = '$_fnmDir/node-versions/v$version/installation';
    if (!Directory(nodeDir).existsSync()) {
      stdout.writeln('[agent] Installing Node.js $version via fnm…');
      await ShellExec.run(_fnmBin, [
        'install', version, '--fnm-dir', _fnmDir,
      ]);
    }

    final nodeBin = '$nodeDir/bin';
    return {
      ...Platform.environment,
      'PATH': '$nodeBin:${Platform.environment['PATH'] ?? '/usr/local/bin:/usr/bin:/bin'}',
      'FNM_DIR': _fnmDir,
    };
  }

  // ── Bun version management ────────────────────────────────────────────────

  static const _bunBase = '/opt/bun-versions';

  /// Ensure a specific Bun version binary is available at
  /// `/opt/bun-versions/{version}/bun` and return its [File].
  static Future<File> _ensureBun(String version) async {
    final dir = '$_bunBase/$version';
    final bin = File('$dir/bun');
    if (bin.existsSync()) return bin;

    Directory(dir).createSync(recursive: true);
    stdout.writeln('[agent] Downloading Bun $version…');
    final archive = '$dir/bun-linux-x64.zip';
    await ShellExec.run('curl', [
      '-fSL', '--output', archive,
      'https://github.com/oven-sh/bun/releases/download/bun-v$version/bun-linux-x64.zip',
    ]);
    await ShellExec.run('unzip', ['-q', '-d', dir, archive]);
    // The zip extracts to `bun-linux-x64/bun` — move it up.
    final extracted = File('$dir/bun-linux-x64/bun');
    if (extracted.existsSync()) {
      await ShellExec.run('mv', [extracted.path, bin.path]);
      await ShellExec.run('rm', ['-rf', '$dir/bun-linux-x64']);
    }
    await ShellExec.run('chmod', ['+x', bin.path]);
    await ShellExec.run('rm', ['-f', archive]);
    return bin;
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  static Future<void> _runAsUser(String user, String cwd, String command) =>
      ShellExec.run(
          'runuser',
          ['-u', user, '--', 'bash', '-lc', command],
          cwd: cwd);

  static Future<void> _runAsUserWithEnv(
    String user,
    String cwd,
    String command,
    Map<String, String> env,
  ) =>
      ShellExec.run(
        'runuser',
        ['-u', user, '--', 'bash', '-lc', command],
        cwd: cwd,
        env: env,
      );
}
