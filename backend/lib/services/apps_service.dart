import 'dart:math';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/application_service.dart';
import 'package:gisila_panel/services/projects_service.dart';
import 'package:gisila_panel/utils/slugs.dart';

/// CRUD + lifecycle helpers for [App] records.
///
/// This service only manipulates the database. The actual host-side
/// provisioning (creating the Linux user, the systemd unit, the AppArmor
/// profile and the Nginx vhost) is performed by the background worker via
/// the privileged `gisila-agent`.
class AppsService extends Service {
  static final _rng = Random.secure();
  Database get _db => db<Database>();

  Future<List<App>> listForUser(User user, {int? projectId}) async {
    // Platform superusers bypass team membership for list reads — same
    // privilege model as [requireTeamRole]. Without this, Application
    // Management UI that filters `/apps/` client-side by `applicationId`
    // stays empty for the operator even when apps in other teams pin the
    // runtime (and correctly 409 version removals via a direct DB query).
    if (user.isSuperuser == true) {
      var q = Query<App>(AppTable.metadata);
      if (projectId != null) q = q.where(AppTable.projectId.eq(projectId));
      return q.all(_db.context());
    }

    final projectsSvc = ProjectsService()..attach(ctx);
    final projects = await projectsSvc.listForUser(user);
    final projectIds = projects.map((p) => p.id).whereType<int>().toList();
    if (projectIds.isEmpty) return <App>[];

    var q = Query<App>(AppTable.metadata)
        .where(AppTable.projectId.inList(projectIds));
    if (projectId != null) q = q.where(AppTable.projectId.eq(projectId));
    return q.all(_db.context());
  }

