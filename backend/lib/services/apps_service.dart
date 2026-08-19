import 'dart:convert';
import 'dart:math';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/application_service.dart';
import 'package:gisila_panel/services/projects_service.dart';
import 'package:gisila_panel/utils/slugs.dart';

/// Network exposure modes an [App] can pick at creation time. See the
/// `expose_mode` column doc in `schema.gisila.yaml` for the full rationale.
const kExposeModes = <String>{'web', 'tcp', 'internal'};

/// Runtimes where a `tcp` app must supply its own start command.
///
/// With no start command the agent derives one, but for these runtimes every
/// available derivation assumes HTTP — gunicorn for python, the detected web
/// framework (Next/Nuxt/`npm start`/…) for node and bun — or doesn't exist at
/// all: a rust build leaves its binary at a crate-specific
/// `target/release/<name>` path rather than the conventional
/// `<workDir>/current/app`. A tcp app speaks its own protocol, so silently
/// starting an HTTP server for it would be wrong; ask up front instead of
/// failing at deploy time. Compiled runtimes (go, dart, zig, binary uploads)
/// are absent on purpose: their default is the built artifact at
/// `<workDir>/current/app`, which is protocol-agnostic and correct here.
const kTcpRuntimesNeedingStartCommand = <String>{
  'python',
  'node',
  'bun',
  'rust',
};

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
    // web (default) | tcp | internal — see kExposeModes. Immutable after
    // creation; forced to 'web' for runtime = static below.
    String? exposeMode,
    // Only meaningful when exposeMode = tcp. Whether the agent should open
    // the host firewall for `port`. Defaults to true for tcp apps (that's
    // the point of picking tcp exposure) and is ignored otherwise.
    bool? publiclyReachable,
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

    // Static sites are always Nginx-served — there is no process to bind a
    // port, so 'tcp'/'internal' exposure (which are about how a *process*
    // reaches the network) is meaningless for them.
    final resolvedExposeMode = isStatic ? 'web' : (exposeMode ?? 'web');
    if (!kExposeModes.contains(resolvedExposeMode)) {
      throw BadRequest(
          'Invalid exposeMode "$resolvedExposeMode". Must be one of: '
          '${kExposeModes.join(', ')}.');
    }
    if (isStatic && exposeMode != null && exposeMode != 'web') {
      throw BadRequest('Static sites only support exposeMode "web".');
    }
    if (resolvedExposeMode == 'tcp' &&
        kTcpRuntimesNeedingStartCommand.contains(runtime) &&
        (startCommand == null || startCommand.trim().isEmpty)) {
      throw BadRequest(
        'A start command is required for a "tcp" app on runtime "$runtime". '
        'Without one the deploy would fall back to starting an HTTP server '
        '(gunicorn / the detected web framework), which is not what a raw TCP '
        'service runs.',
      );
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
      'exposeMode': resolvedExposeMode,
      'publiclyReachable': resolvedExposeMode == 'tcp'
          ? (publiclyReachable ?? true)
          : false,
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
            '(${port != null ? 'port $port, ' : ''}'
            'exposure $resolvedExposeMode, user $linuxUser).');
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
    // exposeMode is set once at creation — switching a live app between
    // nginx-vhost wiring and firewall wiring is a teardown/rebuild operation,
    // not a simple field edit. Use setNetworkExposure to flip the
    // publiclyReachable toggle on an existing 'tcp' app instead.
    if (patch.containsKey('exposeMode')) {
      throw BadRequest('exposeMode cannot be changed after creation.');
    }
    if (patch.containsKey('internalPort') && patch['internalPort'] != null) {
      await _validatePort(patch['internalPort'] as int, excludeAppId: app.id);
    }
    // Same reasoning as at creation: clearing the start command of a tcp app
    // on one of these runtimes would silently hand the next deploy back to an
    // HTTP default that doesn't fit it.
    if (patch.containsKey('startCommand') &&
        app.exposeMode == 'tcp' &&
        kTcpRuntimesNeedingStartCommand.contains(app.runtime) &&
        (patch['startCommand'] as String? ?? '').trim().isEmpty) {
      throw BadRequest(
        'A start command is required for a "tcp" app on runtime '
        '"${app.runtime}" — it has no HTTP-free default to fall back to.',
      );
    }
    patch['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    final rows = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(app.id!))
        .update(patch)
        .run(_db.context());
    return rows.first;
  }

  /// Toggle whether a `tcp`-exposed app's port is opened on the host
  /// firewall. Mirrors `PostgresService.setPublicExposure` — patches the row
  /// then enqueues a worker job that reconciles `ufw` without a full
  /// redeploy. No-op on the DB side if the value is unchanged, but the job is
  /// still enqueued so a previously-failed firewall reconcile can be retried
  /// by re-submitting the same value.
  Future<App> setNetworkExposure(
    User actor,
    int appId, {
    required bool publiclyReachable,
  }) async {
    final app = await requireAppRole(actor, appId, TeamRole.developer);
    if (app.exposeMode != 'tcp') {
      throw BadRequest(
          'Network exposure only applies to apps with exposeMode "tcp".');
    }
    if (app.internalPort == null) {
      throw BadRequest('App has no internal port to expose.');
    }
    await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(app.id!))
        .update(<String, Object?>{
      'publiclyReachable': publiclyReachable,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }).run(_db.context());

    await RedisClient.instance.rpush(
      'gisila:queue:network',
      jsonEncode(<String, Object?>{
        'appId': app.id,
        'reason': publiclyReachable ? 'expose' : 'unexpose',
      }),
    );

    await _logEvent(app.id!, actor, 'network',
        message: publiclyReachable
            ? 'Port ${app.internalPort} opened to the public internet.'
            : 'Port ${app.internalPort} closed to the public internet.');

    return findForUser(actor, appId);
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
