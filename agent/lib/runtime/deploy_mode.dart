/// Deployment mechanisms an [RuntimePlugin] (and the [Application] it backs
/// on the panel side) can support. Mirrors `DeployMode` in
/// `backend/lib/services/application_catalog.dart` — keep both in sync.
enum DeployMode {
  /// The app is compiled/packaged first, then the built artifact is executed.
  buildExecute('build_execute'),

  /// The app is executed directly with no compile step — an interpreter runs
  /// the source in place, or a pre-built binary is dropped in as-is.
  directRun('direct_run'),

  /// No process is run; files are published for nginx to serve directly.
  staticPublish('static_publish');

  const DeployMode(this.value);
  final String value;

  static DeployMode? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final m in DeployMode.values) {
      if (m.value == raw) return m;
    }
    return null;
  }
}
