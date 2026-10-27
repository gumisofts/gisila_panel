// Mirrors the agent's AgentValidators.optionalVersion, so a bad pin is
// refused when it is saved rather than at deploy time. Pins become directory
// names under /opt and parts of download URLs.
final _versionRe = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+\-]{0,63}$');

/// Form validator for a runtime version such as `22.12.0`, `3.12`,
/// `stable` or `nightly-2024-01-01`; empty means "not pinned".
String? validRuntimeVersion(String v) {
  if (v.isEmpty) return null;
  if (!_versionRe.hasMatch(v) || v.contains('..')) {
    return 'Use a version such as 22.12.0, 3.12 or stable.';
  }
  return null;
}
