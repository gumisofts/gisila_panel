import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/forms/project_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/projects_service.dart';

part 'projects.g.dart';

@Controller('/projects', ['Projects'])
@RequireAuth()
class ProjectsApi {
  @Get('/', summary: 'List projects across all my teams')
  Future<Map<String, Object?>> list(
    ProjectsService projects,
    RequestContext ctx,
    int? teamId,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await projects.listForUser(user, teamId: teamId);
    return <String, Object?>{
      'results': result.map((p) => p.toJson()).toList(),
    };
  }

  @Post('/', summary: 'Create a project')
  Future<Map<String, Object?>> create(
    CreateProjectForm form,
    ProjectsService projects,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final project = await projects.create(
      user,
      teamId: form.teamId.value!,
      name: form.name.value!,
      description: form.description.value,
    );
    return project.toJson();
  }

  @Get('/{id}', summary: 'Get a project')
  Future<Map<String, Object?>> retrieve(
    int id,
    ProjectsService projects,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final project = await projects.findForUser(user, id);
    return project.toJson();
  }

  @Patch('/{id}', summary: 'Update a project')
  Future<Map<String, Object?>> update(
    int id,
    UpdateProjectForm form,
    ProjectsService projects,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final project = await projects.update(
      user,
      id,
      name: form.name.value,
      description: form.description.value,
    );
    return project.toJson();
  }

  @Delete('/{id}', summary: 'Delete a project')
  Future<Map<String, Object?>> delete(
    int id,
    ProjectsService projects,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await projects.delete(user, id);
    return <String, Object?>{'detail': 'Project deleted.'};
  }
}
