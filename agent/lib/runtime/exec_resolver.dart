import 'dart:io';

/// Turns a start command — written the way you would type it in a shell — into
/// something a process manager can actually exec.
///
/// The two are not the same language. A start command is authored against an
/// interactive shell sitting inside the project: the virtualenv activated,
/// `node_modules/.bin` on PATH, cargo's `target/release` a relative hop away.
/// A unit has none of that. systemd (and supervisord) take an absolute path or
/// a bare name looked up on the *system* PATH — which holds none of the app's
/// own tooling — and refuse anything relative outright as a "bad unit file
/// setting". So `python manage.py runserver` reaches the system interpreter
/// that has never heard of the app's dependencies (and on Debian/Ubuntu does
/// not exist at all, only `python3`), `next start` is simply not found, and
/// `./target/release/api` fails to load the unit at all.
///
/// Each runtime therefore declares where its executables really live and what
/// runs its source files, and [resolve] rewrites the command's first token to
/// match. A token it cannot place is returned untouched for PATH to resolve,
/// so nothing that worked before starts failing.
class ExecResolver {
  const ExecResolver({
    this.binDirs = const [],
    this.interpreter,
    this.scriptSuffixes = const [],
    this.altBaseDir,
  });

  /// The runtime's own installation dirs for executables a start command can
  /// name — the virtualenv's `bin`, `node_modules/.bin`, cargo's
  /// `target/release`. Searched in order for a bare name, before PATH.
  final List<String> binDirs;

  /// Runs this runtime's source files, and any [binDirs] entry whose shebang
  /// the sandbox can't honour. Absolute for python, where pointing at the
  /// venv's interpreter is the entire point; a bare `node` / `bun` for the JIT
  /// runtimes, whose unit already pins the right version on PATH through
  /// `runtimeBinDir`. Null for compiled runtimes, which have no scripts.
  final String? interpreter;

  /// Extensions of the source files [interpreter] can run.
  final List<String> scriptSuffixes;

  /// Second base for a relative path that doesn't exist under the working
  /// directory. The panel's own placeholder text spells the compiled artifact
  /// `./current/app`, which reads relative to the app root rather than to the
  /// unit's working directory — accept both instead of making people work out
  /// which one a given runtime uses.
  final String? altBaseDir;

  /// The resolver for [runtime], given an app's layout: [workDir] is the app
  /// root (`/srv/apps/app_xxx`) and [src] the build source tree it runs from.
  factory ExecResolver.forRuntime(
    String runtime, {
    required String workDir,
    required String src,
  }) {
    switch (runtime) {
      // Celery apps share the python layout (same venv, same source tree).
      case 'python':
      case 'celery':
        final venv = '$workDir/current/.venv/bin';
        return ExecResolver(
          binDirs: [venv],
          interpreter: '$venv/python',
          scriptSuffixes: const ['.py'],
          altBaseDir: workDir,
        );
      case 'node':
        return ExecResolver(
          binDirs: ['$src/node_modules/.bin'],
          interpreter: 'node',
          scriptSuffixes: const ['.js', '.mjs', '.cjs'],
          altBaseDir: workDir,
        );
      case 'bun':
        return ExecResolver(
          binDirs: ['$src/node_modules/.bin'],
          interpreter: 'bun',
          // Bun runs TypeScript directly, so its entrypoint may well be a .ts.
          scriptSuffixes: const ['.js', '.mjs', '.cjs', '.ts', '.tsx'],
          altBaseDir: workDir,
        );
      case 'rust':
        // Cargo leaves binaries at target/release/<crate-name> and the deploy
        // installs nothing to current/app, which is exactly why a rust app has
        // to name its own start command.
        return ExecResolver(
          binDirs: ['$src/target/release', '$src/target/debug'],
          altBaseDir: workDir,
        );
      default:
        // go, dart, zig, uploaded binaries: one compiled artifact, installed
        // by the build at <workDir>/current/app.
        return ExecResolver(
          binDirs: ['$workDir/current'],
          altBaseDir: workDir,
        );
    }
  }

  /// Rewrite [startCommand] into an `ExecStart=` / supervisord `command=`
  /// value, resolving its program against [workingDirectory] and [binDirs].
  String resolve(
    String startCommand, {
    required String workingDirectory,
  }) {
    final trimmed = startCommand.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('startCommand must not be empty');
    }
    final parts = trimmed.split(RegExp(r'\s+'));
    final token = parts.first;
    final cwd = _stripSlash(workingDirectory);

    String? program;
    if (token.startsWith('/')) {
      program = token;
    } else if (token.startsWith('./') || token.contains('/')) {
      final rel = token.startsWith('./') ? token.substring(2) : token;
      program = '$cwd/$rel';
      if (!File(program).existsSync() && altBaseDir != null) {
        final alt = '${_stripSlash(altBaseDir!)}/$rel';
        if (File(alt).existsSync()) program = alt;
      }
    } else {
      // A bare name: the runtime's own bin dirs, then — for a source file
      // named without any path ("manage.py", "server.js") — the working
      // directory. Anything else is left for the process manager's PATH.
      for (final dir in binDirs) {
        if (File('$dir/$token').existsSync()) {
          program = '$dir/$token';
          break;
        }
      }
      if (program == null && _isScript(token)) program = '$cwd/$token';
      if (program == null) return trimmed;
    }

    parts[0] = program;
    final runner = _runnerFor(program);
    if (runner != null) parts.insert(0, runner);
    return parts.join(' ');
  }

  bool _isScript(String path) => scriptSuffixes.any(path.endsWith);

  /// The interpreter to put in front of [program], or null when it can be
  /// exec'd on its own.
  String? _runnerFor(String program) {
    final runner = interpreter;
    if (runner == null) return null;
    if (!_isScript(program) && !_usesEnvShebang(program)) return null;
    // A venv that was never built can't interpret anything; leave the command
    // as-is so the failure is the missing build, not a bogus ExecStart.
    if (runner.contains('/') && !File(runner).existsSync()) return null;
    return runner;
  }

  /// True when [path] opens with a `#!/usr/bin/env …` shebang.
  ///
  /// `env` looks the interpreter up on PATH, the one thing the unit cannot
  /// supply — and AppArmor won't follow the indirection either. Every
  /// `node_modules/.bin` shim is written this way, which is why they have to
  /// be handed to `node` explicitly. A venv console script like `gunicorn`
  /// instead carries an absolute `#!…/.venv/bin/python` that works as-is, and
  /// a compiled binary has no shebang at all; both are left alone.
  static bool _usesEnvShebang(String path) {
    try {
      final handle = File(path).openSync();
      try {
        final head = handle.readSync(128);
        if (head.length < 2 || head[0] != 0x23 || head[1] != 0x21) return false;
        return String.fromCharCodes(head).split('\n').first.contains('/env ');
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return false;
    }
  }

  static String _stripSlash(String dir) =>
      dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
}
