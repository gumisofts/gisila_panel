import 'dart:io';

import 'package:gisila_agent/runtime/exec.dart';

/// Persistent, per-app build cache that lets dependency installs be skipped when
/// their inputs (lock files, version pins) are unchanged across deploys.
///
/// All state lives under `<workDir>/.build-cache/`, which sits OUTSIDE
/// `releases/current_build` and therefore survives the source refresh between
/// deployments. Each cache entry is a single file holding the fingerprint that
/// produced the currently-installed artifact (node_modules / .venv); a build
/// step compares the live fingerprint against the recorded one and only re-runs
/// the install when they differ — or when the artifact itself went missing.
///
/// The fingerprint is a content hash, so an install re-runs precisely when a
/// lock file or a pinned runtime version changes — never on an unrelated source
/// commit. Correctness over the cache is preserved by two rules:
///   1. the marker is written only AFTER a successful install, and
///   2. [invalidate] is called BEFORE the install starts,
/// so a crashed or interrupted install never leaves a marker that would let the
/// next deploy wrongly skip the step.
class BuildCache {
  /// Root directory for all cache markers belonging to the app at [workDir].
  static String dir(String workDir) => '$workDir/.build-cache';

  /// Compute a stable fingerprint from the contents of [files] (those that
  /// exist) plus the [extra] tokens (version pins, package-manager name, …).
  /// Missing files are skipped so a step whose inputs all vanish still yields a
  /// deterministic key. The hash is content-based: identical inputs across two
  /// deploys produce an identical fingerprint.
  static String fingerprint(Iterable<String> files,
      [Iterable<String> extra = const <String>[]]) {
    final buf = StringBuffer();
    for (final token in extra) {
      buf
        ..write('e:')
        ..write(token)
        ..write('\n');
    }
    for (final path in files) {
      final f = File(path);
      if (!f.existsSync()) continue;
      final bytes = f.readAsBytesSync();
      buf
        ..write('f:')
        ..write(path.split('/').last)
        ..write(':')
        ..write(bytes.length)
        ..write(':')
        ..write(_fnv1a64(bytes))
        ..write('\n');
    }
    return buf.toString();
  }

  /// Whether the cache entry [name] already records [fingerprint] AND (when
  /// [artifact] is given) that artifact directory/file is still present. Both
  /// must hold for an install to be safely skipped: a matching fingerprint with
  /// a vanished node_modules/.venv must still trigger a reinstall.
  static bool isFresh(String workDir, String name, String fingerprint,
      {String? artifact}) {
    if (artifact != null &&
        !(Directory(artifact).existsSync() || File(artifact).existsSync())) {
      return false;
    }
    final f = File('${dir(workDir)}/$name');
    if (!f.existsSync()) return false;
    return f.readAsStringSync() == fingerprint;
  }

  /// Record [fingerprint] for cache entry [name] after a successful install.
  /// The cache directory is (re)created and handed to [user] so a later deploy
  /// running as that user can overwrite the marker.
  static Future<void> store(
      String workDir, String user, String name, String fingerprint) async {
    final d = dir(workDir);
    await ShellExec.run('mkdir', ['-p', d], requireSuccess: false);
    File('$d/$name').writeAsStringSync(fingerprint);
    await ShellExec.run('chown', ['-R', '$user:$user', d],
        requireSuccess: false);
  }

  /// Drop the marker for cache entry [name] so the next freshness check cannot
  /// pass. Call this before (re)running an install and whenever the artifact it
  /// guards is rebuilt from scratch.
  static void invalidate(String workDir, String name) {
    final f = File('${dir(workDir)}/$name');
    if (f.existsSync()) f.deleteSync();
  }

  /// Remove the entire cache for [workDir] — used to honour a force-rebuild
  /// request so the deploy reinstalls every dependency from a clean slate.
  static Future<void> clear(String workDir) async {
    await ShellExec.run('rm', ['-rf', dir(workDir)], requireSuccess: false);
  }

  /// 64-bit FNV-1a hash. Native Dart ints are 64-bit and wrap on overflow
  /// (AOT / JIT), which is exactly the modular arithmetic FNV expects. This is
  /// a cache key, not a security primitive — collision resistance over a single
  /// app's lock files is more than sufficient.
  static int _fnv1a64(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final b in bytes) {
      hash ^= b;
      hash = hash * prime;
    }
    return hash;
  }
}
