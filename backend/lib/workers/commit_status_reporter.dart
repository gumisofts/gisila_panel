import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/secret_box.dart';

/// Self-driven [Timer] loop that reports the status of deployments queued
/// by a push back on the pushed commit (GitHub, Gitea / Forgejo, GitLab).
///
/// [WebhooksService] records where to post when it queues the deployment;
/// this loop posts each state change (pending, then success or failure)
/// once, using the app's status token. Failed posts are retried on later
/// ticks a few times, then given up on.
class CommitStatusReporter {
  CommitStatusReporter(
    this.database, {
    this.interval = const Duration(seconds: 10),
    HttpClient Function()? client,
  }) : _client = client ?? HttpClient.new;

  final Database database;
  final Duration interval;
  final HttpClient Function() _client;

  static const maxAttempts = 5;
  static const context = 'gisila-panel/deploy';

  Timer? _timer;
  var _ticking = false;

  void start() {
    logger.i('commit_status: started (every ${interval.inSeconds}s)');
    _timer = Timer.periodic(interval, (_) => _safeTick());
  }

  void stop() => _timer?.cancel();

  Future<void> _safeTick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await tick();
    } catch (e, st) {
      logger.w('commit_status: tick failed: $e', stackTrace: st);
    } finally {
      _ticking = false;
    }
  }

  /// The commit state for a deployment status.
  static String stateFor(String? status) => switch (status) {
        'succeeded' => 'success',
        'failed' => 'failure',
        _ => 'pending',
      };

  Future<void> tick() async {
    final rows = await database.context().execute(
      'SELECT s.deployment_id, s.app_id, s.host, s.url, s.reported_state, '
      's.attempts, d.status, w.status_token FROM deployment_commit_statuses s '
      'JOIN deployments d ON d.id = s.deployment_id '
      'JOIN app_webhooks w ON w.app_id = s.app_id '
      'WHERE w.status_token IS NOT NULL AND s.attempts < \$1 '
      "AND s.created_at > now() - interval '1 day'",
      parameters: [maxAttempts],
    );
    for (final r in rows) {
      final row = r.toColumnMap();
      final state = stateFor(row['status'] as String?);
      if (state == row['reported_state']) continue;
      if (await _post(row, state)) {
        await database.context().execute(
          'UPDATE deployment_commit_statuses SET reported_state = \$2, '
          'attempts = 0 WHERE deployment_id = \$1',
          parameters: [row['deployment_id'], state],
        );
      } else {
        await database.context().execute(
          'UPDATE deployment_commit_statuses SET attempts = attempts + 1 '
          'WHERE deployment_id = \$1',
          parameters: [row['deployment_id']],
        );
      }
    }
  }

  Future<bool> _post(Map<String, Object?> row, String state) async {
    final host = row['host'] as String;
    final url = Uri.parse(row['url'] as String);
    final token = SecretBox.instance
        .open(row['status_token'] as String, SecretBox.appWebhookStatusToken);
    final description = switch (state) {
      'success' => 'Deployed',
      'failure' => 'Deployment failed',
      _ => 'Deploying',
    };
    final panel = env['PANEL_PUBLIC_URL']?.trim() ?? '';
    final target = panel.isEmpty ? null : '$panel/apps/${row['app_id']}';

    final client = _client()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req =
          await client.postUrl(url).timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.set('user-agent', 'gisila-panel');
      req.headers.contentType = ContentType.json;
      final Map<String, Object?> body;
      if (host == 'gitlab') {
        req.headers.set('private-token', token);
        body = {
          // GitLab says "failed" and has "running" for in-progress work.
          'state': switch (state) {
            'failure' => 'failed',
            'pending' => 'running',
            _ => state,
          },
          'name': context,
          'description': description,
          if (target != null) 'target_url': target,
        };
      } else {
        req.headers.set('authorization',
            host == 'gitea' ? 'token $token' : 'Bearer $token');
        if (host == 'github') {
          req.headers.set('accept', 'application/vnd.github+json');
        }
        body = {
          'state': state,
          'context': context,
          'description': description,
          if (target != null) 'target_url': target,
        };
      }
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain<void>();
      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      logger.w('commit_status: ${url.host} answered ${res.statusCode} for '
          'deployment #${row['deployment_id']}');
      return false;
    } catch (e) {
      logger.w('commit_status: posting to ${url.host} for deployment '
          '#${row['deployment_id']} failed: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
