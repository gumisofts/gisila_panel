import 'dart:convert';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';

class DeploymentsService extends Service {
  Database get _db => db<Database>();

  Future<List<Deployment>> list(User actor, int appId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.findForUser(actor, appId);
    return Query<Deployment>(DeploymentTable.metadata)
        .where(DeploymentTable.appId.eq(app.id!))
        .orderBy(DeploymentTable.id, desc: true)
        .all(_db.context());
  }

  /// API shape of a deployment. `deployConfig` carries the env snapshot —
  /// secret values included — so it never leaves the server; callers get
  /// whether a rollback is possible instead.
  static Map<String, Object?> toPublicJson(Deployment d,
          {bool canRollback = false}) =>
      d.toJson()
        ..remove('deployConfig')
        ..['canRollback'] = canRollback;

  /// Ids of the deployments in [newestFirst] that can still be rolled back to:
  /// successful, with a recorded release + config, not the live one, and among
  /// the releases the worker keeps on disk (the live release plus the newest
  /// `releasesToKeep` before it — see DeploymentWorker._releasesToRetain).
  static Set<int> rollbackable(App app, List<Deployment> newestFirst) {
    final keep = (app.releasesToKeep ?? 5).clamp(1, 50);
    final retained = <String>{};
    final out = <int>{};
    for (final d in newestFirst) {
      if (d.status != 'succeeded' ||
          d.releaseId == null ||
          d.deployConfig == null) {
        continue;
      }
      if (!retained.contains(d.releaseId) && retained.length > keep) break;
      retained.add(d.releaseId!);
      if (d.isActive != true) out.add(d.id!);
    }
    return out;
  }

