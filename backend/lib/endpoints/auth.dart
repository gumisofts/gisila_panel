import 'dart:async';

import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/forms/auth_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/auth_service.dart';

part 'auth.g.dart';

@Controller('/auth', ['Auth'])
class AuthApi {
  // ── Login ──────────────────────────────────────────────────────────────────

  @Post(
    '/login',
    summary: 'Sign in with email + password',
    config: RouteConfig(
      rateLimit: RateLimitConfig(requestsPerMinute: 60),
    ),
  )
  @Public()
  Future<Map<String, Object?>> login(LoginForm form, AuthService auth) async {
    final result = await auth.login(
      email: form.email.value!,
      password: form.password.value!,
    );
    return <String, Object?>{
      'user': result.user.toJson(exclude: ['password']),
      'access': result.accessToken,
    };
  }

  // ── Current user ───────────────────────────────────────────────────────────

  @Get('/me', summary: 'Get the authenticated user profile')
  @RequireAuth()
  Future<Map<String, Object?>> me(RequestContext ctx) async {
    final user = ctx.principal!.claims['user'] as User;
    return user.toJson(exclude: ['password']);
  }

  @Post('/change-password', summary: 'Change password')
  @RequireAuth()
  Future<Map<String, Object?>> changePassword(
    ChangePasswordForm form,
    AuthService auth,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await auth.changePassword(
      user,
      oldPassword: form.oldPassword.value!,
      newPassword: form.newPassword.value!,
    );
    return <String, Object?>{'detail': 'Password changed successfully.'};
  }

  // ── User management (superuser only) ───────────────────────────────────────

  @Get('/users', summary: 'List all user accounts (superuser only)')
  @RequireAuth()
  Future<Map<String, Object?>> listUsers(
    AuthService auth,
    RequestContext ctx,
  ) async {
    _requireSuperuser(ctx);
    final users = await auth.listUsers();
    return <String, Object?>{
      'results': users.map((u) => u.toJson(exclude: ['password'])).toList(),
      'count': users.length,
    };
  }

  @Post('/users', summary: 'Create a new user account (superuser only)')
  @RequireAuth()
  Future<Map<String, Object?>> createUser(
    CreateUserForm form,
    AuthService auth,
    RequestContext ctx,
  ) async {
    _requireSuperuser(ctx);
    final result = await auth.createUser(
      email: form.email.value!,
      password: form.password.value!,
      firstName: form.firstName.value,
      lastName: form.lastName.value,
      isSuperuser: form.isSuperuser.value ?? false,
    );
    return <String, Object?>{
      'user': result.user.toJson(exclude: ['password']),
      'team': result.team.toJson(),
    };
  }

  @Patch(
    '/users/{id}',
    summary: 'Update a user account (superuser only)',
  )
  @RequireAuth()
  Future<Map<String, Object?>> updateUser(
    int id,
    UpdateUserForm form,
    AuthService auth,
    RequestContext ctx,
  ) async {
    _requireSuperuser(ctx);
    final actor = ctx.principal!.claims['user'] as User;
    if (actor.id == id && form.isSuperuser.value == false) {
      throw BadRequest(
        'You cannot remove your own superuser status.',
        code: 'cannot_demote_self',
      );
    }
    final updated = await auth.updateUser(
      id,
      firstName: form.firstName.value,
      lastName: form.lastName.value,
      isActive: form.isActive.value,
      isSuperuser: form.isSuperuser.value,
    );
    return updated.toJson(exclude: ['password']);
  }

  @Delete('/users/{id}', summary: 'Delete a user account (superuser only)')
  @RequireAuth()
  Future<Map<String, Object?>> deleteUser(
    int id,
    AuthService auth,
    RequestContext ctx,
  ) async {
    _requireSuperuser(ctx);
    final actor = ctx.principal!.claims['user'] as User;
    if (actor.id == id) {
      throw BadRequest(
        'You cannot delete your own account.',
        code: 'cannot_delete_self',
      );
    }
    await auth.deleteUser(id);
    return <String, Object?>{'detail': 'User deleted.'};
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

void _requireSuperuser(RequestContext ctx) {
  final user = ctx.principal!.claims['user'] as User;
  if (user.isSuperuser != true) {
    throw Forbidden(
      'Superuser access required.',
    );
  }
}
