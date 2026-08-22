import 'dart:async';
import 'dart:io';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';

/// Alerting + notification delivery: the panel-wide SMTP config, threshold
/// [AlertRule]s (system / app / postgres / mongo / mail / service / runtime
/// scoped), the [AlertEvent] history they produce, and the per-user
/// [Notification] inbox those events fan out to. See the comment block above
/// these models in `schema.gisila.yaml` for the full design.
///
/// The actual logic lives in [NotificationCore], a plain class that only
/// needs a [Database] — that's what [AlertEvaluator] (a worker, outside any
/// HTTP request) uses directly. This class is the thin `Service` façade the
/// HTTP endpoints use instead, matching every other `*Service` in this
/// codebase (`db<Database>()` is only resolvable inside a request context).
class NotificationService extends Service {
  NotificationCore get _core => NotificationCore(db<Database>());

  Future<SmtpConfig> getSmtpConfig() => _core.getSmtpConfig();

  Future<SmtpConfig> updateSmtpConfig({
    String? smtpHost,
    int? smtpPort,
    String? smtpUsername,
    String? smtpPassword,
    String? smtpSecurity,
    String? fromEmail,
    String? fromName,
    bool? emailEnabled,
    String? alertEmail,
  }) => _core.updateSmtpConfig(
        smtpHost: smtpHost,
        smtpPort: smtpPort,
        smtpUsername: smtpUsername,
        smtpPassword: smtpPassword,
        smtpSecurity: smtpSecurity,
        fromEmail: fromEmail,
        fromName: fromName,
        emailEnabled: emailEnabled,
        alertEmail: alertEmail,
      );

  Future<void> sendTestEmail(String toEmail) => _core.sendTestEmail(toEmail);

  Future<List<AlertRule>> listAlertRules({
    String? scope,
    int? appId,
    int? postgresInstanceId,
    int? mongoInstanceId,
    int? managedServiceId,
    int? applicationId,
  }) => _core.listAlertRules(
        scope: scope,
        appId: appId,
        postgresInstanceId: postgresInstanceId,
        mongoInstanceId: mongoInstanceId,
        managedServiceId: managedServiceId,
        applicationId: applicationId,
      );

  Future<AlertRule> findAlertRule(int id) => _core.findAlertRule(id);

  Future<AlertRule> createAlertRule({
    required String scope,
    int? appId,
    int? postgresInstanceId,
    int? mongoInstanceId,
    int? managedServiceId,
    int? applicationId,
    required String metric,
    String comparison = 'gte',
    int? thresholdPercent,
    String severity = 'warning',
    int cooldownMinutes = 15,
    bool enabled = true,
    bool notifyEmail = true,
    int? createdByUserId,
  }) => _core.createAlertRule(
        scope: scope,
        appId: appId,
        postgresInstanceId: postgresInstanceId,
        mongoInstanceId: mongoInstanceId,
        managedServiceId: managedServiceId,
        applicationId: applicationId,
        metric: metric,
        comparison: comparison,
        thresholdPercent: thresholdPercent,
        severity: severity,
        cooldownMinutes: cooldownMinutes,
        enabled: enabled,
        notifyEmail: notifyEmail,
        createdByUserId: createdByUserId,
      );

  Future<AlertRule> updateAlertRule(
    int id, {
    String? metric,
    String? comparison,
    int? thresholdPercent,
    String? severity,
    int? cooldownMinutes,
    bool? enabled,
    bool? notifyEmail,
  }) => _core.updateAlertRule(
        id,
        metric: metric,
        comparison: comparison,
        thresholdPercent: thresholdPercent,
        severity: severity,
        cooldownMinutes: cooldownMinutes,
        enabled: enabled,
        notifyEmail: notifyEmail,
      );

  Future<void> deleteAlertRule(int id) => _core.deleteAlertRule(id);

