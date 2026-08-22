import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/forms/notification_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';
import 'package:gisila_panel/services/notification_service.dart';
import 'package:gisila_panel/workers/host_stats_sampler.dart';

part 'notifications.g.dart';

/// SMTP config, threshold [AlertRule]s, their [AlertEvent] history, the
/// whole-host usage snapshot the rule editor previews against, and the
/// per-user notification inbox.
///
/// Access rules (mirroring `NotificationCore.recipientsForRule`):
///  * `system` / `postgres` / `mongo` / `mail` / `service` / `runtime` scoped
///    rules + the SMTP config are superuser-only — none of those resources
///    are team-owned.
///  * `app` scoped rules follow normal team RBAC: any member can read,
///    `developer`+ can write (same bar as editing the app's resource quota
///    in `AppsApi.update`).
@Controller('/notifications', ['Notifications'])
@RequireAuth()
class NotificationsApi {
  // ── SMTP config ──────────────────────────────────────────────────────

  @Get('/settings/smtp', summary: 'Get the panel-wide SMTP config')
  Future<Map<String, Object?>> getSmtpConfig(
    NotificationService notifications,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final cfg = await notifications.getSmtpConfig();
    return cfg.toJson(exclude: ['smtp_password']);
  }

  @Put('/settings/smtp', summary: 'Update the panel-wide SMTP config')
  Future<Map<String, Object?>> updateSmtpConfig(
    UpdateSmtpConfigForm form,
    NotificationService notifications,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final cfg = await notifications.updateSmtpConfig(
      smtpHost: form.smtpHost.value,
      smtpPort: form.smtpPort.value,
      smtpUsername: form.smtpUsername.value,
      smtpPassword: form.smtpPassword.value,
      smtpSecurity: form.smtpSecurity.value,
      fromEmail: form.fromEmail.value,
      fromName: form.fromName.value,
      emailEnabled: form.emailEnabled.value,
      alertEmail: form.alertEmail.value,
    );
    return cfg.toJson(exclude: ['smtp_password']);
  }

  @Post('/settings/smtp/test', summary: 'Send a one-off test email')
  Future<Map<String, Object?>> sendTestEmail(
    SendTestEmailForm form,
    NotificationService notifications,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await notifications.sendTestEmail(form.toEmail.value!);
    return <String, Object?>{'detail': 'Test email sent.'};
  }

  // ── Host stats (system-scope rule editor preview) ──────────────────

  @Get('/host-stats', summary: 'Latest whole-host CPU / memory / disk snapshot')
  Future<Map<String, Object?>> hostStats(RequestContext ctx) async {
    requireSuperuser(ctx);
    final snapshot = await readLatestHostStats();
    return <String, Object?>{'snapshot': snapshot};
  }

  // ── Alert rules ──────────────────────────────────────────────────────

  @Get('/rules', summary: 'List alert rules')
  Future<Map<String, Object?>> listRules(
    NotificationService notifications,
    AppsService apps,
    RequestContext ctx,
    String? scope,
    int? appId,
    int? postgresInstanceId,
    int? mongoInstanceId,
    int? managedServiceId,
    int? applicationId,
  ) async {
    await _requireReadAccess(ctx, apps, scope: scope, appId: appId);
    final rules = await notifications.listAlertRules(
      scope: scope,
      appId: appId,
      postgresInstanceId: postgresInstanceId,
      mongoInstanceId: mongoInstanceId,
      managedServiceId: managedServiceId,
      applicationId: applicationId,
    );
    return <String, Object?>{'results': rules.map((r) => r.toJson()).toList()};
  }

  @Get('/rules/{id}', summary: 'Get an alert rule')
  Future<Map<String, Object?>> retrieveRule(
    int id,
    NotificationService notifications,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final rule = await notifications.findAlertRule(id);
    await _requireReadAccess(ctx, apps, scope: rule.scope, appId: rule.appId);
    return rule.toJson();
  }

  @Post('/rules', summary: 'Create an alert rule')
  Future<Map<String, Object?>> createRule(
    CreateAlertRuleForm form,
    NotificationService notifications,
    AppsService apps,
    RequestContext ctx,
  ) async {
    await _requireWriteAccess(
      ctx,
      apps,
      scope: form.scope.value!,
      appId: form.appId.value,
    );
    final rule = await notifications.createAlertRule(
      scope: form.scope.value!,
      appId: form.appId.value,
      postgresInstanceId: form.postgresInstanceId.value,
      mongoInstanceId: form.mongoInstanceId.value,
      managedServiceId: form.managedServiceId.value,
      applicationId: form.applicationId.value,
      metric: form.metric.value!,
      comparison: form.comparison.value ?? 'gte',
      thresholdPercent: form.thresholdPercent.value,
      severity: form.severity.value ?? 'warning',
      cooldownMinutes: form.cooldownMinutes.value ?? 15,
      enabled: form.enabled.value ?? true,
      notifyEmail: form.notifyEmail.value ?? true,
      createdByUserId: currentUser(ctx).id,
    );
    return rule.toJson();
  }

