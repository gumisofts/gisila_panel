/// Renders an app's user-defined environment variables as a systemd
/// `EnvironmentFile=` document.
///
/// The same file (`<workDir>/.env`) is referenced by every per-app unit — the
/// web service and each Celery worker/beat/flower — via `EnvironmentFile=`, so
/// the runtime configuration lives in exactly one place instead of being
/// duplicated as `Environment=` lines across units. It also gives a developer
/// who SSHes in a file to load before running management commands by hand
/// (`set -a; source .env; set +a`), which is what makes `python manage.py
/// migrate` hit the real database instead of Django's sqlite fallback.
///
/// Format: one `KEY="value"` per line. Values are double-quoted and the two
/// characters systemd treats specially inside double quotes — backslash and
/// double-quote — are escaped, matching how the `Environment=` lines were
/// rendered before. This same syntax is accepted by bash's `source` under
/// `set -a`, so the one file serves both consumers.
String renderEnvFile(Map<String, String> envVars) {
  final buf = StringBuffer()
    ..writeln('# Managed by gisila-agent — do not edit by hand.')
    ..writeln('# App environment variables. Loaded by systemd via '
        'EnvironmentFile=,')
    ..writeln('# and sourceable in a shell with: set -a; source .env; set +a');
  for (final entry in envVars.entries) {
    final escaped = entry.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    buf.writeln('${entry.key}="$escaped"');
  }
  return buf.toString();
}
