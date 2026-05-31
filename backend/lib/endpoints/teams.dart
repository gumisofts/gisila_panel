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
    return <String, Object?>{
      'results': result.map((t) => t.toJson()).toList(),
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
      team,
      email: form.email.value!,
      role: form.role.value ?? 'developer',
    );
    return member.toJson();
  }
}
