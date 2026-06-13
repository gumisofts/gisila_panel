import 'dart:convert';
import 'dart:io';

/// Which JavaScript framework a built source tree belongs to. Drives how the
/// service is started (or whether it is a static bundle that nginx serves).
enum NodeFrameworkKind {
  nextStandalone,
  next,
  nuxt,
  sveltekitNode,
  astroNode,
  remix,
  generic, // plain Node/Express/etc — a `start` script or detectable entrypoint
  staticSpa, // Vite / CRA / static framework output — no server process
  unknown, // could not determine how to start it
}

/// A concrete plan for starting (or classifying) a Node/Bun application,
/// resolved from its package.json + on-disk build output.
class NodeStartPlan {
  const NodeStartPlan({
    required this.kind,
    required this.label,
    this.startCommand,
    this.workingDir,
    this.extraEnv = const {},
    this.staticDir,
  });

  /// Detected framework family.
  final NodeFrameworkKind kind;

  /// Human-readable description for the build log (e.g. "Next.js (standalone)").
  final String label;

  /// Fully-resolved ExecStart command (concrete port already substituted), or
  /// null when this is a static bundle / undetectable.
  final String? startCommand;

  /// Absolute working directory the service should run from. For most
  /// frameworks this is the build source root; Next standalone overrides it to
  /// the `.next/standalone` subdirectory.
  final String? workingDir;

  /// Framework-default environment the unit should set unless the user already
  /// provides the key (e.g. HOST/HOSTNAME so the server binds 0.0.0.0).
  final Map<String, String> extraEnv;

  /// For [NodeFrameworkKind.staticSpa]: the build output directory (relative to
  /// the source root) that nginx should serve.
  final String? staticDir;

  bool get isStaticSpa => kind == NodeFrameworkKind.staticSpa;
  bool get isServer => startCommand != null && !isStaticSpa;
}

