import 'dart:math';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';
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

  /// Create a new [App] record. The Linux user, port, work dir, etc.
  /// are reserved here but provisioned by the agent during the first
  /// deployment.
  Future<App> create(
    User actor, {
    required int projectId,
    required String name,
    required String runtime,
    required String sourceType,
    String? gitUrl,
    String? gitBranch,
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
    // SSH deploy key (for git source)
    int? deployKeyId,
  }) async {
    final projectsSvc = ProjectsService()..attach(ctx);
    await projectsSvc.findForUser(actor, projectId);

    final slug = Slug.make(name);
    final shortId = _randomId(6);
    final linuxUser = 'app_$shortId';
    final workDir = '${hostConfig.appsRoot}/$linuxUser';
    final port = await _allocatePort();
    final now = DateTime.now().toUtc();

    final created =
        await Query<App>(AppTable.metadata).insert(<String, Object?>{
      'projectId': projectId,
      'name': name,
      'slug': slug,
      'linuxUser': linuxUser,
      'workDir': workDir,
      'internalPort': port,
      'runtime': runtime,
      'sourceType': sourceType,
      'gitUrl': gitUrl,
      'gitBranch': gitBranch,
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
      if (deployKeyId != null) 'deployKeyId': deployKeyId,
      'status': 'created',
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await _logEvent(created.id!, actor, 'create',
        message: 'App created (port $port, user $linuxUser).');
    return created;
  }

  Future<App> update(
    User actor,
    int appId,
    Map<String, Object?> patch,
  ) async {
    final app = await findForUser(actor, appId);
    if (patch.isEmpty) {
      throw BadRequest('No updatable fields provided.');
    }
    patch['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    final rows = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(app.id!))
        .update(patch)
        .run(_db.context());
    return rows.first;
  }

  Future<void> delete(User actor, int appId) async {
    final app = await findForUser(actor, appId);
    // The actual systemd / nginx / user teardown is performed by the worker.
    await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(app.id!))
        .delete()
        .run(_db.context());
  }

  Future<int> _allocatePort() async {
    final taken = await Query<App>(AppTable.metadata).all(_db.context());
    final used = taken.map((a) => a.internalPort).whereType<int>().toSet();
    for (var p = hostConfig.portMin; p <= hostConfig.portMax; p++) {
      if (!used.contains(p)) return p;
    }
    throw Conflict(
      'No internal ports left in range ${hostConfig.portMin}-${hostConfig.portMax}.',
      code: 'no_ports_available',
    );
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
