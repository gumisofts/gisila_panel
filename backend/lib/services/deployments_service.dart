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

    final now = DateTime.now().toUtc();
    final rb = await Query<Deployment>(DeploymentTable.metadata)
        .insert(<String, Object?>{
      'appId': app.id,
      'triggeredById': actor.id,
      'sourceType': target.sourceType,
      'gitCommitSha': target.gitCommitSha,
      'artifactPath': target.artifactPath,
      'status': 'queued',
      'isActive': false,
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await RedisClient.instance.rpush(
      'gisila:queue:deployments',
      jsonEncode(<String, Object?>{
        'deploymentId': rb.id,
        'appId': app.id,
        'sourceType': target.sourceType,
        'artifactPath': target.artifactPath,
        'rollback': true,
        'queuedAt': now.toIso8601String(),
      }),
    );
    return rb;
  }

  Future<List<BuildLog>> buildLogs(User actor, int appId, int deploymentId,
      {int limit = 2000}) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.findForUser(actor, appId);
    assert(app.id != null);
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