/// Detect the framework of a built Node/Bun project and produce a [NodeStartPlan].
///
/// Detection runs *after* the build, so it can trust on-disk output (e.g.
/// `.next/standalone`, `.output/server`) rather than guessing from config alone.
///
/// [src] is the build source root (`<workDir>/releases/current_build`).
/// [port] is the concrete listen port (substituted into start commands because
/// systemd only expands `$PORT` as a whole token).
/// [runtime] is the app runtime — `node` or `bun`; Bun apps start via `bun`.
class NodeFramework {
  static NodeStartPlan plan({
    required String src,
    required int port,
    required String runtime,
  }) {
    final pkg = _readPackageJson(src);
    final deps = _allDeps(pkg);
    final scripts = (pkg['scripts'] as Map?)?.cast<String, dynamic>() ?? const {};
    final isBun = runtime == 'bun';

    bool dep(String name) => deps.containsKey(name);
    bool depPrefix(String prefix) => deps.keys.any((k) => k.startsWith(prefix));
    bool config(String base) => [
          '$base.js',
          '$base.mjs',
          '$base.cjs',
          '$base.ts',
        ].any((f) => File('$src/$f').existsSync());

    // ── Next.js ──────────────────────────────────────────────────────────────
    // Bun can't host Next's node server; named frameworks always start via node.
    if (dep('next') || config('next.config')) {
      // Standalone output is the most reliable signal — the build literally
      // emitted a self-contained server. (A config probe is a weak pre-build
      // hint only; post-build the file either exists or it doesn't.)
      final standaloneServer = File('$src/.next/standalone/server.js');
      if (standaloneServer.existsSync() ||
          _configMentions(src, 'next.config', 'standalone')) {
        return NodeStartPlan(
          kind: NodeFrameworkKind.nextStandalone,
          label: 'Next.js (standalone)',
          startCommand: 'node server.js',
          workingDir: '$src/.next/standalone',
          // Next's standalone server reads PORT (set by the unit) and HOSTNAME.
          extraEnv: const {'HOSTNAME': '0.0.0.0'},
        );
      }
      return NodeStartPlan(
        kind: NodeFrameworkKind.next,
        label: 'Next.js',
        // Invoke the locally-installed binary so we never depend on npm/pnpm
        // resolving the `start` script (and so `-p` is explicit). Run it via
        // `node <abs-path>` because systemd's ExecStart needs a bare-name or
        // absolute first token, and Node ignores the script's `#!/usr/bin/env`
        // shebang (which AppArmor wouldn't permit).
        startCommand: 'node $src/node_modules/.bin/next start -p $port',
        workingDir: src,
      );
    }

    // ── Nuxt 3 (Nitro) ───────────────────────────────────────────────────────
    if (dep('nuxt') || dep('nuxt3') || config('nuxt.config')) {
      if (File('$src/.output/server/index.mjs').existsSync()) {
        return NodeStartPlan(
          kind: NodeFrameworkKind.nuxt,
          label: 'Nuxt (Nitro node server)',
          startCommand: 'node .output/server/index.mjs',
          workingDir: src,
          // Nitro honours PORT/HOST; bind all interfaces for the reverse proxy.
          extraEnv: const {'HOST': '0.0.0.0', 'NITRO_HOST': '0.0.0.0'},
        );
      }
      // `nuxt generate` produces a fully static site.
      if (Directory('$src/.output/public').existsSync()) {
        return NodeStartPlan(
          kind: NodeFrameworkKind.staticSpa,
          label: 'Nuxt (static)',
          staticDir: '.output/public',
        );
      }
    }

    // ── SvelteKit ────────────────────────────────────────────────────────────
    if (dep('@sveltejs/kit')) {
      if (File('$src/build/index.js').existsSync()) {
        return NodeStartPlan(
          kind: NodeFrameworkKind.sveltekitNode,
          label: 'SvelteKit (adapter-node)',
          startCommand: 'node build/index.js',
          workingDir: src,
          // adapter-node reads PORT/HOST.
          extraEnv: const {'HOST': '0.0.0.0'},
        );
      }
      if (File('$src/build/index.html').existsSync()) {
        return const NodeStartPlan(
          kind: NodeFrameworkKind.staticSpa,
          label: 'SvelteKit (adapter-static)',
          staticDir: 'build',
        );
      }
    }

    // ── Astro ────────────────────────────────────────────────────────────────
    if (dep('astro') || config('astro.config')) {
      if (File('$src/dist/server/entry.mjs').existsSync()) {
        return NodeStartPlan(
          kind: NodeFrameworkKind.astroNode,
          label: 'Astro (node adapter)',
          startCommand: 'node ./dist/server/entry.mjs',
          workingDir: src,
          extraEnv: const {'HOST': '0.0.0.0'},
        );
      }
      // Default Astro output is static.
      return const NodeStartPlan(
        kind: NodeFrameworkKind.staticSpa,
        label: 'Astro (static)',
        staticDir: 'dist',
      );
    }

    // ── Remix ────────────────────────────────────────────────────────────────
    if (dep('@remix-run/serve') ||
        dep('@remix-run/node') ||
        depPrefix('@remix-run/')) {
      // v2 (vite) emits build/server/index.js; classic compiler emits build/index.js.
      final v2 = File('$src/build/server/index.js').existsSync();
      final classic = File('$src/build/index.js').existsSync();
      if (v2 || classic) {
        final target = v2 ? './build/server/index.js' : './build/index.js';
        return NodeStartPlan(
          kind: NodeFrameworkKind.remix,
          label: 'Remix (remix-serve)',
          // `node <abs bin> <build>` — bare-name first token for systemd, Node
          // strips the bin's shebang. The build target stays relative to cwd.
          startCommand: 'node $src/node_modules/.bin/remix-serve $target',
          workingDir: src,
        );
      }
    }

    // ── Static-only bundlers (no server) ─────────────────────────────────────
    // Only treat as static when there is no custom server entrypoint to run.
    if (!_hasServerEntrypoint(pkg, src)) {
      if (dep('vite')) {
        return const NodeStartPlan(
          kind: NodeFrameworkKind.staticSpa,
          label: 'Vite (static SPA)',
          staticDir: 'dist',
        );
      }
      if (dep('react-scripts')) {
        return const NodeStartPlan(
          kind: NodeFrameworkKind.staticSpa,
          label: 'Create React App (static)',
          staticDir: 'build',
        );
      }
      if (dep('@parcel/core') || dep('parcel')) {
        return const NodeStartPlan(
          kind: NodeFrameworkKind.staticSpa,
          label: 'Parcel (static)',
          staticDir: 'dist',
        );
      }
    }

    // ── Generic Node / Bun server ────────────────────────────────────────────
    // Prefer the project's own `start` script when present.
    if (scripts['start'] is String && (scripts['start'] as String).trim().isNotEmpty) {
      return NodeStartPlan(
        kind: NodeFrameworkKind.generic,
        label: isBun ? 'Bun (start script)' : 'Node (start script)',
        startCommand: isBun ? 'bun run start' : 'npm start',
        workingDir: src,
      );
    }
    // Otherwise look for a conventional entrypoint.
    final entry = _findEntrypoint(pkg, src);
    if (entry != null) {
      return NodeStartPlan(
        kind: NodeFrameworkKind.generic,
        label: isBun ? 'Bun ($entry)' : 'Node ($entry)',
        startCommand: isBun ? 'bun run $entry' : 'node $entry',
        workingDir: src,
      );
    }

    return const NodeStartPlan(
      kind: NodeFrameworkKind.unknown,
      label: 'unknown',
    );
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _readPackageJson(String src) {
    final f = File('$src/package.json');
    if (!f.existsSync()) return const {};
    try {
      final decoded = jsonDecode(f.readAsStringSync());
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  static Map<String, dynamic> _allDeps(Map<String, dynamic> pkg) {
    final out = <String, dynamic>{};
    for (final key in const ['dependencies', 'devDependencies', 'optionalDependencies']) {
      final m = pkg[key];
      if (m is Map) out.addAll(m.cast<String, dynamic>());
    }
    return out;
  }

  /// Whether the project declares a custom server entrypoint (so it should be
  /// run rather than treated as a static bundle even if Vite is a dependency).
  static bool _hasServerEntrypoint(Map<String, dynamic> pkg, String src) {
    final scripts = (pkg['scripts'] as Map?)?.cast<String, dynamic>() ?? const {};
    final start = scripts['start'];
    if (start is String && start.trim().isNotEmpty) {
      // A `vite preview` start script is still just static serving, not a server.
      if (!start.contains('vite preview') && !start.contains('serve -s')) {
        return true;
      }
    }
    return _findEntrypoint(pkg, src) != null;
  }

  /// Resolve a conventional Node entrypoint relative to [src], or null.
  static String? _findEntrypoint(Map<String, dynamic> pkg, String src) {
    final main = pkg['main'];
    if (main is String && main.trim().isNotEmpty && File('$src/$main').existsSync()) {
      return main.trim();
    }
    for (final cand in const [
      'server.js',
      'server.mjs',
      'app.js',
      'index.js',
      'index.mjs',
      'src/index.js',
      'src/server.js',
      'dist/index.js',
      'dist/server.js',
    ]) {
      if (File('$src/$cand').existsSync()) return cand;
    }
    return null;
  }

  /// Cheap substring probe of a framework config file (no JS evaluation). Used
  /// only as a secondary signal for Next standalone before the build output
  /// exists. Returns true if any config variant contains [needle].
  static bool _configMentions(String src, String base, String needle) {
    for (final f in ['$base.js', '$base.mjs', '$base.cjs', '$base.ts']) {
      final file = File('$src/$f');
      if (file.existsSync()) {
        try {
          if (file.readAsStringSync().contains(needle)) return true;
        } catch (_) {}
      }
    }
    return false;
  }
}
