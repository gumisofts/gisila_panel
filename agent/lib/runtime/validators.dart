import 'package:gisila_agent/runtime/runtime_registry.dart';

/// Strict input validation for everything the agent shells out with.
///
/// All routines throw [ArgumentError] on rejection. The agent CLI maps
/// those into a non-zero exit code so the worker can fail the deployment
/// cleanly.
class AgentValidators {
  static final _userRe = RegExp(r'^app_[a-z0-9]{6,}$');
  static final _workDirRe =
      RegExp(r'^/srv/apps/app_[a-z0-9]{6,}(/[a-zA-Z0-9_.\-]+)*/?$');
  static final _sourceTypeRe = RegExp(r'^(binary|git|zip)$');
  static final _hostnameRe =
      RegExp(r'^([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$');
  static final _commandRe = RegExp(r'^[^|&;`$<>]+$');
  static final _pathSegmentRe = RegExp(r'^[a-zA-Z0-9_.\-]+$');

  static String requireUser(String? raw) {
    if (raw == null || !_userRe.hasMatch(raw)) {
      throw ArgumentError('Invalid --user: $raw');
    }
    return raw;
  }

  static String requireWorkDir(String? raw) {
    if (raw == null || !_workDirRe.hasMatch(raw)) {
      throw ArgumentError('Invalid --work-dir: $raw');
    }
    return raw;
  }

  static int requirePort(String? raw, {int min = 1024, int max = 65535}) {
    final p = int.tryParse(raw ?? '');
    if (p == null || p < min || p > max) {
      throw ArgumentError('Invalid --port: $raw');
    }
    return p;
  }

  /// Validated against the [RuntimeRegistry] — the set of installed
  /// Application plugins — rather than a compiled-in allowlist, so a newly
  /// registered runtime plugin is automatically valid with no changes here.
  static String requireRuntime(String? raw) {
    if (raw == null || !RuntimeRegistry.has(raw)) {
      throw ArgumentError('Invalid --runtime: $raw');
    }
    return raw;
  }

  static String requireSourceType(String? raw) {
    if (raw == null || !_sourceTypeRe.hasMatch(raw)) {
      throw ArgumentError('Invalid --source-type: $raw');
    }
    return raw;
  }

  static String requireHostname(String? raw) {
    if (raw == null || !_hostnameRe.hasMatch(raw.toLowerCase())) {
      throw ArgumentError('Invalid --hostname: $raw');
    }
    return raw.toLowerCase();
  }

  static String? optionalCommand(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (!_commandRe.hasMatch(raw)) {
      throw ArgumentError('Refusing potentially unsafe command: $raw');
    }
    return raw;
  }

  /// Validate a monorepo subdirectory (relative path under the repo root
  /// where the actual project to build/run lives). Rejects absolute paths,
  /// `.`/`..` traversal segments and any shell/glob metacharacters — this
  /// value is spliced directly into filesystem paths the agent runs as root.
  /// Returns null (meaning "repo root") for a null/blank/root ("." or "/")
  /// input, and the cleaned (no leading/trailing slashes) path otherwise.
  static String? optionalSourceSubdir(String? raw) {
    if (raw == null) return null;
    final cleaned =
        raw.trim().replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isEmpty || cleaned == '.') return null;
    final segments = cleaned.split('/');
    for (final s in segments) {
      if (s.isEmpty || s == '.' || s == '..' || !_pathSegmentRe.hasMatch(s)) {
        throw ArgumentError('Invalid --source-subdir: $raw');
      }
    }
    return segments.join('/');
  }
}
