/// Strict input validation for everything the agent shells out with.
///
/// All routines throw [ArgumentError] on rejection. The agent CLI maps
/// those into a non-zero exit code so the worker can fail the deployment
/// cleanly.
class AgentValidators {
  static final _userRe = RegExp(r'^app_[a-z0-9]{6,}$');
  static final _workDirRe =
      RegExp(r'^/srv/apps/app_[a-z0-9]{6,}(/[a-zA-Z0-9_.\-]+)*/?$');
  static final _runtimeRe =
      RegExp(r'^(dart|go|rust|zig|bun|node|python|binary)$');
  static final _sourceTypeRe = RegExp(r'^(binary|git|zip)$');
  static final _hostnameRe =
      RegExp(r'^([a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$');
  static final _commandRe = RegExp(r'^[^|&;`$<>]+$');

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

  static String requireRuntime(String? raw) {
    if (raw == null || !_runtimeRe.hasMatch(raw)) {
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
}
