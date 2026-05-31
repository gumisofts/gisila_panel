import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';

part 'metrics.g.dart';

@Controller('/apps/{appId}/metrics', ['Metrics'])
@RequireAuth()
class MetricsApi {
  @Get('/', summary: 'Recent CPU / memory samples for an app')
  Future<Map<String, Object?>> recent(
    int appId,
    AppsService apps,
    RequestContext ctx,
    int? minutes,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final app = await apps.findForUser(user, appId);
    final since =
        DateTime.now().toUtc().subtract(Duration(minutes: minutes ?? 60));
    final samples = await Query<MetricSample>(MetricSampleTable.metadata)
        .where(MetricSampleTable.appId.eq(app.id!))
        .where(MetricSampleTable.sampledAt.gte(since))
        .orderBy(MetricSampleTable.sampledAt)
        .all(ctx.db<Database>().context());
    return <String, Object?>{
      'app': <String, Object?>{
        'id': app.id,
        'name': app.name,
        'status': app.status,
      },
      'samples': samples.map((s) => s.toJson()).toList(),
    };
  }
}