  @Put('/rules/{id}', summary: 'Update an alert rule')
  Future<Map<String, Object?>> updateRule(
    int id,
    UpdateAlertRuleForm form,
    NotificationService notifications,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final existing = await notifications.findAlertRule(id);
    await _requireWriteAccess(ctx, apps, scope: existing.scope, appId: existing.appId);
    final rule = await notifications.updateAlertRule(
      id,
      metric: form.metric.value,
      comparison: form.comparison.value,
      thresholdPercent: form.thresholdPercent.value,
      severity: form.severity.value,
      cooldownMinutes: form.cooldownMinutes.value,
      enabled: form.enabled.value,
      notifyEmail: form.notifyEmail.value,
    );
    return rule.toJson();
  }

  @Delete('/rules/{id}', summary: 'Delete an alert rule')
  Future<Map<String, Object?>> deleteRule(
    int id,
    NotificationService notifications,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final existing = await notifications.findAlertRule(id);
    await _requireWriteAccess(ctx, apps, scope: existing.scope, appId: existing.appId);
    await notifications.deleteAlertRule(id);
    return <String, Object?>{'detail': 'Alert rule deleted.'};
  }

  // ── Alert event history ──────────────────────────────────────────────

  @Get('/events', summary: 'List alert event history')
  Future<Map<String, Object?>> listEvents(
    NotificationService notifications,
    AppsService apps,
    RequestContext ctx,
    String? scope,
    int? appId,
    int? postgresInstanceId,
    int? mongoInstanceId,
    int? managedServiceId,
    int? applicationId,
    int? limit,
  ) async {
    await _requireReadAccess(ctx, apps, scope: scope, appId: appId);
    final events = await notifications.listEvents(
      scope: scope,
      appId: appId,
      postgresInstanceId: postgresInstanceId,
      mongoInstanceId: mongoInstanceId,
      managedServiceId: managedServiceId,
      applicationId: applicationId,
      limit: limit ?? 50,
    );
    return <String, Object?>{'results': events.map((e) => e.toJson()).toList()};
  }

  // ── Per-user inbox ────────────────────────────────────────────────────

  @Get('/inbox', summary: 'List the current user\'s notifications')
  Future<Map<String, Object?>> inbox(
    NotificationService notifications,
    RequestContext ctx,
    bool? unreadOnly,
    int? limit,
    int? offset,
  ) async {
    final user = currentUser(ctx);
    final page = await notifications.listInbox(
      user.id!,
      unreadOnly: unreadOnly ?? false,
      limit: limit ?? 50,
      offset: offset ?? 0,
    );
    return <String, Object?>{
      'results': page.items.map((n) => n.toJson()).toList(),
      'count': page.count,
    };
  }

  @Get('/inbox/unread-count', summary: 'Unread notification count for the bell badge')
  Future<Map<String, Object?>> unreadCount(
    NotificationService notifications,
    RequestContext ctx,
  ) async {
    final user = currentUser(ctx);
    final count = await notifications.unreadCount(user.id!);
    return <String, Object?>{'count': count};
  }

  @Post('/inbox/{id}/read', summary: 'Mark a notification as read')
  Future<Map<String, Object?>> markRead(
    int id,
    NotificationService notifications,
    RequestContext ctx,
  ) async {
    final user = currentUser(ctx);
    await notifications.markRead(user.id!, id);
    return <String, Object?>{'detail': 'Marked as read.'};
  }

  @Post('/inbox/read-all', summary: 'Mark every notification as read')
  Future<Map<String, Object?>> markAllRead(
    NotificationService notifications,
    RequestContext ctx,
  ) async {
    final user = currentUser(ctx);
    await notifications.markAllRead(user.id!);
    return <String, Object?>{'detail': 'All notifications marked as read.'};
  }

  // ── Shared access checks ─────────────────────────────────────────────

  /// Read access: any team member may view their app's rules/events;
  /// everything else (system-wide, database-scoped, or an unfiltered list)
  /// is superuser-only.
  Future<void> _requireReadAccess(
    RequestContext ctx,
    AppsService apps, {
    String? scope,
    int? appId,
  }) async {
    if ((scope == 'app' || scope == null) && appId != null) {
      await apps.requireAppRole(currentUser(ctx), appId, TeamRole.viewer);
      return;
    }
    requireSuperuser(ctx);
  }

  /// Write access: creating/editing/deleting an app-scoped rule requires the
  /// same "developer" bar as editing the app's own resource quota
  /// (`AppsApi.update`); every other scope is superuser-only.
  Future<void> _requireWriteAccess(
    RequestContext ctx,
    AppsService apps, {
    required String? scope,
    int? appId,
  }) async {
    if (scope == 'app') {
      if (appId == null) throw HttpException(422, 'appId is required for app-scoped rules.');
      await apps.requireAppRole(currentUser(ctx), appId, TeamRole.developer);
      return;
    }
    requireSuperuser(ctx);
  }
}
