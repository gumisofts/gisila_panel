import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/infra/secret_box.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';
import 'package:gisila_panel/services/deployments_service.dart';

/// What happened to one webhook delivery.
class WebhookOutcome {
  WebhookOutcome.deployed(int this.deploymentId)
      : ignored = null,
        statusCode = 202;
  WebhookOutcome.ignored(String this.ignored)
      : deploymentId = null,
        statusCode = 200;

  final int? deploymentId;
  final String? ignored;
  final int statusCode;

  Map<String, Object?> toJson() => {
        if (deploymentId != null) 'deploymentId': deploymentId,
        if (ignored != null) 'ignored': ignored,
      };
}

/// Push-to-deploy: each git app can have a webhook that GitHub, Gitea /
/// Forgejo or GitLab calls on every push. A push to the app's branch
/// queues a deployment.
///
/// The secret proves a delivery came from the repository host: GitHub and
/// Gitea sign the body with it (`X-Hub-Signature-256`, HMAC-SHA256),
/// GitLab sends it as `X-Gitlab-Token`. It is stored sealed and shown only
/// when created or rotated.
class WebhooksService extends Service {
  Database get _db => db<Database>();

  static const _sealColumn = SecretBox.appWebhookSecret;

  /// The URL path deliveries are sent to (relative to the panel's origin).
  static String deliveryPath(int appId) => '/webhooks/apps/$appId';

  /// Any team member may see this; it never includes the secret.
  Future<Map<String, Object?>> status(User actor, int appId) async {
    final app =
        await (AppsService()..attach(ctx)).findForUser(actor, appId);
    final row = await _row(app.id!);
    return <String, Object?>{
      'configured': row != null,
      'enabled': row?['enabled'] == true,
      'path': deliveryPath(app.id!),
      'branch': _configuredBranch(app),
      'lastDeliveryAt': (row?['last_delivery_at'] as DateTime?)
          ?.toUtc()
          .toIso8601String(),
      'lastDeliveryResult': row?['last_delivery_result'],
      'reportsStatus': row?['status_token'] != null,
    };
  }

  /// Sets the token used to report deploy status on commits (GitHub:
  /// a token with "Commit statuses: write", GitLab: `api` scope, Gitea:
  /// `write:repository`), or clears it with null.
  Future<void> setStatusToken(User actor, int appId, String? token) async {
    final app = await (AppsService()..attach(ctx))
        .requireAppRole(actor, appId, TeamRole.admin);
    final value = token?.trim();
    final updated = await _db.context().execute(
      'UPDATE app_webhooks SET status_token = \$2, updated_at = now() '
      'WHERE app_id = \$1',
      parameters: [
        app.id,
        value == null || value.isEmpty
            ? null
            : SecretBox.instance.seal(value, SecretBox.appWebhookStatusToken),
      ],
    );
    if (updated.affectedRows == 0) {
      throw BadRequest('Create the webhook first.');
    }
  }

  /// Creates the webhook, or replaces its secret, and returns the new
  /// secret. This is the only time it can be read.
  Future<Map<String, Object?>> enable(User actor, int appId) async {
    final app = await (AppsService()..attach(ctx))
        .requireAppRole(actor, appId, TeamRole.admin);
    if (app.sourceType != 'git') {
      throw BadRequest('Only apps that deploy from git can have a webhook.');
    }
    final secret = _newSecret();
    await _db.context().execute(
      'INSERT INTO app_webhooks (app_id, secret, enabled) '
      'VALUES (\$1, \$2, TRUE) ON CONFLICT (app_id) DO UPDATE '
      'SET secret = EXCLUDED.secret, enabled = TRUE, updated_at = now()',
      parameters: [app.id, SecretBox.instance.seal(secret, _sealColumn)],
    );
    return <String, Object?>{
      'path': deliveryPath(app.id!),
      'branch': _configuredBranch(app),
      'secret': secret,
    };
  }

  Future<void> disable(User actor, int appId) async {
    final app = await (AppsService()..attach(ctx))
        .requireAppRole(actor, appId, TeamRole.admin);
    await _db.context().execute(
      'DELETE FROM app_webhooks WHERE app_id = \$1',
      parameters: [app.id],
    );
  }