  Future<List<AlertEvent>> listEvents({
    String? scope,
    int? appId,
    int? postgresInstanceId,
    int? mongoInstanceId,
    int? managedServiceId,
    int? applicationId,
    int limit = 50,
  }) => _core.listEvents(
        scope: scope,
        appId: appId,
        postgresInstanceId: postgresInstanceId,
        mongoInstanceId: mongoInstanceId,
        managedServiceId: managedServiceId,
        applicationId: applicationId,
        limit: limit,
      );

  Future<List<Notification>> listInbox(int userId, {bool unreadOnly = false, int limit = 50}) =>
      _core.listInbox(userId, unreadOnly: unreadOnly, limit: limit);

  Future<int> unreadCount(int userId) => _core.unreadCount(userId);

  Future<void> markRead(int userId, int id) => _core.markRead(userId, id);

  Future<void> markAllRead(int userId) => _core.markAllRead(userId);
}

/// Plain (non-`Service`) implementation, usable both from HTTP endpoints
/// (via [NotificationService]) and directly from [AlertEvaluator], which runs
/// as a self-driven worker outside any request context.
class NotificationCore {
  NotificationCore(this._db);
  final Database _db;

  // ── SMTP config (singleton) ─────────────────────────────────────────────

  /// Reads the single SMTP config row, creating an empty (disabled) one on
  /// first access so callers never have to special-case "not configured yet".
  Future<SmtpConfig> getSmtpConfig() async {
    final existing = await Query<SmtpConfig>(SmtpConfigTable.metadata)
        .orderBy(SmtpConfigTable.id)
        .first(_db.context());
    if (existing != null) return existing;

    return Query<SmtpConfig>(SmtpConfigTable.metadata).insert(<String, Object?>{
      'smtpPort': 587,
      'smtpSecurity': 'starttls',
      'fromName': 'Gisila Panel',
      'emailEnabled': false,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
  }

  Future<SmtpConfig> updateSmtpConfig({
    String? smtpHost,
    int? smtpPort,
    String? smtpUsername,
    String? smtpPassword,
    String? smtpSecurity,
    String? fromEmail,
    String? fromName,
    bool? emailEnabled,
    String? alertEmail,
  }) async {
    final cfg = await getSmtpConfig();
    if (emailEnabled == true) {
      final host = smtpHost ?? cfg.smtpHost;
      final from = fromEmail ?? cfg.fromEmail;
      if (host == null || host.isEmpty || from == null || from.isEmpty) {
        throw HttpException(
          422,
          'An SMTP host and "from" address are required before enabling email delivery.',
        );
      }
    }

    final data = <String, Object?>{
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (smtpHost != null) data['smtpHost'] = smtpHost.isEmpty ? null : smtpHost;
    if (smtpPort != null) data['smtpPort'] = smtpPort;
    if (smtpUsername != null) data['smtpUsername'] = smtpUsername.isEmpty ? null : smtpUsername;
    // An empty password means "leave the stored one alone" (the UI never
    // re-displays it, so an empty field is not "the user wants to clear it").
    if (smtpPassword != null && smtpPassword.isNotEmpty) {
      data['smtpPassword'] = smtpPassword;
    }
    if (smtpSecurity != null) data['smtpSecurity'] = smtpSecurity;
    if (fromEmail != null) data['fromEmail'] = fromEmail.isEmpty ? null : fromEmail;
    if (fromName != null) data['fromName'] = fromName;
    if (emailEnabled != null) data['emailEnabled'] = emailEnabled;
    // The settings form always submits this field. Blank (the form binder
    // turns "" into null) clears the dedicated recipient.
    data['alertEmail'] = (alertEmail == null || alertEmail.isEmpty) ? null : alertEmail;

    await Query<SmtpConfig>(SmtpConfigTable.metadata)
        .where(SmtpConfigTable.id.eq(cfg.id!))
        .update(data)
        .run(_db.context());
    return getSmtpConfig();
  }

  /// Sends a one-off test message using the *currently stored* config
  /// (ignoring `email_enabled`, since testing is how an operator verifies the
  /// config before flipping that switch on).
  Future<void> sendTestEmail(String toEmail) async {
    final cfg = await getSmtpConfig();
    if (cfg.smtpHost == null || cfg.smtpHost!.isEmpty) {
      throw HttpException(422, 'Configure an SMTP host first.');
    }
    final fromEmail = cfg.fromEmail ?? cfg.smtpUsername;
    if (fromEmail == null || fromEmail.isEmpty) {
      throw HttpException(422, 'A "from" address is not configured.');
    }

    final security = cfg.smtpSecurity ?? 'starttls';
    final server = SmtpServer(
      cfg.smtpHost!,
      port: cfg.smtpPort ?? 587,
      username: cfg.smtpUsername,
      password: cfg.smtpPassword,
      ssl: security == 'ssl',
      allowInsecure: security == 'none',
    );
    final message = Message()
      ..from = Address(fromEmail, cfg.fromName ?? 'Gisila Panel')
      ..recipients.add(toEmail)
      ..subject = 'Gisila Panel — test notification'
      ..text = 'This is a test email from Gisila Panel. If you can read this, '
          'outbound alert email is configured correctly.';

    // A bad host/port/credentials/TLS mode is the whole point of this
    // endpoint — surface it as a 422 with the real reason instead of letting
    // it fall through to the generic "Internal server error" 500. `send()`
    // can throw a `MailerException` (auth, protocol, "connection not secure")
    // or a bare `SocketException`/`TimeoutException` for connect failures —
    // neither is caught by the framework's `TypeError`/`FormatException`
    // coercion handling, so it has to be done here.
    try {
      await send(message, server, timeout: const Duration(seconds: 20));
    } on MailerException catch (e) {
      throw HttpException(422, 'Could not send test email: ${e.message}');
    } on SocketException catch (e) {
      throw HttpException(
        422,
        'Could not reach ${cfg.smtpHost}:${server.port} — ${e.message}.',
      );
    } on TimeoutException {
      throw HttpException(
        422,
        'Connecting to ${cfg.smtpHost}:${server.port} timed out after 20s.',
      );
    }
  }

  // ── Alert rules ──────────────────────────────────────────────────────────

  Future<List<AlertRule>> listAlertRules({
    String? scope,
    int? appId,
    int? postgresInstanceId,
    int? mongoInstanceId,
    int? managedServiceId,
    int? applicationId,
  }) async {
    var q = Query<AlertRule>(AlertRuleTable.metadata);
    if (scope != null) q = q.where(AlertRuleTable.scope.eq(scope));
    if (appId != null) q = q.where(AlertRuleTable.appId.eq(appId));
    if (postgresInstanceId != null) {
      q = q.where(AlertRuleTable.postgresInstanceId.eq(postgresInstanceId));
    }
    if (mongoInstanceId != null) {
      q = q.where(AlertRuleTable.mongoInstanceId.eq(mongoInstanceId));
    }
    if (managedServiceId != null) {
      q = q.where(AlertRuleTable.managedServiceId.eq(managedServiceId));
    }
    if (applicationId != null) {
      q = q.where(AlertRuleTable.applicationId.eq(applicationId));
    }
    return q.orderBy(AlertRuleTable.createdAt, desc: true).all(_db.context());
  }

  /// Every enabled rule — the set [AlertEvaluator] walks each tick.
  Future<List<AlertRule>> listEnabledRules() => Query<AlertRule>(AlertRuleTable.metadata)
      .where(AlertRuleTable.enabled.eq(true))
      .all(_db.context());

  Future<AlertRule> findAlertRule(int id) async {
    final rule = await Query<AlertRule>(AlertRuleTable.metadata)
        .where(AlertRuleTable.id.eq(id))
        .first(_db.context());
    if (rule == null) throw NotFound('Alert rule #$id not found.');
    return rule;
  }

  Future<AlertRule> createAlertRule({
    required String scope,
    int? appId,
    int? postgresInstanceId,
    int? mongoInstanceId,
    int? managedServiceId,
    int? applicationId,
    required String metric,
    String comparison = 'gte',
    int? thresholdPercent,
    String severity = 'warning',
    int cooldownMinutes = 15,
    bool enabled = true,
    bool notifyEmail = true,
    int? createdByUserId,
  }) async {
    _validateScope(
      scope: scope,
      appId: appId,
      postgresInstanceId: postgresInstanceId,
      mongoInstanceId: mongoInstanceId,
      managedServiceId: managedServiceId,
      applicationId: applicationId,
    );
    _validateMetric(metric: metric, thresholdPercent: thresholdPercent);

    return Query<AlertRule>(AlertRuleTable.metadata).insert(<String, Object?>{
      'scope': scope,
      'appId': appId,
      'postgresInstanceId': postgresInstanceId,
      'mongoInstanceId': mongoInstanceId,
      'managedServiceId': managedServiceId,
      'applicationId': applicationId,
      'metric': metric,
      'comparison': comparison,
      'thresholdPercent': thresholdPercent,
      'severity': severity,
      'cooldownMinutes': cooldownMinutes,
      'enabled': enabled,
      'notifyEmail': notifyEmail,
      'createdById': createdByUserId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
  }

  /// Partial update: only non-null arguments are applied. `thresholdPercent`
  /// is meaningless for `status_down` rules, so it's fine for it to keep a
  /// stale value across a metric switch — the evaluator never reads it for
  /// that metric. Clients that always resubmit the whole form (as the panel
  /// UI does) get the behaviour they expect either way.
  Future<AlertRule> updateAlertRule(
    int id, {
    String? metric,
    String? comparison,
    int? thresholdPercent,
    String? severity,
    int? cooldownMinutes,
    bool? enabled,
    bool? notifyEmail,
  }) async {
    final rule = await findAlertRule(id);
    final data = <String, Object?>{
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    if (metric != null) data['metric'] = metric;
    if (comparison != null) data['comparison'] = comparison;
    if (thresholdPercent != null) data['thresholdPercent'] = thresholdPercent;
    if (severity != null) data['severity'] = severity;
    if (cooldownMinutes != null) data['cooldownMinutes'] = cooldownMinutes;
    if (enabled != null) data['enabled'] = enabled;
    if (notifyEmail != null) data['notifyEmail'] = notifyEmail;

    _validateMetric(
      metric: metric ?? rule.metric,
      thresholdPercent: thresholdPercent ?? rule.thresholdPercent,
    );

    await Query<AlertRule>(AlertRuleTable.metadata)
        .where(AlertRuleTable.id.eq(id))
        .update(data)
        .run(_db.context());
    return findAlertRule(id);
  }

  Future<void> deleteAlertRule(int id) async {
    await findAlertRule(id);
    await Query<AlertRule>(AlertRuleTable.metadata)
        .where(AlertRuleTable.id.eq(id))
        .delete()
        .run(_db.context());
  }

  void _validateScope({
    required String scope,
    int? appId,
    int? postgresInstanceId,
    int? mongoInstanceId,
    int? managedServiceId,
    int? applicationId,
  }) {
    switch (scope) {
      case 'system':
        if (appId != null || postgresInstanceId != null || mongoInstanceId != null) {
          throw HttpException(422, 'System-scoped rules must not reference a target.');
        }
      case 'app':
        if (appId == null) throw HttpException(422, 'appId is required for app-scoped rules.');
      case 'postgres':
        if (postgresInstanceId == null) {
          throw HttpException(422, 'postgresInstanceId is required for postgres-scoped rules.');
        }
      case 'mongo':
        if (mongoInstanceId == null) {
          throw HttpException(422, 'mongoInstanceId is required for mongo-scoped rules.');
        }
      case 'mail':
        // System-wide singleton, like `system` — no target to reference.
        break;
      case 'service':
        if (managedServiceId == null) {
          throw HttpException(422, 'managedServiceId is required for service-scoped rules.');
        }
      case 'runtime':
        if (applicationId == null) {
          throw HttpException(422, 'applicationId is required for runtime-scoped rules.');
        }
      default:
        throw HttpException(422, 'Unknown scope "$scope".');
    }
  }

  static const validMetrics = {
    'cpu_percent',
    'memory_percent',
    'disk_percent',
    'connections_percent',
    'status_down',
  };

  /// CPU is "percent of one core" for postgres (and apps vs their quota can
  /// overshoot), so the ceiling is host cores × 100 rather than 100.
  static final int _maxCpuThresholdPercent = Platform.numberOfProcessors * 100;

  void _validateMetric({required String metric, int? thresholdPercent}) {
    if (!validMetrics.contains(metric)) {
      throw HttpException(422, 'Unknown metric "$metric".');
    }
    if (metric == 'status_down') return;
    if (thresholdPercent == null || thresholdPercent < 0) {
      throw HttpException(422, 'thresholdPercent is required for "$metric".');
    }
    final max = metric == 'cpu_percent' ? _maxCpuThresholdPercent : 100;
    if (thresholdPercent > max) {
      throw HttpException(422, 'thresholdPercent must be between 0 and $max.');
    }
  }

  // ── Recipients ───────────────────────────────────────────────────────────

  /// Resolves who should be notified for [rule]:
  ///  * `system` / `postgres` / `mongo` — every active superuser (databases
  ///    and the host itself are infrastructure, not team-owned; see
  ///    `DatabasesApi`/`MongoApi`, which are superuser-only end to end).
  ///  * `app` — every member of the app's team.
  Future<List<User>> recipientsForRule(AlertRule rule) async {
    if (rule.scope != 'app') {
      return Query<User>(UserTable.metadata)
          .where(UserTable.isSuperuser.eq(true))
          .where(UserTable.isActive.eq(true))
          .all(_db.context());
    }

    final appId = rule.appId;
    if (appId == null) return const [];
    final app = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(appId))
        .first(_db.context());
    if (app == null) return const [];
    final project = await Query<Project>(ProjectTable.metadata)
        .where(ProjectTable.id.eq(app.projectId))
        .first(_db.context());
    if (project == null) return const [];

    final members = await Query<TeamMember>(TeamMemberTable.metadata)
        .where(TeamMemberTable.teamId.eq(project.teamId))
        .all(_db.context());
    final userIds = members.map((m) => m.userId).toList();
    if (userIds.isEmpty) return const [];

    return Query<User>(UserTable.metadata)
        .where(UserTable.id.inList(userIds))
        .where(UserTable.isActive.eq(true))
        .all(_db.context());
  }

  // ── Alert events (firing / resolving) ───────────────────────────────────

  /// The most recent still-open (`firing`) event for [ruleId], if any. The
  /// evaluator uses this both to avoid re-firing inside the cooldown window
  /// and to detect recovery (metric back under threshold while one is open).
  Future<AlertEvent?> findOpenEvent(int ruleId) => Query<AlertEvent>(AlertEventTable.metadata)
      .where(AlertEventTable.ruleId.eq(ruleId))
      .where(AlertEventTable.status.eq('firing'))
      .orderBy(AlertEventTable.createdAt, desc: true)
      .first(_db.context());

  /// Records a new firing, fans it out to the per-user inbox, and (subject to
  /// [AlertRule.notifyEmail] + the global SMTP toggle) sends one alert email
  /// covering every recipient.
  Future<AlertEvent> fireEvent(
    AlertRule rule, {
    required int? observedPercent,
    required String message,
  }) async {
    final now = DateTime.now().toUtc();
    final event = await Query<AlertEvent>(AlertEventTable.metadata).insert(<String, Object?>{
      'ruleId': rule.id,
      'scope': rule.scope,
      'appId': rule.appId,
      'postgresInstanceId': rule.postgresInstanceId,
      'mongoInstanceId': rule.mongoInstanceId,
      'managedServiceId': rule.managedServiceId,
      'applicationId': rule.applicationId,
      'metric': rule.metric,
      'observedPercent': observedPercent,
      'thresholdPercent': rule.thresholdPercent,
      'severity': rule.severity,
      'message': message,
      'status': 'firing',
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await Query<AlertRule>(AlertRuleTable.metadata)
        .where(AlertRuleTable.id.eq(rule.id!))
        .update({'lastTriggeredAt': now.toIso8601String()})
        .run(_db.context());

    final recipients = await recipientsForRule(rule);
    await _fanOutNotifications(
      event: event,
      recipients: recipients,
      title: _titleFor(rule),
      level: rule.severity ?? 'warning',
      body: message,
    );

    if (rule.notifyEmail == true) {
      await _emailEvent(event, recipients, message);
    }

    return event;
  }

  /// Marks the still-open event as resolved and lets recipients know the
  /// metric is back under threshold.
  Future<void> resolveEvent(AlertEvent event, AlertRule rule) async {
    final now = DateTime.now().toUtc();
    await Query<AlertEvent>(AlertEventTable.metadata)
        .where(AlertEventTable.id.eq(event.id!))
        .update({'status': 'resolved', 'resolvedAt': now.toIso8601String()})
        .run(_db.context());

    final recipients = await recipientsForRule(rule);
    await _fanOutNotifications(
      event: event,
      recipients: recipients,
      title: 'Resolved: ${_targetLabel(rule)} ${_metricLabel(rule.metric)}',
      level: 'info',
      body: 'Back under the configured threshold.',
    );
  }

  Future<void> _fanOutNotifications({
    required AlertEvent event,
    required List<User> recipients,
    required String title,
    required String level,
    required String body,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final user in recipients) {
      if (user.id == null) continue;
      await Query<Notification>(NotificationTable.metadata).insert(<String, Object?>{
        'userId': user.id,
        'eventId': event.id,
        'title': title,
        'body': body,
        'level': level,
        'createdAt': now,
      }).run(_db.context());
    }
  }

  Future<void> _emailEvent(AlertEvent event, List<User> recipients, String message) async {
    final cfg = await getSmtpConfig();
    if (cfg.emailEnabled != true || cfg.smtpHost == null || cfg.smtpHost!.isEmpty) return;
    final addresses = recipients
        .map((u) => u.email)
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toList();
    final dedicated = cfg.alertEmail?.trim();
    if (dedicated != null && dedicated.isNotEmpty && !addresses.contains(dedicated)) {
      addresses.add(dedicated);
    }
    if (addresses.isEmpty) return;

    try {
      final fromEmail = cfg.fromEmail ?? cfg.smtpUsername!;
      final security = cfg.smtpSecurity ?? 'starttls';
      final server = SmtpServer(
        cfg.smtpHost!,
        port: cfg.smtpPort ?? 587,
        username: cfg.smtpUsername,
        password: cfg.smtpPassword,
        ssl: security == 'ssl',
        allowInsecure: security == 'none',
      );
      final mail = Message()
        ..from = Address(fromEmail, cfg.fromName ?? 'Gisila Panel')
        ..recipients.addAll(addresses)
        ..subject = '[Gisila Panel] $message'
        ..text = message;

      await send(mail, server, timeout: const Duration(seconds: 20));
      await Query<AlertEvent>(AlertEventTable.metadata)
          .where(AlertEventTable.id.eq(event.id!))
          .update({'emailSentAt': DateTime.now().toUtc().toIso8601String()})
          .run(_db.context());
    } catch (e) {
      logger.w('notifications: alert email failed for event ${event.id}: $e');
      await Query<AlertEvent>(AlertEventTable.metadata)
          .where(AlertEventTable.id.eq(event.id!))
          .update({'emailError': e.toString()})
          .run(_db.context());
    }
  }

  String _titleFor(AlertRule rule) =>
      '${_severityPrefix(rule.severity)}${_targetLabel(rule)} ${_metricLabel(rule.metric)}';

  String _severityPrefix(String? severity) => severity == 'critical' ? 'Critical: ' : 'Warning: ';

  String _targetLabel(AlertRule rule) => switch (rule.scope) {
        'system' => 'Server',
        'app' => 'App',
        'postgres' => 'Postgres instance',
        'mongo' => 'Mongo instance',
        'mail' => 'Mail stack',
        'service' => 'Service',
        'runtime' => 'Runtime',
        _ => 'Resource',
      };

  String _metricLabel(String? metric) => switch (metric) {
        'cpu_percent' => 'CPU usage high',
        'memory_percent' => 'memory usage high',
        'disk_percent' => 'disk usage high',
        'connections_percent' => 'connection usage high',
        'status_down' => 'is down',
        _ => 'threshold breached',
      };

  // ── Event history ────────────────────────────────────────────────────────

  Future<List<AlertEvent>> listEvents({
    String? scope,
    int? appId,
    int? postgresInstanceId,
    int? mongoInstanceId,
    int? managedServiceId,
    int? applicationId,
    int limit = 50,
  }) async {
    var q = Query<AlertEvent>(AlertEventTable.metadata);
    if (scope != null) q = q.where(AlertEventTable.scope.eq(scope));
    if (appId != null) q = q.where(AlertEventTable.appId.eq(appId));
    if (postgresInstanceId != null) {
      q = q.where(AlertEventTable.postgresInstanceId.eq(postgresInstanceId));
    }
    if (mongoInstanceId != null) {
      q = q.where(AlertEventTable.mongoInstanceId.eq(mongoInstanceId));
    }
    if (managedServiceId != null) {
      q = q.where(AlertEventTable.managedServiceId.eq(managedServiceId));
    }
    if (applicationId != null) {
      q = q.where(AlertEventTable.applicationId.eq(applicationId));
    }
    return q.orderBy(AlertEventTable.createdAt, desc: true).limit(limit).all(_db.context());
  }

  // ── Inbox (per-user) ─────────────────────────────────────────────────────

  Future<List<Notification>> listInbox(
    int userId, {
    bool unreadOnly = false,
    int limit = 50,
  }) async {
    var q = Query<Notification>(NotificationTable.metadata)
        .where(NotificationTable.userId.eq(userId));
    if (unreadOnly) q = q.where(NotificationTable.readAt.isNull);
    return q.orderBy(NotificationTable.createdAt, desc: true).limit(limit).all(_db.context());
  }

  Future<int> unreadCount(int userId) => Query<Notification>(NotificationTable.metadata)
      .where(NotificationTable.userId.eq(userId))
      .where(NotificationTable.readAt.isNull)
      .count(_db.context());

  Future<void> markRead(int userId, int id) async {
    final row = await Query<Notification>(NotificationTable.metadata)
        .where(NotificationTable.id.eq(id))
        .where(NotificationTable.userId.eq(userId))
        .first(_db.context());
    if (row == null) throw NotFound('Notification #$id not found.');
    if (row.readAt != null) return;
    await Query<Notification>(NotificationTable.metadata)
        .where(NotificationTable.id.eq(id))
        .update({'readAt': DateTime.now().toUtc().toIso8601String()})
        .run(_db.context());
  }

  Future<void> markAllRead(int userId) async {
    await Query<Notification>(NotificationTable.metadata)
        .where(NotificationTable.userId.eq(userId))
        .where(NotificationTable.readAt.isNull)
        .update({'readAt': DateTime.now().toUtc().toIso8601String()})
        .run(_db.context());
  }
}