  Future<App> findForUser(User user, int appId) async {
    final app = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(appId))
        .first(_db.context());
    if (app == null) throw NotFound('App not found.');
    final projectsSvc = ProjectsService()..attach(ctx);
    await projectsSvc.findForUser(user, app.projectId);
    return app;
  }

  /// Like [findForUser] but also enforces that the caller holds at least the
  /// [min] role in the app's owning team. Returns the app on success. Used by
  /// every mutating app operation (deploy, lifecycle, env, domains, …).
  Future<App> requireAppRole(User user, int appId, TeamRole min) async {
    final app = await findForUser(user, appId); // membership (read) gate first
    final project = await Query<Project>(ProjectTable.metadata)
        .where(ProjectTable.id.eq(app.projectId))
        .first(_db.context());
    if (project == null) throw NotFound('App not found.');
    await requireTeamRole(_db, user, project.teamId, min);
    return app;
  }

  /// Create a new [App] record. The Linux user, work dir, etc.
  /// are reserved here but provisioned by the agent during the first
  /// deployment. [port] must be unique across all apps.
  Future<App> create(
    User actor, {
    required int projectId,
    required String name,
    // Preferred: the id of an installed [Application]. `runtime` remains a
    // deprecated free-text alias, resolved to the matching Application by
    // key, for backward compatibility with older API clients.
    int? applicationId,
    String? runtime,
    // build_execute | direct_run | static_publish — must be one of the
    // resolved Application's deployModes; defaults to its defaultDeployMode.
    String? deploymentMode,
    required String sourceType,
    // Static sites are served directly by Nginx and have no listening port.
    // Required for every other (service) runtime.
    int? port,
    String? gitUrl,
    String? gitBranch,
    // Optional subdirectory within the repo to build/run from, so a single
    // monorepo can be deployed by pointing at just one of its projects.
    String? sourceSubdir,
    String? buildCommand,
    String? startCommand,
    String? healthCheckPath,
    int? memoryMbLimit,
    int? cpuQuotaPercent,
    int? tasksLimit,
    // Python-specific
    String? pythonVersion,
    String? pythonMode,
    String? wsgiApp,
    // Gunicorn tuning (python only)
    int? gunicornWorkers,
    int? gunicornThreads,
    int? gunicornTimeout,
    String? gunicornBind,
    String? gunicornExtraArgs,
    // Runtime version pins
    String? nodeVersion,
    String? dartVersion,
    String? goVersion,
    String? rustVersion,
    String? bunVersion,
    // Celery-specific (runtime = celery)
    String? celeryApp,
    int? celeryWorkerCount,
    int? celeryConcurrency,
    String? celeryQueues,
    bool? celeryBeatEnabled,
    String? celeryExtraArgs,
    // Static site (runtime = static)
    String? staticRoot,
    bool? staticSpa,
    // Local disk media (Model A)
    bool? mediaEnabled,
    int? mediaMaxUploadMb,
    // SSH deploy key (for git source)
    int? deployKeyId,
  }) async {
    final projectsSvc = ProjectsService()..attach(ctx);
    final project = await projectsSvc.findForUser(actor, projectId);
    // Creating an app is a developer-level action.
    await requireTeamRole(_db, actor, project.teamId, TeamRole.developer);

    // Resolve the Application: prefer the explicit applicationId, falling
    // back to the deprecated free-text `runtime` alias so older API clients
    // keep working unchanged.
    final applicationsSvc = ApplicationService()..attach(ctx);
    final application = applicationId != null
        ? await applicationsSvc.findById(applicationId)
        : (runtime != null ? await applicationsSvc.findByKey(runtime) : null);
    if (application == null) {
      throw BadRequest('Either a valid applicationId or runtime is required.');
    }
    if (application.status != 'installed') {
      throw BadRequest(
          '${application.displayName} is not installed on this host '
          '(status: ${application.status}). Install it from Application '
          'Management first.');
    }
    runtime = application.key!;
    final supportedModes = application.deployModes.split(',');
    if (deploymentMode != null && !supportedModes.contains(deploymentMode)) {
      throw BadRequest('${application.displayName} does not support deploy '
          'mode "$deploymentMode".');
    }
    deploymentMode ??= application.defaultDeployMode;

    // Static apps carry no port; every service runtime needs a unique one.
    final isStatic = runtime == 'static';
    if (isStatic) {
      port = null;
    } else {
      if (port == null) {
        throw BadRequest('An internal port is required for runtime "$runtime".');
      }
      await _validatePort(port);
    }

    final slug = Slug.make(name);
    final shortId = _randomId(6);
    final linuxUser = 'app_$shortId';
    final workDir = '${hostConfig.appsRoot}/$linuxUser';
    final now = DateTime.now().toUtc();

    final created =
        await Query<App>(AppTable.metadata).insert(<String, Object?>{
      'projectId': projectId,
      'name': name,
      'slug': slug,
      'linuxUser': linuxUser,
      'workDir': workDir,
      'internalPort': port,
      'applicationId': application.id,
      'deploymentMode': deploymentMode,
      'runtime': runtime,
      'sourceType': sourceType,
      'gitUrl': gitUrl,
      'gitBranch': gitBranch,
      if (sourceSubdir != null) 'sourceSubdir': sourceSubdir,
      'buildCommand': buildCommand,
      'startCommand': startCommand,
      'healthCheckPath': healthCheckPath,
      'memoryMbLimit': memoryMbLimit ?? 256,
      'cpuQuotaPercent': cpuQuotaPercent ?? 50,
      'tasksLimit': tasksLimit ?? 100,
      if (pythonVersion != null) 'pythonVersion': pythonVersion,
      if (pythonMode != null) 'pythonMode': pythonMode,
      if (wsgiApp != null) 'wsgiApp': wsgiApp,
      if (gunicornWorkers != null) 'gunicornWorkers': gunicornWorkers,
      if (gunicornThreads != null) 'gunicornThreads': gunicornThreads,
      if (gunicornTimeout != null) 'gunicornTimeout': gunicornTimeout,
      if (gunicornBind != null) 'gunicornBind': gunicornBind,
      if (gunicornExtraArgs != null) 'gunicornExtraArgs': gunicornExtraArgs,
      if (nodeVersion != null) 'nodeVersion': nodeVersion,
      if (dartVersion != null) 'dartVersion': dartVersion,
      if (goVersion != null) 'goVersion': goVersion,
      if (rustVersion != null) 'rustVersion': rustVersion,
      if (bunVersion != null) 'bunVersion': bunVersion,
      if (celeryApp != null) 'celeryApp': celeryApp,
      if (celeryWorkerCount != null) 'celeryWorkerCount': celeryWorkerCount,
      if (celeryConcurrency != null) 'celeryConcurrency': celeryConcurrency,
      if (celeryQueues != null) 'celeryQueues': celeryQueues,
      if (celeryBeatEnabled != null) 'celeryBeatEnabled': celeryBeatEnabled,
      if (celeryExtraArgs != null) 'celeryExtraArgs': celeryExtraArgs,
      if (staticRoot != null) 'staticRoot': staticRoot,
      if (staticSpa != null) 'staticSpa': staticSpa,
      if (mediaEnabled != null) 'mediaEnabled': mediaEnabled,
      if (mediaMaxUploadMb != null) 'mediaMaxUploadMb': mediaMaxUploadMb,
      if (deployKeyId != null) 'deployKeyId': deployKeyId,
      'status': 'created',
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await _logEvent(created.id!, actor, 'create',
        message: 'App created '
            '(${port != null ? 'port $port, ' : ''}user $linuxUser).');
    return created;
  }

  Future<App> update(
    User actor,
    int appId,
    Map<String, Object?> patch,
  ) async {
    // Editing app settings is a developer-level action.
    final app = await requireAppRole(actor, appId, TeamRole.developer);
    if (patch.isEmpty) {
      throw BadRequest('No updatable fields provided.');
    }
    if (patch.containsKey('internalPort') && patch['internalPort'] != null) {
      await _validatePort(patch['internalPort'] as int, excludeAppId: app.id);
    }
    patch['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    final rows = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(app.id!))
        .update(patch)
        .run(_db.context());
    return rows.first;
  }

  Future<void> _validatePort(int port, {int? excludeAppId}) async {
    if (port < 1024 || port > 65535) {
      throw BadRequest('Port must be between 1024 and 65535.');
    }
    final taken = await Query<App>(AppTable.metadata).all(_db.context());
    final used = taken
        .where((a) => a.id != excludeAppId)
        .map((a) => a.internalPort)
        .whereType<int>()
        .toSet();
    if (used.contains(port)) {
      throw Conflict(
        'Port $port is already in use by another app.',
        code: 'port_in_use',
      );
    }
  }

  String _randomId(int chars) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      Iterable.generate(
        chars,
        (_) => alphabet.codeUnitAt(_rng.nextInt(alphabet.length)),
      ),
    );
  }

  Future<void> _logEvent(
    int appId,
    User actor,
    String kind, {
    String? message,
  }) async {
    await Query<AppEvent>(AppEventTable.metadata).insert(<String, Object?>{
      'appId': appId,
      'actorId': actor.id,
      'kind': kind,
      'message': message,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).run(_db.context());
  }
}
