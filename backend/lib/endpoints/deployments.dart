import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/forms/deployment_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/deployments_service.dart';

part 'deployments.g.dart';

@Controller('/apps/{appId}/deployments', ['Deployments'])
@RequireAuth()
class DeploymentsApi {
  @Get('/', summary: 'List an app\'s deployments')
  Future<Map<String, Object?>> list(
    int appId,
    DeploymentsService deployments,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await deployments.list(user, appId);
    return <String, Object?>{
      'results': result.map((d) => d.toJson()).toList(),
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
      artifactPath: form.artifactId.value,
    );
    return deployment.toJson();
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
    return rb.toJson();
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