  /// Create a deployment record, mark it as `queued`, then enqueue a job for
  /// the worker. The worker is responsible for actually building / shipping
  /// the artifact through `gisila-agent`.
  Future<Deployment> trigger(
    User actor,
    int appId, {
    required String sourceType,
    String? gitCommitSha,
    String? artifactPath,
    bool forceRebuild = false,
  }) async {
    final appsSvc = AppsService()..attach(ctx);
    // Deploying is a developer-level action.
    final app = await appsSvc.requireAppRole(actor, appId, TeamRole.developer);

    final now = DateTime.now().toUtc();
    final deployment = await Query<Deployment>(DeploymentTable.metadata)
        .insert(<String, Object?>{
      'appId': app.id,
      'triggeredById': actor.id,
      'sourceType': sourceType,
      'gitCommitSha': gitCommitSha,
      'artifactPath': artifactPath,
      'status': 'queued',
      'isActive': false,
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(app.id!))
        .update(<String, Object?>{'status': 'building'}).run(_db.context());

    await Query<AppEvent>(AppEventTable.metadata).insert(<String, Object?>{
      'appId': app.id,
      'actorId': actor.id,
      'kind': 'deploy',
      'message': 'Deployment #${deployment.id} queued.',
      'createdAt': now.toIso8601String(),
    }).run(_db.context());

    try {
      await RedisClient.instance.rpush(
        'gisila:queue:deployments',
        jsonEncode(<String, Object?>{
          'deploymentId': deployment.id,
          'appId': app.id,
          'sourceType': sourceType,
          'gitCommitSha': gitCommitSha,
          'artifactPath': artifactPath,
          'forceRebuild': forceRebuild,
          'queuedAt': now.toIso8601String(),
        }),
      );
    } catch (e) {
      // The row is already `queued`. If Redis never got the message the
      // worker will never see it — mark failed so the UI doesn't sit on
      // queued forever (the stuck-deployment sweeper is the other half).
      await Query<Deployment>(DeploymentTable.metadata)
          .where(DeploymentTable.id.eq(deployment.id!))
          .update(<String, Object?>{
        'status': 'failed',
        'failureReason': 'Failed to enqueue deployment: $e',
        'finishedAt': DateTime.now().toUtc().toIso8601String(),
      }).run(_db.context());
      rethrow;
    }

    return deployment;
  }

  Future<Deployment> rollback(User actor, int appId, int deploymentId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.requireAppRole(actor, appId, TeamRole.developer);

    final target = await Query<Deployment>(DeploymentTable.metadata)
        .where(DeploymentTable.id.eq(deploymentId))
        .where(DeploymentTable.appId.eq(app.id!))
        .first(_db.context());

    if (target == null) throw NotFound('Deployment not found.');
    if (target.status != 'succeeded') {
      throw BadRequest('Only successful deployments can be rolled back to.');
    }
    if (target.isActive == true) {
      throw BadRequest('Deployment #${target.id} is already live.');
    }
    if (target.releaseId == null || target.deployConfig == null) {
      throw BadRequest(
        'Deployment #${target.id} was made before deployments recorded their '
        'build and configuration, so it cannot be restored as it ran. '
        'Redeploy instead.',
      );
    }
    final history = await list(actor, appId);
    if (!rollbackable(app, history).contains(target.id)) {
      throw BadRequest(
        'The build of deployment #${target.id} is no longer kept on disk '
        '(this app keeps ${app.releasesToKeep ?? 5}). Redeploy instead.',
      );
    }

    final now = DateTime.now().toUtc();
    // The rollback is its own deployment row carrying the target's release
    // and config snapshot, so rolling back to a rollback works the same way
    // and the history shows exactly what is live.
    final rb = await Query<Deployment>(DeploymentTable.metadata)
        .insert(<String, Object?>{
      'appId': app.id,
      'triggeredById': actor.id,
      'sourceType': target.sourceType,
      'gitCommitSha': target.gitCommitSha,
      'artifactPath': target.artifactPath,
      'rollbackOfId': target.id,
      'releaseId': target.releaseId,
      'deployConfig': target.deployConfig,
      'status': 'queued',
      'isActive': false,
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await Query<AppEvent>(AppEventTable.metadata).insert(<String, Object?>{
      'appId': app.id,
      'actorId': actor.id,
      'kind': 'rollback',
      'message': 'Rollback #${rb.id} to deployment #${target.id} queued.',
      'createdAt': now.toIso8601String(),
    }).run(_db.context());

    try {
      await RedisClient.instance.rpush(
        'gisila:queue:deployments',
        jsonEncode(<String, Object?>{
          'deploymentId': rb.id,
          'appId': app.id,
          'rollback': true,
          'queuedAt': now.toIso8601String(),
        }),
      );
    } catch (e) {
      await Query<Deployment>(DeploymentTable.metadata)
          .where(DeploymentTable.id.eq(rb.id!))
          .update(<String, Object?>{
        'status': 'failed',
        'failureReason': 'Failed to enqueue rollback: $e',
        'finishedAt': DateTime.now().toUtc().toIso8601String(),
      }).run(_db.context());
      rethrow;
    }
    return rb;
  }

  Future<List<BuildLog>> buildLogs(User actor, int appId, int deploymentId,
      {int limit = 2000}) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.findForUser(actor, appId);
    // Access was checked on the app, so the deployment must be one of its own —
    // otherwise any app the caller can see would expose every other app's logs.
    final deployment = await Query<Deployment>(DeploymentTable.metadata)
        .where(DeploymentTable.id.eq(deploymentId))
        .where(DeploymentTable.appId.eq(app.id!))
        .first(_db.context());
    if (deployment == null) throw NotFound('Deployment not found.');
    // Newest-first then reverse so callers see chronological order but we keep
    // the *tail* of long builds (a plain ASC + LIMIT would drop the end).
    final newestFirst = await Query<BuildLog>(BuildLogTable.metadata)
        .where(BuildLogTable.deploymentId.eq(deploymentId))
        .orderBy(BuildLogTable.id, desc: true)
        .limit(limit)
        .all(_db.context());
    return newestFirst.reversed.toList();
  }
}
