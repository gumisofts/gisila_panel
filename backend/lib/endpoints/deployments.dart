import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/authz/authz.dart' show TeamRole;
import 'package:gisila_panel/forms/deployment_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';
import 'package:gisila_panel/services/artifact_store.dart';
import 'package:gisila_panel/services/deployments_service.dart';

part 'deployments.g.dart';

@Controller('/apps/{appId}/deployments', ['Deployments'])
@RequireAuth()
class DeploymentsApi {
  @Get('/', summary: 'List an app\'s deployments')
  Future<Map<String, Object?>> list(
    int appId,
    DeploymentsService deployments,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final app = await apps.findForUser(user, appId);
    final result = await deployments.list(user, appId);
    final rollbackable = DeploymentsService.rollbackable(app, result);
    return <String, Object?>{
      'results': [
        for (final d in result)
          DeploymentsService.toPublicJson(d,
              canRollback: rollbackable.contains(d.id)),
      ],
    };
  }

  @Post('/', summary: 'Trigger a new deployment')
  Future<Map<String, Object?>> trigger(
    int appId,
    TriggerDeploymentForm form,
    DeploymentsService deployments,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final deployment = await deployments.trigger(
      user,
      appId,
      sourceType: form.sourceType.value!,
      gitCommitSha: form.gitCommitSha.value,
      artifactId: form.artifactId.value,
      forceRebuild: form.forceRebuild.value ?? false,
    );
    return DeploymentsService.toPublicJson(deployment);
  }

  /// The file is the raw request body (`Content-Type:
  /// application/octet-stream`): an executable for a `binary` app, a ZIP of
  /// the source for a `zip` app. Pass the returned `artifactId` to
  /// `POST /apps/{appId}/deployments/` to deploy it.
  @Post('/artifacts', summary: 'Upload a binary or ZIP to deploy')
  Future<Map<String, Object?>> uploadArtifact(
    int appId,
    AppsService apps,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    // An upload only exists to be deployed, so it takes the deploy role.
    final app = await apps.requireAppRole(user, appId, TeamRole.developer);
    final id = await ArtifactStore()
        .save(app.id!, app.sourceType, ctx.request.read());
    return <String, Object?>{'artifactId': id};
  }

  @Post('/{id}/rollback', summary: 'Roll back to this deployment')
  Future<Map<String, Object?>> rollback(
    int appId,
    int id,
    DeploymentsService deployments,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final rb = await deployments.rollback(user, appId, id);
    return DeploymentsService.toPublicJson(rb);
  }

  @Get('/{id}/logs', summary: 'Build logs for a deployment')
  Future<Map<String, Object?>> logs(
    int appId,
    int id,
    DeploymentsService deployments,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final logs = await deployments.buildLogs(user, appId, id);
    return <String, Object?>{
      'results': logs.map((l) => l.toJson()).toList(),
    };
  }
}
