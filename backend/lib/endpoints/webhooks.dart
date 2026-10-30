import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/forms/webhook_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/webhooks_service.dart';

part 'webhooks.g.dart';

/// Managing an app's push-to-deploy webhook.
@Controller('/apps/{appId}/webhook', ['Webhooks'])
@RequireAuth()
class AppWebhookApi {
  @Get('/', summary: 'Push-to-deploy webhook status')
  Future<Map<String, Object?>> status(
    int appId,
    WebhooksService hooks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    return hooks.status(user, appId);
  }

  /// Returns the secret to paste into the repository's webhook settings.
  /// Calling it again rotates the secret; the old one stops working.
  @Post('/', summary: 'Create the webhook or rotate its secret')
  Future<Map<String, Object?>> enable(
    int appId,
    WebhooksService hooks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    return hooks.enable(user, appId);
  }

  @Delete('/', summary: 'Remove the webhook')
  Future<Map<String, Object?>> disable(
    int appId,
    WebhooksService hooks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await hooks.disable(user, appId);
    return <String, Object?>{'detail': 'Webhook removed.'};
  }

  /// A token the panel uses to report deploy status on each pushed commit.
  /// It is stored encrypted and never returned.
  @Put('/status-token', summary: 'Set the token for commit statuses')
  Future<Map<String, Object?>> setStatusToken(
    int appId,
    StatusTokenForm form,
    WebhooksService hooks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await hooks.setStatusToken(user, appId, form.token.value);
    return <String, Object?>{'detail': 'Commit statuses will be reported.'};
  }

  @Delete('/status-token', summary: 'Stop reporting commit statuses')
  Future<Map<String, Object?>> clearStatusToken(
    int appId,
    WebhooksService hooks,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await hooks.setStatusToken(user, appId, null);
    return <String, Object?>{'detail': 'Commit statuses are off.'};
  }
}

/// Where GitHub, Gitea / Forgejo and GitLab send pushes. Not behind panel
/// login: the signature made with the app's webhook secret is the check.
@Controller('/webhooks', ['Webhooks'])
class WebhookDeliveryApi {
  @Post(
    '/apps/{appId}',
    summary: 'Receive a push and deploy it',
    config: RouteConfig(
      rateLimit: RateLimitConfig(requestsPerMinute: 120),
      maxBodyBytes: 5 * 1024 * 1024,
    ),
  )
  @Public()
  Future<Response> deliver(
    int appId,
    Request request,
    WebhooksService hooks,
  ) async {
    final body = <int>[];
    await for (final chunk in request.read()) {
      body.addAll(chunk);
    }
    final outcome = await hooks.deliver(appId, request.headers, body);
    return jsonResponse(body: outcome.toJson(), statusCode: outcome.statusCode);
  }
}
