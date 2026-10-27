import 'dart:io';

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
  // No control characters either: commands are rendered into a single
  // `ExecStart=` line, and a newline would let the value add unit directives of
  // its own (`ExecStartPre=+…` runs as root).
  static final _commandRe = RegExp(r'^[^|&;`$<>\x00-\x1f\x7f]+$');
  static final _controlCharRe = RegExp(r'[\x00-\x1f\x7f]');
  static final _envNameRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  static final _pathSegmentRe = RegExp(r'^[a-zA-Z0-9_.\-]+$');
  // Deployment ids, optionally suffixed `-<ms>` by a retried publish. No dots
  // or slashes: the value names a directory under releases/ that root deletes.
  static final _releaseIdRe = RegExp(r'^[0-9]+(-[0-9]+)?$');

  static String requireUser(String? raw) {
    if (raw == null || !_userRe.hasMatch(raw)) {
      throw ArgumentError('Invalid --user: $raw');
    }
    return raw;
  }

  /// Root runs builds in and deletes under this path, so `.`/`..` segments
  /// (which the character class alone lets through) are refused too.
  static String requireWorkDir(String? raw) {
    if (raw == null ||
        !_workDirRe.hasMatch(raw) ||
        raw.split('/').any((s) => s == '.' || s == '..')) {
      throw ArgumentError('Invalid --work-dir: $raw');
    }
    return raw;
  }

  static final _versionRe = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+\-]{0,63}$');

  /// A runtime version pin such as `22.12.0`, `3.12`, `stable` or
  /// `nightly-2024-01-01`; null when unset. Pins become directory names
  /// under /opt and parts of download URLs, so only a version's own
  /// characters are allowed, and never `..`.
  static String? optionalVersion(String option, String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final v = raw.trim();
    if (!_versionRe.hasMatch(v) || v.contains('..')) {
      throw ArgumentError('Invalid --$option: $raw');
    }
    return v;
  }

  /// Total RAM of this host in MB (from /proc/meminfo), or null where that
  /// can't be read.
  static int? hostMemoryMb() {
    try {
      final line = File('/proc/meminfo')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('MemTotal:'));
      final kb = int.parse(RegExp(r'(\d+)').firstMatch(line)![1]!);
      return kb ~/ 1024;
    } on Object {
      return null;
    }
  }

  /// A positive integer for --[option], clamped to [max]. Out-of-range
  /// values are clamped rather than refused so apps saved before the panel
  /// bounded these fields still deploy; the panel's forms refuse new ones.
  static int _positiveClamped(String option, String? raw, int max) {
    final v = int.tryParse(raw ?? '');
    if (v == null || v < 1) {
      throw ArgumentError('Invalid --$option: $raw');
    }
    return v > max ? max : v;
  }

  /// `MemoryMax=` in MB for an app unit, at most the host's RAM (a larger
  /// value would be no limit at all).
  static int requireMemoryMb(String? raw) =>
      _positiveClamped('memory-mb', raw, hostMemoryMb() ?? 1 << 30);

  /// `CPUQuota=` percent, at most every core of this host.
  static int requireCpuQuota(String? raw) =>
      _positiveClamped('cpu-quota', raw, Platform.numberOfProcessors * 100);

  /// `TasksMax=` for an app unit.
  static int requireTasksMax(String? raw) =>
      _positiveClamped('tasks-max', raw, 16384);

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

  static String requireReleaseId(String? raw) {
    if (raw == null || !_releaseIdRe.hasMatch(raw)) {
      throw ArgumentError('Invalid --release-id: $raw');
    }
    return raw;
  }

  static String? optionalReleaseId(String? raw) =>
      (raw == null || raw.isEmpty) ? null : requireReleaseId(raw);

  /// Comma-separated release ids to retain when pruning; null when the flag
  /// was not passed (prune by count instead).
  static Set<String>? optionalReleaseIds(String? raw) {
    if (raw == null) return null;
    return {
      for (final id in raw.split(','))
        if (id.trim().isNotEmpty) requireReleaseId(id.trim()),
    };
  }

  /// Where the panel stores uploaded build artifacts, as
  /// `<root>/apps/<appId>/<32 hex chars>.bin|.zip`. The panel API writes
  /// there; set GISILA_ARTIFACT_DIR for both if it lives elsewhere.
  static String get artifactRoot =>
      Platform.environment['GISILA_ARTIFACT_DIR'] ??
      '/var/lib/gisila/artifacts';

  static final _artifactRe = RegExp(r'^([0-9]+)/([0-9a-f]{32})\.(bin|zip)$');

  /// The uploaded artifact a binary or zip build installs. Root reads it and
  /// hands its contents to the app user, so it must be a regular file the
  /// panel stored for this app: any other path (`/etc/shadow`, another
  /// app's upload, a symlink to either) would be copied out for the tenant.
  static String requireArtifactPath(
    String? raw, {
    required String appId,
    required String sourceType,
    String? root,
  }) {
    final ext = sourceType == 'zip' ? 'zip' : 'bin';
    final base = '${root ?? artifactRoot}/apps/';
    final m = raw == null || !raw.startsWith(base)
        ? null
        : _artifactRe.firstMatch(raw.substring(base.length));
    if (m == null || m.group(1) != appId || m.group(3) != ext) {
      throw ArgumentError('Invalid --artifact-path: $raw');
    }
    // A regular file, with no symlink anywhere below the artifact root.
    final isFile = FileSystemEntity.typeSync(raw!, followLinks: false) ==
        FileSystemEntityType.file;
    if (!isFile ||
        File(raw).resolveSymbolicLinksSync() !=
            '${Directory(base).resolveSymbolicLinksSync()}/'
                '${raw.substring(base.length)}') {
      throw ArgumentError('--artifact-path is not an uploaded file: $raw');
    }
    return raw;
  }

  // Remote transports only. `file://`, bare local paths and `ext::` would let
  // a tenant clone another app's tree from /srv/apps.
  static final _gitUrlRe = RegExp(
      r'^(?:(?:https?|ssh|git)://[A-Za-z0-9\[][A-Za-z0-9._~%!$&()*+,;=:@\[\]-]*'
      r'(?:/\S*)?'
      r'|[A-Za-z0-9._-]+@[A-Za-z0-9][A-Za-z0-9.-]*:[^\s-]\S*)$');
  // A conservative subset of `git check-ref-format`.
  static final _gitRefRe = RegExp(r'^[A-Za-z0-9._@+-]+(/[A-Za-z0-9._@+-]+)*$');

  /// A git remote URL: http(s)/ssh/git scheme or scp-style `user@host:path`.
  static String requireGitUrl(String? raw) {
    if (raw == null ||
        raw.length > 2048 ||
        raw.startsWith('-') ||
        _controlCharRe.hasMatch(raw) ||
        !_gitUrlRe.hasMatch(raw)) {
      throw ArgumentError(
          'Invalid --git-url: use an https://, ssh:// or user@host:path URL');
    }
    return raw;
  }

  /// A branch or tag name; null for the remote's default branch.
  static String? optionalGitRef(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.length > 255 ||
        raw.startsWith('-') ||
        raw.contains('..') ||
        raw.contains('@{') ||
        raw.endsWith('.lock') ||
        !_gitRefRe.hasMatch(raw)) {
      throw ArgumentError('Invalid --git-branch: $raw');
    }
    return raw;
  }

  static String? optionalCommand(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (!_commandRe.hasMatch(raw)) {
      throw ArgumentError('Refusing potentially unsafe command: $raw');
    }
    return raw;
  }

  /// Reject a [value] holding any control character. Every option of a command
  /// that renders config files (systemd units, supervisor confs, the env file)
  /// goes through this: those formats are line-based, so a newline in any
  /// interpolated value — a celery queue list, gunicorn args, a bin dir — would
  /// add lines of its own.
  static void rejectControlChars(String option, String? value) {
    if (value != null && _controlCharRe.hasMatch(value)) {
      throw ArgumentError('Invalid --$option: contains a control character');
    }
  }

  /// Validate env var names. Values may be anything (they are quoted and
  /// escaped where rendered), but a name is written bare — `NAME="value"` —
  /// so it must be a plain shell identifier.
  static Map<String, String> requireEnvVars(Map<String, String> vars) {
    for (final name in vars.keys) {
      if (!_envNameRe.hasMatch(name)) {
        throw ArgumentError('Invalid env var name: $name');
      }
    }
    return vars;
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
