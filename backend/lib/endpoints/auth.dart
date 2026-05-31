import 'dart:async';

import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/forms/auth_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/auth_service.dart';

part 'auth.g.dart';

@Controller('/auth', ['Auth'])
class AuthApi {
  @Post(
    '/register',
    summary: 'Register a new account',
    config: RouteConfig(
      rateLimit: RateLimitConfig(requestsPerMinute: 20),
    ),
  )
  @Public()
  Future<Map<String, Object?>> register(
    RegisterForm form,
    AuthService auth,
  ) async {
    final result = await auth.register(
      email: form.email.value!,
      password: form.password.value!,
      firstName: form.firstName.value,
      lastName: form.lastName.value,
    );
    return <String, Object?>{
      'user': result.user.toJson(exclude: ['password']),
      'access': result.accessToken,
      'team': result.team.toJson(),
    };
  }

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
}
