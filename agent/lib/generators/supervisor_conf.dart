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
  });

  final int appId;
  final String linuxUser;
  final String workDir;
  final String startCommand;
  final int port;

  String get programName => 'gisila-$linuxUser';

  String render() => '''
[program:$programName]
command=$startCommand
directory=$workDir/current
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
environment=PORT="$port",GISILA_APP_ID="$appId"
''';
}
