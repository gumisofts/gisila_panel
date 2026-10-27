import 'dart:async';

import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/forms/auth_forms.dart';
import 'package:gisila_panel/infra/client_ip.dart';
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
  Future<Map<String, Object?>> login(
    LoginForm form,
    AuthService auth,
    RequestContext ctx,
  ) async {
    final result = await auth.login(
      email: form.email.value!,
      password: form.password.value!,
      ip: clientIp(ctx.request),
    );
    switch (result) {
      case LoginMfaRequired(:final challenge):
        // Password was right; the session comes from POST /auth/login/mfa.
        return <String, Object?>{'mfaRequired': true, 'challenge': challenge};
      case LoginSession(:final user, :final accessToken):
        await auth.recordEvent(user.id!, 'auth.login');
        return _session(user, accessToken);
    }
  }

  @Post(
    '/login/mfa',
    summary: 'Complete a sign-in with a TOTP or recovery code',
    config: RouteConfig(
      rateLimit: RateLimitConfig(requestsPerMinute: 30),
    ),
  )
  @Public()
  Future<Map<String, Object?>> loginMfa(
    MfaLoginForm form,
    AuthService auth,
    RequestContext ctx,
  ) async {
    final result = await auth.completeMfaLogin(
      challenge: form.challenge.value!,
      code: form.code.value!,
      ip: clientIp(ctx.request),
    );
    await auth.recordEvent(result.user.id!, 'auth.login');
    return _session(result.user, result.accessToken);
  }

  // ── Current user ───────────────────────────────────────────────────────────

  @Get('/me', summary: 'Get the authenticated user profile')
  @RequireAuth()
  Future<Map<String, Object?>> me(RequestContext ctx) async {
    final user = ctx.principal!.claims['user'] as User;
    return user.toJson(exclude: ['password']);
  }

  @Post('/change-password', summary: 'Change password (signs out other sessions)')
  @RequireAuth()
  Future<Map<String, Object?>> changePassword(
    ChangePasswordForm form,
    AuthService auth,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final access = await auth.changePassword(
      user,
      oldPassword: form.oldPassword.value!,
      newPassword: form.newPassword.value!,
    );
    await auth.recordEvent(user.id!, 'auth.password_change');
    return <String, Object?>{
      'detail': 'Password changed. Other sessions were signed out.',
      'access': access,
    };
  }

  // ── Sessions ───────────────────────────────────────────────────────────────

  @Post('/logout',
      summary: 'Sign out this session (its token stops working)',
      statusCode: 200)
  @RequireAuth()
  Future<Map<String, Object?>> logout(
    AuthService auth,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final header = ctx.request.headers['authorization'] ?? '';
    final token = header.split(RegExp(r'\s+')).last;
    // API tokens (gsl_…) are revoked from the tokens page, not here.
    if (!token.startsWith('gsl_')) {
      await auth.logout(token);
      await auth.recordEvent(user.id!, 'auth.logout');
    }
    return <String, Object?>{'detail': 'Signed out.'};
  }

  @Post(
    '/sessions/revoke',
    summary: 'Sign out every other session; returns a new token for this one',
  )
  @RequireAuth()
  Future<Map<String, Object?>> revokeSessions(
    AuthService auth,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final access = await auth.revokeSessions(user);
    await auth.recordEvent(user.id!, 'auth.sessions_revoke');
    return <String, Object?>{'access': access};
  }

  // ── Two-factor authentication ──────────────────────────────────────────────

  @Get('/totp', summary: 'Two-factor authentication status')
  @RequireAuth()
  Future<Map<String, Object?>> totpStatus(
    AuthService auth,
    RequestContext ctx,
  ) async {
    final status = await auth.totpStatus(ctx.principal!.claims['user'] as User);
    return <String, Object?>{
      'enabled': status.enabled,
      'recoveryCodesRemaining': status.recoveryCodesRemaining,
    };
  }

  @Post(
    '/totp/setup',
    summary: 'Start two-factor setup; returns the secret and otpauth URI',
    config: RouteConfig(rateLimit: RateLimitConfig(requestsPerMinute: 10)),
  )
  @RequireAuth()
  Future<Map<String, Object?>> totpSetup(
    PasswordConfirmForm form,
    AuthService auth,
    RequestContext ctx,
  ) async {
    final setup = await auth.beginTotpSetup(
      ctx.principal!.claims['user'] as User,
      password: form.password.value!,
    );
    return <String, Object?>{
      'secret': setup.secret,
      'otpauthUri': setup.otpauthUri,
    };
  }

  @Post(
    '/totp/enable',
    summary: 'Confirm two-factor setup with a first code; returns recovery codes',
    config: RouteConfig(rateLimit: RateLimitConfig(requestsPerMinute: 10)),
  )
  @RequireAuth()
  Future<Map<String, Object?>> totpEnable(
    TotpCodeForm form,
    AuthService auth,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await auth.enableTotp(user, code: form.code.value!);
    await auth.recordEvent(user.id!, 'auth.totp_enable');
    return <String, Object?>{
      'recoveryCodes': result.recoveryCodes,
      'access': result.accessToken,
    };
  }

  @Post(
    '/totp/disable',
    summary: 'Turn two-factor authentication off',
    config: RouteConfig(rateLimit: RateLimitConfig(requestsPerMinute: 10)),
  )
  @RequireAuth()
  Future<Map<String, Object?>> totpDisable(
    TotpDisableForm form,
    AuthService auth,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await auth.disableTotp(
      user,
      password: form.password.value!,
      code: form.code.value!,
    );
    await auth.recordEvent(user.id!, 'auth.totp_disable');
    return <String, Object?>{'detail': 'Two-factor authentication is off.'};
  }

  @Post(
    '/totp/recovery-codes',
    summary: 'Replace the recovery codes',
    config: RouteConfig(rateLimit: RateLimitConfig(requestsPerMinute: 10)),
  )
  @RequireAuth()
  Future<Map<String, Object?>> totpRecoveryCodes(
    TotpCodeForm form,
    AuthService auth,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final codes =
        await auth.regenerateRecoveryCodes(user, code: form.code.value!);
    await auth.recordEvent(user.id!, 'auth.recovery_codes_regenerate');
    return <String, Object?>{'recoveryCodes': codes};
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
    final withTotp = await auth.userIdsWithTotp();
    return <String, Object?>{
      'results': users
          .map((u) => <String, Object?>{
                ...u.toJson(exclude: ['password']),
                'totp_enabled': withTotp.contains(u.id),
              })
          .toList(),
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

  @Delete(
    '/users/{id}/totp',
    summary: "Reset a user's two-factor authentication (superuser only)",
  )
  @RequireAuth()
  Future<Map<String, Object?>> resetUserTotp(
    int id,
    AuthService auth,
    RequestContext ctx,
  ) async {
    _requireSuperuser(ctx);
    final actor = ctx.principal!.claims['user'] as User;
    await auth.resetTotp(id);
    await auth.recordEvent(actor.id!, 'auth.totp_reset', targetUserId: id);
    return <String, Object?>{
      'detail': 'Two-factor authentication reset. The user was signed out.',
    };
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

Map<String, Object?> _session(User user, String accessToken) =>
    <String, Object?>{
      'user': user.toJson(exclude: ['password']),
      'access': accessToken,
    };

void _requireSuperuser(RequestContext ctx) {
  final user = ctx.principal!.claims['user'] as User;
  if (user.isSuperuser != true) {
    throw Forbidden(
      'Superuser access required.',
    );
  }
}