  /// Handles a delivery. Throws [Unauthorized] — the same for an unknown
  /// app, a disabled webhook and a bad signature, so callers can't probe
  /// which apps exist.
  Future<WebhookOutcome> deliver(
      int appId, Map<String, String> headers, List<int> body) async {
    final row = await _row(appId);
    if (row == null || row['enabled'] != true) throw _unauthorized();
    final secret =
        SecretBox.instance.open(row['secret'] as String, _sealColumn);
    final host = verify(headers, body, secret);
    if (host == null) throw _unauthorized();

    final outcome = await _handle(appId, host, headers, body,
        reportStatus: row['status_token'] != null);
    await _db.context().execute(
      'UPDATE app_webhooks SET last_delivery_at = now(), '
      'last_delivery_result = \$2 WHERE app_id = \$1',
      parameters: [
        appId,
        outcome.deploymentId != null
            ? 'deployment #${outcome.deploymentId} queued'
            : 'ignored: ${outcome.ignored}',
      ],
    );
    return outcome;
  }

  /// Which host signed [body] with [secret] (`github`, `gitea`, `gitlab`),
  /// or null when no signature checks out.
  static String? verify(
      Map<String, String> headers, List<int> body, String secret) {
    final gitlab = headers['x-gitlab-token'];
    if (gitlab != null) {
      return _equal(utf8.encode(gitlab), utf8.encode(secret))
          ? 'gitlab'
          : null;
    }
    final mac = Hmac(sha256, utf8.encode(secret)).convert(body).toString();
    final hub = headers['x-hub-signature-256'];
    if (hub != null) {
      if (!_equal(utf8.encode(hub), utf8.encode('sha256=$mac'))) return null;
      return headers.containsKey('x-gitea-event') ? 'gitea' : 'github';
    }
    final gitea = headers['x-gitea-signature'];
    if (gitea != null) {
      return _equal(utf8.encode(gitea), utf8.encode(mac)) ? 'gitea' : null;
    }
    return null;
  }

  Future<WebhookOutcome> _handle(int appId, String host,
      Map<String, String> headers, List<int> body,
      {required bool reportStatus}) async {
    final event = switch (host) {
      'gitlab' => headers['x-gitlab-event'],
      'gitea' => headers['x-gitea-event'] ?? headers['x-github-event'],
      _ => headers['x-github-event'],
    };
    if (event == 'ping') return WebhookOutcome.ignored('ping');
    if (event != 'push' && event != 'Push Hook') {
      return WebhookOutcome.ignored('event "$event"');
    }

    final Map<String, Object?> payload;
    try {
      payload = (jsonDecode(utf8.decode(body)) as Map).cast<String, Object?>();
    } catch (_) {
      throw BadRequest('The webhook body is not JSON. Set the content type '
          'to application/json in the repository settings.');
    }

    final app = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(appId))
        .first(_db.context());
    if (app == null) throw _unauthorized();
    if (app.sourceType != 'git') {
      return WebhookOutcome.ignored('app does not deploy from git');
    }

    // Without a configured branch the agent clones the repository's
    // default branch, which the push payload names.
    final repo = payload['repository'] ?? payload['project'];
    final branch = _configuredBranch(app) ??
        (repo is Map ? repo['default_branch'] as String? : null);
    if (branch == null) {
      return WebhookOutcome.ignored('no branch set for the app');
    }
    final ref = payload['ref'];
    if (ref != 'refs/heads/$branch') {
      return WebhookOutcome.ignored('push to $ref, not refs/heads/$branch');
    }
    final sha = (host == 'gitlab' ? payload['checkout_sha'] : null) ??
        payload['after'];
    if (payload['deleted'] == true ||
        sha == null ||
        (sha is String && RegExp(r'^0+$').hasMatch(sha))) {
      return WebhookOutcome.ignored('branch deleted');
    }
    if (sha is! String ||
        !RegExp(r'^[0-9a-f]{40}([0-9a-f]{24})?$').hasMatch(sha)) {
      throw BadRequest('The push has no valid commit id.');
    }

    final delivery = headers['x-github-delivery'] ??
        headers['x-gitea-delivery'] ??
        headers['x-gitlab-event-uuid'];
    if (delivery != null && !await _firstDelivery(appId, delivery)) {
      return WebhookOutcome.ignored('duplicate delivery');
    }

    // The build clones the branch head when it starts, so one deployment
    // still waiting in the queue already covers this push.
    final waiting = await Query<Deployment>(DeploymentTable.metadata)
        .where(DeploymentTable.appId.eq(appId))
        .where(DeploymentTable.status.eq('queued'))
        .first(_db.context());
    if (waiting != null) {
      return WebhookOutcome.ignored(
          'deployment #${waiting.id} is already queued');
    }

