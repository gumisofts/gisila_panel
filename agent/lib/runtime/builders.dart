import 'dart:io';

import 'package:gisila_agent/runtime/build_cache.dart';
import 'package:gisila_agent/runtime/exec.dart';

/// Per-runtime build / fetch routines. Each helper leaves the latest source
/// in `<workDir>/releases/current_build/` and (for compiled runtimes) the
/// final executable under `<workDir>/current/app`.
class Builders {
  /// Gitignored dependency/build artifacts that are worth preserving across a
  /// source refresh so the cache layer can reuse them. The git fetch path keeps
  /// these implicitly (it never touches ignored files); the zip path has to
  /// stash and restore them explicitly.
  static const _artifactDirs = ['node_modules', '.venv'];

  static Future<void> fromGit({
    required String workDir,
    required String user,
    required String url,
    String? branch,
    String? deployKeyPath,
    bool noCache = false,
  }) async {
    final src = '$workDir/releases/current_build';

    // Build the environment; if a deploy key is provided, configure an ssh
    // wrapper so `git` authenticates with that key (for both clone and fetch).
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

    // Prefer an in-place incremental update of an existing checkout of the SAME
    // remote: `fetch` + `reset --hard` re-points the tree at the new commit
    // while leaving gitignored artifacts (node_modules, .venv, .next/cache, …)
    // untouched, so the install/build steps can reuse them. Any mismatch or git
    // error falls back to a clean shallow clone, which is always correct. A
    // force-rebuild skips the incremental path entirely so the clone wipes
    // every preserved artifact.
    final updated = noCache
        ? false
        : await _tryGitUpdate(src: src, url: url, branch: branch, env: env);
    if (!updated) {
      await ShellExec.run('rm', ['-rf', src]);
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
    }
    await ShellExec.run('chown', ['-R', '$user:$user', src]);
  }

