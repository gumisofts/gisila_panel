/// Generates supervisord configs for a Celery deployment (Docker / dev mode).
///
/// Produces one `[program:...]` block per worker, plus optional beat and
/// flower blocks. All blocks share the same env vars.
class CeleryWorkerSupervisorConf {
  CeleryWorkerSupervisorConf({
    required this.appId,
    required this.linuxUser,
    required this.workDir,
    required this.celeryApp,
    required this.port,
    this.workerCount = 2,
    this.concurrency = 4,
    this.queues,
    this.extraArgs,
    this.beatEnabled = false,
    this.envVars = const {},
  });

  final int appId;
  final String linuxUser;
  final String workDir;
  final String celeryApp;
  final int port;
  final int workerCount;
  final int concurrency;
  final String? queues;
  final String? extraArgs;
  final bool beatEnabled;
  final Map<String, String> envVars;

  String _envPairs(Map<String, String> extra) {
    final buf =
        StringBuffer('PORT="$port",GISILA_APP_ID="$appId"');
    for (final entry in envVars.entries) {
      final escaped =
          entry.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      buf.write(',${entry.key}="$escaped"');
    }
    for (final entry in extra.entries) {
      buf.write(',${entry.key}="${entry.value}"');
    }
    return buf.toString();
  }

  String render() {
    final venv = '$workDir/current/.venv';
    final src = '$workDir/current/src';
    final logs = '$workDir/logs';
    final tmp = '$workDir/tmp';
    final queuesArg =
        (queues != null && queues!.isNotEmpty) ? ' -Q $queues' : '';
    final extraArgsStr =
        (extraArgs != null && extraArgs!.isNotEmpty) ? ' ${extraArgs!.trim()}' : '';

    // Flower is reverse-proxied at the app's domain and has no auth of its own,
    // so it must run with HTTP basic-auth from `FLOWER_BASIC_AUTH`
    // ("user:password"). Supervisor runs `command=` without a shell and does
    // not expand `${VAR}`, so the value is inlined here; `%` is doubled because
    // supervisor treats it as the start of an expansion specifier. The deploy
    // worker guarantees the var is set for Celery apps.
    final flowerAuth = envVars['FLOWER_BASIC_AUTH'];
    final basicAuthArg = (flowerAuth != null && flowerAuth.isNotEmpty)
        ? ' --basic-auth=${flowerAuth.replaceAll('%', '%%')}'
        : '';

    final buf = StringBuffer();

    // Worker processes
    for (var i = 1; i <= workerCount; i++) {
      buf.write('''
[program:gisila-$linuxUser-worker-$i]
command=$venv/bin/celery -A $celeryApp worker -n worker-$i@%h --loglevel=info -c $concurrency$queuesArg$extraArgsStr --logfile=$logs/worker-$i.log
directory=$src
user=$linuxUser
autostart=true
autorestart=true
startsecs=5
startretries=5
stopwaitsecs=30
stdout_logfile=$logs/worker-$i-stdout.log
stdout_logfile_maxbytes=20MB
stdout_logfile_backups=3
stderr_logfile=$logs/worker-$i-stderr.log
stderr_logfile_maxbytes=20MB
stderr_logfile_backups=3
environment=${_envPairs({})}

''');
    }

    // Flower UI
    buf.write('''
[program:gisila-$linuxUser-flower]
command=$venv/bin/celery -A $celeryApp flower --port=$port --address=127.0.0.1 --logging=info$basicAuthArg
directory=$src
user=$linuxUser
autostart=true
autorestart=true
startsecs=5
startretries=5
stopwaitsecs=10
stdout_logfile=$logs/flower-stdout.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=2
stderr_logfile=$logs/flower-stderr.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=2
environment=${_envPairs({})}

''');

    // Beat scheduler (optional)
    if (beatEnabled) {
      final schedule = '$workDir/shared/celerybeat-schedule';
      buf.write('''
[program:gisila-$linuxUser-beat]
command=$venv/bin/celery -A $celeryApp beat --loglevel=info --logfile=$logs/beat.log --pidfile=$tmp/celerybeat.pid --schedule=$schedule
directory=$src
user=$linuxUser
autostart=true
autorestart=true
startsecs=5
startretries=3
stopwaitsecs=10
stdout_logfile=$logs/beat-stdout.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=2
stderr_logfile=$logs/beat-stderr.log
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=2
environment=${_envPairs({})}

''');
    }

    // Group so supervisorctl can control them all at once
    final members = [
      for (var i = 1; i <= workerCount; i++) 'gisila-$linuxUser-worker-$i',
      'gisila-$linuxUser-flower',
      if (beatEnabled) 'gisila-$linuxUser-beat',
    ].join(',');

    buf.write('''
[group:gisila-$linuxUser]
programs=$members
''');

    return buf.toString();
  }
}

/// Generates a supervisord program config for a deployed app.
///
/// Used instead of systemd in Docker / container environments.
/// Each app gets its own [program:gisila-<linuxUser>] section.
class SupervisorConf {
  SupervisorConf({
    required this.appId,
    required this.linuxUser,
    required this.workDir,
    required this.startCommand,
    required this.port,
    this.runtimeBinDir,
    this.workingDir,
    this.envVars = const {},
  });

  final int appId;
  final String linuxUser;
  final String workDir;
  final String startCommand;
  final int port;

  /// Explicit working directory. When null, defaults to `<workDir>/current`.
  /// Node/Bun apps run from the published release (`<workDir>/current/src`).
  final String? workingDir;

  /// When set, prepended to PATH inside the supervisord process so `node` /
  /// `bun` in [startCommand] resolves to the pinned version binary.
  final String? runtimeBinDir;
  final Map<String, String> envVars;

  String get programName => 'gisila-$linuxUser';

  String render() {
    // supervisord environment= format: KEY="VALUE",KEY2="VALUE2"
    // Embedded double-quotes in values must be escaped as \".
    final pairs = StringBuffer('PORT="$port",GISILA_APP_ID="$appId"');
    if (runtimeBinDir != null) {
      pairs.write(',PATH="$runtimeBinDir:/usr/local/bin:/usr/bin:/bin"');
    }
    // Stop pnpm from reinstalling deps when the program starts: its pre-script
    // deps-status check can decide node_modules is stale and trigger an
    // automatic `pnpm install`, which aborts on the no-TTY modules-purge prompt
    // (ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY) and crash-loops the process.
    // Mirrors the systemd unit. pnpm 11 reads `pnpm_config_*`, pnpm 9/10 read
    // `npm_config_*`; both are set. The keys are pnpm-specific and ignored by
    // other runtimes, so this is safe to set unconditionally.
    pairs.write(',npm_config_verify_deps_before_run="false"'
        ',pnpm_config_verify_deps_before_run="false"'
        ',npm_config_confirm_modules_purge="false"'
        ',pnpm_config_confirm_modules_purge="false"');
    for (final entry in envVars.entries) {
      final escaped =
          entry.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      pairs.write(',${entry.key}="$escaped"');
    }
    return '''
[program:$programName]
command=$startCommand
directory=${workingDir ?? '$workDir/current'}
user=$linuxUser
autostart=true
autorestart=true
startsecs=3
startretries=5
stopwaitsecs=10
stdout_logfile=$workDir/logs/stdout.log
stdout_logfile_maxbytes=20MB
stdout_logfile_backups=3
stderr_logfile=$workDir/logs/stderr.log
stderr_logfile_maxbytes=20MB
stderr_logfile_backups=3
environment=$pairs
''';
  }
}
