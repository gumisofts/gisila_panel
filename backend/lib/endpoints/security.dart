import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/forms/security_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/security_service.dart';

part 'security.g.dart';

@Controller('/me/security', ['Security'])
@RequireAuth()
class SecurityApi {
  @Get('/tokens', summary: 'List my API tokens')
  Future<Map<String, Object?>> tokens(
    SecurityService security,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final tokens = await security.listTokens(user);
    return <String, Object?>{
      'results': tokens.map((t) => t.toJson(exclude: ['tokenHash'])).toList(),
    };
  }

  @Post('/tokens', summary: 'Issue a new API token')
  Future<Map<String, Object?>> issueToken(
    CreateApiTokenForm form,
    SecurityService security,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await security.issueToken(
      user,
      name: form.name.value!,
      expiresInDays: form.expiresInDays.value,
    );
    return <String, Object?>{
      'token': result.token.toJson(exclude: ['tokenHash']),
      'plain': result.plain,
      'warning': 'This token will only be shown once — store it now.',
    };
  }

  @Delete('/tokens/{id}', summary: 'Revoke an API token')
  Future<Map<String, Object?>> revokeToken(
    int id,
    SecurityService security,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await security.revokeToken(user, id);
    return <String, Object?>{'detail': 'Token revoked.'};
  }

  @Get('/ssh-keys', summary: 'List my SSH keys')
  Future<Map<String, Object?>> sshKeys(
    SecurityService security,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final keys = await security.listSshKeys(user);
    return <String, Object?>{
      'results': keys.map((k) => k.toJson()).toList(),
    };
  }

  @Post('/ssh-keys', summary: 'Add an SSH key (paste existing public key)')
  Future<Map<String, Object?>> addSshKey(
    AddSshKeyForm form,
    SecurityService security,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final key = await security.addSshKey(
      user,
      name: form.name.value!,
      publicKey: form.publicKey.value!,
      algorithm: form.algorithm.value,
    );
    return key.toJson(exclude: ['privateKey']);
  }

  @Post('/ssh-keys/generate', summary: 'Generate a new SSH keypair')
  Future<Map<String, Object?>> generateSshKey(
    GenerateSshKeyForm form,
    SecurityService security,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final result = await security.generateKey(
      user,
      name: form.name.value!,
      algorithm: form.algorithm.value!,
    );
    return <String, Object?>{
      'key': result.key.toJson(exclude: ['privateKey']),
      'privateKey': result.privateKey,
      'warning':
          'This private key will only be shown once — store it if you need it externally.',
    };
  }

  @Delete('/ssh-keys/{id}', summary: 'Delete an SSH key')
  Future<Map<String, Object?>> deleteSshKey(
    int id,
    SecurityService security,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await security.deleteSshKey(user, id);
    return <String, Object?>{'detail': 'SSH key deleted.'};
  }
}