    final deployment = await (DeploymentsService()..attach(ctx)).queue(
      app,
      sourceType: 'git',
      gitCommitSha: sha,
      reason: 'by a push to $branch (${sha.substring(0, 7)}, $host)',
    );
    if (reportStatus) {
      final url = statusUrl(host, payload, sha, app.gitUrl);
      if (url != null) {
        await _db.context().execute(
          'INSERT INTO deployment_commit_statuses (deployment_id, app_id, '
          'host, url) VALUES (\$1, \$2, \$3, \$4)',
          parameters: [deployment.id, appId, host, url.toString()],
        );
      }
    }
    return WebhookOutcome.deployed(deployment.id!);
  }

  /// The repository host's commit-status URL for [sha], built from the
  /// signed push payload. Null unless it is https on the app's own git host
  /// (or `api.` + that host, as for github.com), so a crafted payload can't
  /// make the panel send the token anywhere else.
  static Uri? statusUrl(String host, Map<String, Object?> payload, String sha,
      String? gitUrl) {
    final repo = payload['repository'];
    final project = payload['project'];
    Uri? url;
    switch (host) {
      case 'github':
        final template = repo is Map ? repo['statuses_url'] : null;
        if (template is String) {
          url = Uri.tryParse(template.replaceAll('{sha}', sha));
        }
      case 'gitea':
        final html = repo is Map ? repo['html_url'] : null;
        final name = repo is Map ? repo['full_name'] : null;
        final base = html is String ? Uri.tryParse(html) : null;
        if (base != null && name is String) {
          url = _at(base, '/api/v1/repos/$name/statuses/$sha');
        }
      case 'gitlab':
        final web = project is Map ? project['web_url'] : null;
        final id = project is Map ? project['id'] : null;
        final base = web is String ? Uri.tryParse(web) : null;
        if (base != null && id is int) {
          url = _at(base, '/api/v4/projects/$id/statuses/$sha');
        }
    }
    final gitHost = _gitHost(gitUrl);
    if (url == null ||
        gitHost == null ||
        url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        (url.host != gitHost && url.host != 'api.$gitHost')) {
      return null;
    }
    return url;
  }

  static Uri _at(Uri base, String path) => Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: path);

  /// Host of a git URL: `git@github.com:o/r.git`, `https://github.com/o/r`,
  /// `ssh://git@host:2222/o/r`.
  static String? _gitHost(String? gitUrl) {
    if (gitUrl == null || gitUrl.isEmpty) return null;
    final scp = RegExp(r'^[\w.-]+@([\w.-]+):').firstMatch(gitUrl);
    if (scp != null && !gitUrl.contains('://')) {
      return scp.group(1)!.toLowerCase();
    }
    final uri = Uri.tryParse(gitUrl);
    return (uri == null || uri.host.isEmpty) ? null : uri.host.toLowerCase();
  }

  Future<bool> _firstDelivery(int appId, String delivery) async {
    final c = _db.context();
    await c.execute(
      "DELETE FROM app_webhook_deliveries "
      "WHERE created_at < now() - interval '7 days'",
    );
    final inserted = await c.execute(
      'INSERT INTO app_webhook_deliveries (app_id, delivery_id) '
      'VALUES (\$1, \$2) ON CONFLICT DO NOTHING RETURNING app_id',
      parameters: [
        appId,
        delivery.length > 128 ? delivery.substring(0, 128) : delivery,
      ],
    );
    return inserted.isNotEmpty;
  }

  Future<Map<String, Object?>?> _row(int appId) async {
    final rows = await _db.context().execute(
      'SELECT secret, enabled, last_delivery_at, last_delivery_result, '
      'status_token '
      'FROM app_webhooks WHERE app_id = \$1',
      parameters: [appId],
    );
    return rows.isEmpty ? null : rows.first.toColumnMap();
  }

  /// The app's branch, or null when it builds the repository's default.
  static String? _configuredBranch(App app) =>
      (app.gitBranch == null || app.gitBranch!.isEmpty) ? null : app.gitBranch;

  static String _newSecret() {
    final rnd = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => rnd.nextInt(256)))
        .replaceAll('=', '');
  }

  static bool _equal(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static HttpException _unauthorized() => HttpException(
      401, 'Invalid webhook signature.',
      code: 'invalid_signature');
}
