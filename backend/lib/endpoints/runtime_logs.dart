import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/services/apps_service.dart';

part 'runtime_logs.g.dart';

/// The last lines of an app's runtime log, in one response. The live stream
/// is the `/ws/apps/{id}/logs` WebSocket; this is for clients that can't hold
/// a socket open, such as AI assistants connected through `/mcp`.
@Controller('/apps/{appId}/runtime-logs', ['Logs'])
@RequireAuth()
class RuntimeLogsApi {
  @Get('/', summary: 'Recent runtime log lines of an app')
  Future<Map<String, Object?>> tail(
    int appId,
    AppsService apps,
    RequestContext ctx, {
    int? lines,
  }) async {
    // Same rule as the log socket: any member of the app's team.
    final app = await apps.findForUser(currentUser(ctx), appId);
    final user = app.linuxUser;
    if (user == null) {
      return <String, Object?>{
        'lines': const <String>[],
        'detail': 'The app has not been deployed yet.',
      };
    }
    if (hostConfig.agentMode == 'dev') {
      return <String, Object?>{
        'lines': const <String>[],
        'detail': 'Runtime logs are not available in dev mode.',
      };
    }
    final n = (lines ?? 200).clamp(1, 2000);
    // The API runs without sudo; the agent reads journald through the
    // systemd-journal group, as the log socket does.
    final cmd = buildAgentCmdNoSudo([
      'logs',
      '--user',
      user,
      '--work-dir',
      app.workDir,
      '--runtime',
      app.runtime,
      '--lines',
      '$n',
    ]);
    final ProcessResult result;
    try {
      result = await Process.run(cmd.first, cmd.skip(1).toList(),
              environment: agentEnvironment,
              includeParentEnvironment: false,
              stdoutEncoding: utf8,
              stderrEncoding: utf8)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw HttpException(504, 'Reading the logs timed out.',
          code: 'logs_timeout');
    }
    final out = const LineSplitter().convert('${result.stdout}');
    return <String, Object?>{
      'lines': out,
      if (result.exitCode != 0)
        'error': '${result.stderr}'.trim().split('\n').first,
    };
  }
}
