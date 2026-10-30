import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/forms/cron_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/cron_service.dart';

part 'cron.g.dart';

/// Scheduled commands for an app. Schedules are 5-field cron expressions
/// (or `@daily`-style shortcuts) in UTC.
@Controller('/apps/{appId}/cron', ['Cron jobs'])
@RequireAuth()
class CronApi {
  @Get('/', summary: 'List cron jobs')
  Future<Map<String, Object?>> list(
    int appId,
    CronService cron,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    return <String, Object?>{'results': await cron.list(user, appId)};
  }

  /// The next run times of a schedule, to check it before saving.
  @Get('/preview', summary: 'Preview a schedule')
  Future<Map<String, Object?>> preview(int appId, {String? schedule}) async =>
      CronService.preview(schedule ?? '');

  @Post('/', summary: 'Create a cron job')
  Future<Map<String, Object?>> create(
    int appId,
    CreateCronJobForm form,
    CronService cron,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    return cron.create(
      user,
      appId,
      name: form.name.value!,
      schedule: form.schedule.value!,
      command: form.command.value!,
      timeoutSeconds: form.timeoutSeconds.value,
      enabled: form.enabled.value,
    );
  }

  @Patch('/{jobId}', summary: 'Change a cron job')
  Future<Map<String, Object?>> update(
    int appId,
    int jobId,
    UpdateCronJobForm form,
    CronService cron,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    return cron.update(
      user,
      appId,
      jobId,
      name: form.name.value,
      schedule: form.schedule.value,
      command: form.command.value,
      timeoutSeconds: form.timeoutSeconds.value,
      enabled: form.enabled.value,
    );
  }

  @Delete('/{jobId}', summary: 'Delete a cron job')
  Future<Map<String, Object?>> delete(
    int appId,
    int jobId,
    CronService cron,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await cron.delete(user, appId, jobId);
    return <String, Object?>{'detail': 'Cron job deleted.'};
  }

  /// Starts a run now. Its `execId` streams live output like a console
  /// command.
  @Post('/{jobId}/run', summary: 'Run a cron job now')
  Future<Map<String, Object?>> runNow(
    int appId,
    int jobId,
    CronService cron,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    return cron.runNow(user, appId, jobId);
  }

  @Get('/{jobId}/runs', summary: 'Recent runs of a cron job')
  Future<Map<String, Object?>> runs(
    int appId,
    int jobId,
    CronService cron,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    return <String, Object?>{'results': await cron.runs(user, appId, jobId)};
  }
}
