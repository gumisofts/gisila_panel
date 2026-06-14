import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/audit_service.dart';

part 'audit.g.dart';

@Controller('/audit', ['Activity'])
@RequireAuth()
class AuditApi {
  @Get('/', summary: 'List my recent activity')
  Future<Map<String, Object?>> list(
    AuditService audit,
    RequestContext ctx,
    int? limit,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await audit.listForActor(user, limit: limit ?? 100);
    return <String, Object?>{
      'results': result.map((a) => a.toJson()).toList(),
    };
  }
}
