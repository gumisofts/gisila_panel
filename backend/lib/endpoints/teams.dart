import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/forms/team_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/teams_service.dart';

part 'teams.g.dart';

@Controller('/teams', ['Teams'])
@RequireAuth()
class TeamsApi {
  @Get('/', summary: 'List my teams')
  Future<Map<String, Object?>> list(
    TeamsService teams,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await teams.listForUser(user);
    final roles = await teams.membershipRoles(user);
    return <String, Object?>{
      'results': result.map((t) {
        final json = t.toJson();
        // Surface the caller's role so the UI can hide actions they can't perform.
        json['myRole'] = user.isSuperuser == true
            ? 'owner'
            : (roles[t.id] ?? 'viewer');
        return json;
      }).toList(),
    };
  }

  @Post('/', summary: 'Create a team')
  Future<Map<String, Object?>> create(
    CreateTeamForm form,
    TeamsService teams,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final team = await teams.create(
      user,
      name: form.name.value!,
      slug: form.slug.value,
    );
    return team.toJson();
  }

  @Get('/{id}', summary: 'Get a team')
  Future<Map<String, Object?>> retrieve(
    int id,
    TeamsService teams,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final team = await teams.findForUser(user, id);
    return team.toJson();
  }

  @Delete('/{id}', summary: 'Delete a team and all of its projects and apps')
  Future<Map<String, Object?>> delete(
    int id,
    TeamsService teams,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await teams.delete(user, id);
    return <String, Object?>{'detail': 'Team removal requested.'};
  }

  @Get('/{id}/quota', summary: "A team's resource quota and usage")
  Future<Map<String, Object?>> quota(
    int id,
    TeamsService teams,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    return (await teams.quota(user, id)).toJson();
  }

  @Put('/{id}/quota', summary: "Set a team's resource quota (superuser)")
  Future<Map<String, Object?>> setQuota(
    int id,
    TeamQuotaForm form,
    TeamsService teams,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final quota = await teams.setQuota(user, id,
        maxApps: form.maxApps.value,
        maxMemoryMb: form.maxMemoryMb.value,
        maxCpuPercent: form.maxCpuPercent.value);
    return quota.toJson();
  }

  @Get('/{id}/members', summary: 'List team members')
  Future<Map<String, Object?>> members(
    int id,
    TeamsService teams,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await teams.findForUser(user, id);
    final result = await teams.members(id);
    return <String, Object?>{
      'results': result.map((m) => m.toJson()).toList(),
    };
  }

  @Post('/{id}/invitations', summary: 'Invite a user to the team')
  Future<Map<String, Object?>> invite(
    int id,
    InviteMemberForm form,
    TeamsService teams,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final team = await teams.findForUser(user, id);
    final member = await teams.invite(
      user,
      team,
      email: form.email.value!,
      role: form.role.value ?? 'developer',
    );
    return member.toJson();
  }
}