  /// Attempt an in-place shallow update of an existing git checkout at [src].
  /// Returns true only when the tree now reflects the requested ref with its
  /// build artifacts preserved; false (a signal to fall back to a clean clone)
  /// on a missing repo, a different remote, or any git failure.
  static Future<bool> _tryGitUpdate({
    required String src,
    required String url,
    String? branch,
    required Map<String, String> env,
  }) async {
    if (!Directory('$src/.git').existsSync()) return false;
    try {
      // git refuses to operate on a repo owned by another uid ("dubious
      // ownership"); the tree is owned by the app user while the agent runs as
      // root, so scope an explicit safe.directory to every invocation.
      final safe = ['-c', 'safe.directory=$src'];

      // Bail out (→ clean clone) when the remote changed: the preserved
      // artifacts would no longer match the new project.
      final remote = await Process.run(
          'git', [...safe, '-C', src, 'remote', 'get-url', 'origin']);
      if (remote.exitCode != 0 ||
          (remote.stdout as String).trim() != url) {
        return false;
      }

      final ref = (branch != null && branch.isNotEmpty) ? branch : 'HEAD';
      final fetch = await ShellExec.run(
          'git', [...safe, '-C', src, 'fetch', '--depth', '1', 'origin', ref],
          env: env, requireSuccess: false);
      if (fetch != 0) return false;

      final reset = await ShellExec.run(
          'git', [...safe, '-C', src, 'reset', '--hard', 'FETCH_HEAD'],
          requireSuccess: false);
      if (reset != 0) return false;

      // Remove stray tracked-type files left over from the previous commit, but
      // NOT ignored files (no `-x`): node_modules / .venv / framework build
      // caches are all gitignored, so this keeps them for the cache layer.
      await ShellExec.run('git', [...safe, '-C', src, 'clean', '-fd'],
          requireSuccess: false);

      stdout.writeln(
          '[agent] git: incremental update — preserved build artifacts');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> fromZip({
    required String workDir,
    required String user,
    required String zipPath,
    bool noCache = false,
  }) async {
    final src = '$workDir/releases/current_build';
    final stash = '${BuildCache.dir(workDir)}/stash';

    // A zip carries no version history to update in place, so the tree is
    // replaced wholesale. Preserve the dependency artifacts across that wipe so
    // a lock file that hasn't changed still skips the install. The uploaded zip
    // wins if it happens to ship its own node_modules/.venv. A force-rebuild
    // skips the stash so the artifacts are wiped with the rest of the tree.
    if (!noCache) await _stashArtifacts(src, stash);
    await ShellExec.run('rm', ['-rf', src]);
    Directory(src).createSync(recursive: true);
    await ShellExec.run('unzip', ['-q', '-d', src, zipPath]);
    if (!noCache) await _restoreArtifacts(src, stash);
    await ShellExec.run('chown', ['-R', '$user:$user', src]);
  }

  /// Move [_artifactDirs] out of [src] into [stash] before the tree is wiped.
  static Future<void> _stashArtifacts(String src, String stash) async {
    await ShellExec.run('rm', ['-rf', stash], requireSuccess: false);
    var created = false;
    for (final d in _artifactDirs) {
      if (!Directory('$src/$d').existsSync()) continue;
      if (!created) {
        Directory(stash).createSync(recursive: true);
        created = true;
      }
      await ShellExec.run('mv', ['$src/$d', '$stash/$d'],
          requireSuccess: false);
    }
  }

  /// Restore stashed artifacts into the freshly-extracted [src], unless the new
  /// tree already provides its own copy. The stash is removed either way.
  static Future<void> _restoreArtifacts(String src, String stash) async {
    for (final d in _artifactDirs) {
      if (Directory('$stash/$d').existsSync() &&
          !Directory('$src/$d').existsSync()) {
        await ShellExec.run('mv', ['$stash/$d', '$src/$d'],
            requireSuccess: false);
      }
    }
    await ShellExec.run('rm', ['-rf', stash], requireSuccess: false);
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
    Map<String, String>? appEnv,
    bool noCache = false,
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
    //
    //    HOME / npm_config_cache:
    //      `runuser -u <app>` runs under PAM, which sets HOME to the user's
    //      passwd entry (/home/<app>) — a directory that is NEVER created for
    //      panel apps (they live under /srv/apps/<app>). The unprivileged user
    //      cannot mkdir it, so npm/yarn/bun fail to write their cache and logs
    //      with `EACCES: permission denied, mkdir '/home/<app>'` and the whole
    //      `npm ci` aborts. (pnpm dodges this via COREPACK_HOME + shared store.)
    //      We point HOME — and npm's cache explicitly — at the app's workdir,
    //      which the app user owns and can write to. This fixes plain npm/yarn
    //      static builds (e.g. Vite/CRA) the same way COREPACK_HOME fixes pnpm.
    final nodeEnv = <String, String>{
      'COREPACK_ENABLE_STRICT': '0',
      'COREPACK_ENABLE_AUTO_PIN': '0',
      'COREPACK_HOME': '$workDir/.corepack',
      'HOME': workDir,
      'npm_config_cache': '$workDir/.npm',
      'XDG_CACHE_HOME': '$workDir/.cache',
      // Keep `pnpm build` (which runs `pnpm run build`) from doing an
      // interactive deps-status reinstall under `runuser` (no TTY): skip the
      // pre-script check and never prompt to purge node_modules. Deps were just
      // installed with --frozen-lockfile above, so this only suppresses a
      // spurious check, never a needed install. CI=true is pnpm's documented
      // remedy for the no-TTY modules-purge abort and the correct signal for an
      // automated build. Both env prefixes are set because pnpm 11 reads
      // `pnpm_config_*` while pnpm 9/10 read `npm_config_*`.
      'CI': 'true',
      'npm_config_verify_deps_before_run': 'false',
      'pnpm_config_verify_deps_before_run': 'false',
      'npm_config_confirm_modules_purge': 'false',
      'pnpm_config_confirm_modules_purge': 'false',
    };
    // Layer the app's configured env vars (the panel's "env vars" / .env) under
    // the build environment so client-side frameworks bake them into the bundle
    // at build time. Vite (`VITE_*`), CRA (`REACT_APP_*`), Astro, etc. read
    // these prefixed vars from `process.env`; without them the build falls back
    // to its compiled-in defaults (e.g. a default backend URL). appEnv goes
    // BELOW nodeEnv so the infra overrides (HOME, COREPACK_*, npm cache, CI)
    // always win over anything the user may have set with the same name.
    final installEnv = <String, String>{
      ...(env ?? Platform.environment),
      ...?appEnv,
      ...nodeEnv,
    };

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
      final pnpmVersion = _resolvePnpmVersion(src, nodeVersion);
      stdout.writeln('[agent] pnpm $pnpmVersion (corepack-free, shared store)');
      final pnpmBinDir = await _ensurePnpm(pnpmVersion, installEnv);
      // Put the real pnpm first on PATH for the install + build steps below.
      final basePath = installEnv['PATH'] ?? '/usr/local/bin:/usr/bin:/bin';
      installEnv['PATH'] = '$pnpmBinDir:$basePath';
      // Hand the resolved bin dir to apply-unit (separate agent invocation) so
      // the runtime PATH points at the same pnpm. Read back in _applyUnit.
      File('$workDir/.pnpm-bin').writeAsStringSync('$pnpmBinDir\n');
    }

    // 5. Install dependencies — skipped when the lock file and the pinned Node
    //    version are unchanged since the last successful deploy AND the
    //    node_modules tree survived the source refresh. The fingerprint covers
    //    every lock-file flavour plus package.json, so any dependency edit (and
    //    only a dependency edit) forces a reinstall.
    const installKey = 'node-install';
    final installFp = BuildCache.fingerprint([
      '$src/pnpm-lock.yaml',
      '$src/package-lock.json',
      '$src/npm-shrinkwrap.json',
      '$src/yarn.lock',
      '$src/bun.lockb',
      '$src/bun.lock',
      '$src/package.json',
    ], [
      'pm:$pkgMgr',
      'node:${nodeVersion ?? 'system'}',
    ]);
    if (!noCache &&
        BuildCache.isFresh(workDir, installKey, installFp,
            artifact: '$src/node_modules')) {
      stdout.writeln(
          '[agent] dependencies unchanged — reusing cached node_modules');
    } else {
      // Invalidate before installing so an interrupted install can never leave
      // a marker that lets the next deploy skip a now-incomplete node_modules.
      BuildCache.invalidate(workDir, installKey);
      final installCmd = _nodeInstallCommand(pkgMgr);
      await _runAsUserWithEnv(user, src, installCmd, installEnv);
      await BuildCache.store(workDir, user, installKey, installFp);
    }

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

    // 7. Framework post-processing.
    await _postBuildNode(user, src, installEnv);
  }

  /// Per-framework fix-ups that must run after the build but before the service
  /// starts. Currently: Next.js `output: 'standalone'`.
  ///
  /// A standalone build emits a self-contained server at `.next/standalone/`
  /// (with a pruned node_modules) but, by Next's design, does NOT copy the
  /// static assets or the `public/` directory into it — the application author
  /// is expected to. Without this the server boots but serves 404s for every
  /// `/_next/static/*` chunk and every public asset. We copy them so the
  /// standalone server is actually serveable.
  static Future<void> _postBuildNode(
      String user, String src, Map<String, String> env) async {
    final standalone = Directory('$src/.next/standalone');
    if (!standalone.existsSync()) return;

    stdout.writeln('[agent] Next.js standalone output — copying static assets');
    // `.next/static` → `.next/standalone/.next/static`
    // `public`       → `.next/standalone/public`
    // Best-effort: public/ is optional and a missing source must not fail the
    // deploy. cp -RT/-rL keeps it simple and idempotent across redeploys.
    await _runAsUserWithEnv(
      user,
      src,
      'mkdir -p .next/standalone/.next && '
      'rm -rf .next/standalone/.next/static .next/standalone/public && '
      'cp -r .next/static .next/standalone/.next/static; '
      'if [ -d public ]; then cp -r public .next/standalone/public; fi',
      env,
    );
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

  /// pnpm spec used when a project does not pin one and the Node version is new
  /// enough (≥22.13). `npm` resolves the bare major to the latest 10.x.
  static const String _defaultPnpmSpec = '10';

  /// pnpm spec for older pinned Node versions. The latest pnpm 10.x raised its
  /// floor to Node ≥22.13, so on an older pin (e.g. 22.12) it refuses to run —
  /// at build AND at `pnpm start`, crash-looping the service. pnpm 9 supports
  /// Node ^18.12 || ≥20 and reads the same lockfile format (9.0), so it is the
  /// safe fallback for older Node.
  static const String _legacyPnpmSpec = '9';

  /// Resolve which pnpm version to install for the project in [src].
  ///
  /// Honors a `"packageManager": "pnpm@X.Y.Z"` pin in package.json so each app
  /// gets exactly the version it expects (this is what corepack would have
  /// fetched). When unpinned, picks a pnpm major compatible with [nodeVersion]:
  /// the floating latest pnpm 10.x requires Node ≥22.13, so an older pinned Node
  /// falls back to pnpm 9 rather than installing a pnpm that can't run on it.
  /// A regex avoids a full JSON parse so a malformed package.json never breaks
  /// the deploy — we simply use the default.
  static String _resolvePnpmVersion(String src, String? nodeVersion) {
    final pkg = File('$src/package.json');
    if (pkg.existsSync()) {
      try {
        final m = RegExp(r'"packageManager"\s*:\s*"pnpm@([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.]+)?)')
            .firstMatch(pkg.readAsStringSync());
        if (m != null) return m.group(1)!;
      } catch (_) {/* fall through to the default */}
    }
    // Unpinned: guard against the latest pnpm 10.x outrunning an older Node pin.
    if (nodeVersion != null && !_nodeAtLeast(nodeVersion, 22, 13)) {
      return _legacyPnpmSpec;
    }
    return _defaultPnpmSpec;
  }

  /// Whether a dotted [version] (e.g. "22.12.0") is ≥ [major].[minor]. Unparid
  /// components default to 0, so a malformed pin is treated as "older".
  static bool _nodeAtLeast(String version, int major, int minor) {
    final parts = version.split('.');
    final maj = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final min = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    if (maj != major) return maj > major;
    return min >= minor;
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
    Map<String, String>? appEnv,
    bool noCache = false,
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
    // Inject the app's configured env vars so a build step bakes client-side
    // vars (e.g. NEXT_PUBLIC_*) into its output. The bun PATH override (when
    // present) is layered last so app vars never shadow it.
    final runEnv = <String, String>{
      ...(env ?? Platform.environment),
      ...?appEnv,
      if (env != null) 'PATH': env['PATH']!,
    };
    final cmd = buildCommand ?? 'bun install';

    // Only the default `bun install` is cache-gated; a custom build command can
    // do arbitrary work and is always re-run. The default install is skipped
    // when the bun lock file and pinned Bun version are unchanged and the
    // node_modules tree survived the source refresh.
    if (buildCommand == null) {
      const installKey = 'bun-install';
      final installFp = BuildCache.fingerprint([
        '$src/bun.lockb',
        '$src/bun.lock',
        '$src/package.json',
      ], [
        'bun:${bunVersion ?? 'system'}',
      ]);
      if (!noCache &&
          BuildCache.isFresh(workDir, installKey, installFp,
              artifact: '$src/node_modules')) {
        stdout.writeln(
            '[agent] dependencies unchanged — reusing cached node_modules');
        return;
      }
      BuildCache.invalidate(workDir, installKey);
      await _runAsUserWithEnv(user, src, cmd, runEnv);
      await BuildCache.store(workDir, user, installKey, installFp);
      return;
    }

    await _runAsUserWithEnv(user, src, cmd, runEnv);
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
    Map<String, String>? appEnv,
    bool noCache = false,
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

    // 3. Create (or reuse) the virtualenv. Reused as-is when the pinned Python
    //    version is unchanged and .venv survived the source refresh; rebuilt
    //    from scratch on a version change or force-rebuild. See _ensureVenv for
    //    why --copies is required.
    final venvRebuilt = await _ensureVenv(
      user: user,
      src: src,
      workDir: workDir,
      pythonBin: pythonBin,
      version: version,
      noCache: noCache,
    );

    // Persistent pip cache so unchanged wheels are not re-downloaded.
    final pipEnv = _pythonBuildEnv(workDir, appEnv);

    if (buildCommand != null) {
      // 4a. Custom build command — run it with the venv activated so that
      //     plain `pip install` / `python` references resolve into the venv.
      //     Arbitrary commands can't be fingerprinted, so this always runs, but
      //     it still benefits from the warm pip cache and reused venv.
      await _runAsUserWithEnv(
          user, src, 'source .venv/bin/activate && $buildCommand', pipEnv);
    } else {
      // 4b. Install app dependencies — skipped when requirements.txt and the
      //     Python version are unchanged and the venv was reused.
      final hasDeps = File('$src/requirements.txt').existsSync();
      if (hasDeps) {
        const depsKey = 'py-deps';
        final depsFp = BuildCache.fingerprint(
            ['$src/requirements.txt'], ['py:${version ?? 'system'}']);
        if (!noCache &&
            !venvRebuilt &&
            BuildCache.isFresh(workDir, depsKey, depsFp,
                artifact: '$venv/bin/python')) {
          stdout.writeln(
              '[agent] requirements unchanged — skipping pip install');
        } else {
          BuildCache.invalidate(workDir, depsKey);
          await _runAsUserWithEnv(user, src,
              '.venv/bin/pip install -q -r requirements.txt', pipEnv);
          await BuildCache.store(workDir, user, depsKey, depsFp);
        }
      }
    }

    // 5. Install server dependencies (needed for the gunicorn start command
    //    generated by apply-unit). The gunicorn binary's presence is the
    //    freshness signal, so a reused venv skips this network round-trip.
    await _ensurePipServerDeps(
      user: user,
      src: src,
      workDir: workDir,
      env: pipEnv,
      key: 'py-server',
      probeBin: '$venv/bin/gunicorn',
      packages: '"gunicorn>=21.0" "uvicorn[standard]>=0.29"',
      noCache: noCache || venvRebuilt,
    );

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
    await _runDjangoManagementCommands(user, src, workDir, appEnv);

    // 6. Symlink the venv into <workDir>/current so the systemd ExecStart
    //    path is stable across deployments.
    await ShellExec.run('mkdir', ['-p', '$workDir/current']);
    final link = Link(currentVenv);
    if (link.existsSync()) link.deleteSync();
    await ShellExec.run('ln', ['-sfn', venv, currentVenv]);
    await ShellExec.run('chown', ['-hR', '$user:$user', venv]);
  }

  /// Persistent build environment for pip-based runtimes.
  ///
  /// `runuser` runs the install as the app user with HOME=/home/<user>, a
  /// directory that never exists for panel apps, so pip can neither cache nor
  /// write logs there. We point HOME — and pip's cache explicitly — at the
  /// app-owned workdir, so wheels survive across deploys and unchanged
  /// dependencies are not re-downloaded. App env vars are layered first so the
  /// infra keys (HOME, PIP_CACHE_DIR) always win.
  static Map<String, String> _pythonBuildEnv(
          String workDir, Map<String, String>? appEnv) =>
      <String, String>{
        ...Platform.environment,
        ...?appEnv,
        'HOME': workDir,
        'PIP_CACHE_DIR': '$workDir/.cache/pip',
        'PIP_DISABLE_PIP_VERSION_CHECK': '1',
      };

  /// Create the project virtualenv at `<src>/.venv`, reusing an existing one
  /// when the pinned Python [version] is unchanged and the venv survived the
  /// source refresh. Returns true when a fresh venv was built (so the caller can
  /// force its dependent installs to re-run). [noCache] forces a rebuild.
  ///
  /// --copies is required: without it the venv's bin/python is a symlink to the
  /// pyenv binary. On Linux, Python uses /proc/self/exe to find its real path,
  /// which resolves that symlink to /opt/pyenv/…/bin/python3.x. Python then
  /// looks for pyvenv.cfg relative to the resolved path — which has none — so it
  /// treats the pyenv prefix as sys.prefix and leaves the venv's site-packages
  /// off sys.path entirely, making app dependencies missing at runtime.
  static Future<bool> _ensureVenv({
    required String user,
    required String src,
    required String workDir,
    required String pythonBin,
    required String? version,
    required bool noCache,
  }) async {
    const venvKey = 'py-venv';
    final venv = '$src/.venv';
    final venvFp =
        BuildCache.fingerprint(const <String>[], ['py:${version ?? 'system'}']);
    final reusable = !noCache &&
        File('$venv/bin/python').existsSync() &&
        BuildCache.isFresh(workDir, venvKey, venvFp,
            artifact: '$venv/bin/python');
    if (reusable) {
      stdout.writeln('[agent] reusing cached virtualenv (.venv)');
      return false;
    }
    // Rebuild from scratch: the venv is tied to a specific interpreter, so a
    // version change (or force-rebuild) must not reuse the old one.
    await ShellExec.run('rm', ['-rf', venv], requireSuccess: false);
    await _runAsUser(user, src, '$pythonBin -m venv --copies .venv');
    await BuildCache.store(workDir, user, venvKey, venvFp);
    // A fresh venv has no packages, so any dependent install markers are stale.
    BuildCache.invalidate(workDir, 'py-deps');
    BuildCache.invalidate(workDir, 'py-server');
    BuildCache.invalidate(workDir, 'py-celery');
    return true;
  }

  /// Install the server packages a runtime always needs (gunicorn/uvicorn, or
  /// celery/flower) into the venv, skipping the install when [probeBin] already
  /// exists and the marker [key] is recorded. [noCache] forces a reinstall.
  static Future<void> _ensurePipServerDeps({
    required String user,
    required String src,
    required String workDir,
    required Map<String, String> env,
    required String key,
    required String probeBin,
    required String packages,
    required bool noCache,
  }) async {
    if (!noCache &&
        BuildCache.isFresh(workDir, key, key, artifact: probeBin)) {
      return;
    }
    BuildCache.invalidate(workDir, key);
    await _runAsUserWithEnv(
        user, src, '.venv/bin/pip install -q $packages', env);
    await BuildCache.store(workDir, user, key, key);
  }

  /// Per-app directory Django static assets are collected into.
  ///
  /// Lives under `shared/` (app-owned, in the unit's ReadWritePaths, and stable
  /// across releases) so nginx can serve it directly and a redeploy does not
  /// wipe it. Mirrors the media directory next to it.
  static String djangoStaticRoot(String workDir) => '$workDir/shared/static';
  static String djangoMediaRoot(String workDir) => '$workDir/shared/media';

  /// Detect a Django project and run its standard deploy-time management
  /// commands. No-op for non-Django Python apps.
  static Future<void> _runDjangoManagementCommands(
      String user, String src, String workDir,
      [Map<String, String>? appEnv]) async {
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
      env: appEnv,
      requireSuccess: false,
    );

    await _runDjangoCollectStatic(user, src, workDir, appEnv);
  }

  /// Collect Django static files into a writable, per-app directory that nginx
  /// can serve, regardless of where the project's settings hardcode
  /// `STATIC_ROOT`.
  ///
  /// Many Django projects pin `STATIC_ROOT` to a system path like
  /// `/var/www/static`. `collectstatic` runs as the unprivileged app user, so
  /// writing there fails with `PermissionError: [Errno 13]` and no static is
  /// ever collected. It is also wrong for a multi-tenant host: every app would
  /// collide on the same shared directory.
  ///
  /// We override `STATIC_ROOT` to `<workDir>/shared/static` without touching the
  /// project's code: a tiny settings shim re-exports the project's own settings
  /// (`from <project.settings> import *`) and overrides only `STATIC_ROOT`.
  /// `collectstatic --settings=<shim>` then writes into the app-owned directory.
  /// The matching nginx `location /static/` is added by the vhost step.
  static Future<void> _runDjangoCollectStatic(
      String user, String src, String workDir,
      [Map<String, String>? appEnv]) async {
    final staticRoot = djangoStaticRoot(workDir);
    final mediaRoot = djangoMediaRoot(workDir);

    // Create the collect targets up front and hand them to the app user so the
    // unprivileged `collectstatic` can write and nginx (granted an ACL later)
    // can read.
    for (final dir in [staticRoot, mediaRoot]) {
      await ShellExec.run('mkdir', ['-p', dir]);
      await ShellExec.run('chown', ['-R', '$user:$user', dir]);
    }

    // Resolve the project's settings module so the shim can re-export it.
    final settingsModule = _djangoSettingsModule(src);
    String settingsArg = '';
    if (settingsModule != null) {
      const shimModule = '_gisila_static_settings';
      final shim = File('$src/$shimModule.py');
      shim.writeAsStringSync(
        '# Generated by gisila-agent — overrides STATIC_ROOT for collectstatic.\n'
        'from $settingsModule import *  # noqa: F401,F403\n'
        'STATIC_ROOT = r"$staticRoot"\n',
      );
      await ShellExec.run('chown', ['$user:$user', shim.path]);
      settingsArg = ' --settings=$shimModule';
      stdout.writeln(
          '[agent] Django collectstatic → $staticRoot (settings shim over '
          '$settingsModule)');
    } else {
      stdout.writeln(
          '[agent] Django collectstatic: could not resolve DJANGO_SETTINGS_MODULE '
          '— collecting with the project default (STATIC_ROOT may be unwritable)');
    }

    // collectstatic exits non-zero when STATIC_ROOT is unset; that is a valid
    // configuration (e.g. DEBUG=True dev serving), so failures are ignored.
    await ShellExec.run(
      'runuser',
      ['-u', user, '--', 'bash', '-lc',
        'source .venv/bin/activate && '
            'python manage.py collectstatic --noinput$settingsArg'],
      cwd: src,
      env: appEnv,
      requireSuccess: false,
    );
  }

  /// Best-effort discovery of the project's `DJANGO_SETTINGS_MODULE`.
  ///
  /// Reads the `os.environ.setdefault('DJANGO_SETTINGS_MODULE', '<module>')`
  /// line that Django's `manage.py` (and `wsgi.py` / `asgi.py`) ship with.
  /// Returns null when no such pin can be found, in which case the caller falls
  /// back to the project's own settings.
  static String? _djangoSettingsModule(String src) {
    final pattern = RegExp(
        r'''DJANGO_SETTINGS_MODULE['"]\s*,\s*['"]([\w.]+)['"]''');
    for (final candidate in [
      '$src/manage.py',
      ...Directory(src)
          .listSync()
          .whereType<Directory>()
          .expand((d) => ['${d.path}/wsgi.py', '${d.path}/asgi.py']),
    ]) {
      final f = File(candidate);
      if (!f.existsSync()) continue;
      final m = pattern.firstMatch(f.readAsStringSync());
      if (m != null) return m.group(1);
    }
    return null;
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
    Map<String, String>? appEnv,
    bool noCache = false,
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

    final venvRebuilt = await _ensureVenv(
      user: user,
      src: src,
      workDir: workDir,
      pythonBin: pythonBin,
      version: version,
      noCache: noCache,
    );

    final pipEnv = _pythonBuildEnv(workDir, appEnv);

    if (buildCommand != null) {
      await _runAsUserWithEnv(
          user, src, 'source .venv/bin/activate && $buildCommand', pipEnv);
    } else {
      final hasDeps = File('$src/requirements.txt').existsSync();
      if (hasDeps) {
        const depsKey = 'py-deps';
        final depsFp = BuildCache.fingerprint(
            ['$src/requirements.txt'], ['py:${version ?? 'system'}']);
        if (!noCache &&
            !venvRebuilt &&
            BuildCache.isFresh(workDir, depsKey, depsFp,
                artifact: '$venv/bin/python')) {
          stdout.writeln(
              '[agent] requirements unchanged — skipping pip install');
        } else {
          BuildCache.invalidate(workDir, depsKey);
          await _runAsUserWithEnv(user, src,
              '.venv/bin/pip install -q -r requirements.txt', pipEnv);
          await BuildCache.store(workDir, user, depsKey, depsFp);
        }
      }
    }

    // Always ensure celery and flower so the generated unit commands work;
    // skipped when a reused venv already has them.
    await _ensurePipServerDeps(
      user: user,
      src: src,
      workDir: workDir,
      env: pipEnv,
      key: 'py-celery',
      probeBin: '$venv/bin/celery',
      packages: '"celery>=5.3" "flower>=2.0"',
      noCache: noCache || venvRebuilt,
    );

    // Run Django management commands if applicable.
    await _runDjangoManagementCommands(user, src, workDir, appEnv);

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
    Map<String, String>? appEnv,
    bool noCache = false,
  }) async {
    if (buildCommand != null && buildCommand.trim().isNotEmpty) {
      // Install deps first (npm ci / bun install), then run the build. appEnv is
      // forwarded so the build bakes the app's configured env vars (e.g.
      // VITE_*/REACT_APP_* backend URLs) into the static bundle.
      await buildNode(
        workDir: workDir,
        user: user,
        buildCommand: buildCommand,
        appEnv: appEnv,
        noCache: noCache,
      );
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
