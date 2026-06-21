import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/forms/storage_forms.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/storage_service.dart';

part 'storage.g.dart';

@Controller('/storage', ['Storage'])
@RequireAuth()
class StorageApi {
  // ── Providers ───────────────────────────────────────────────────────────────

  @Get('/providers', summary: 'List storage providers')
  Future<Map<String, Object?>> listProviders(StorageService svc) async {
    final providers = await svc.listProviders();
    return {'results': providers.map(_serializeProvider).toList()};
  }

  @Post('/providers/minio', summary: 'Install the self-hosted MinIO server')
  Future<Map<String, Object?>> installMinio(
    InstallMinioForm form,
    StorageService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final p = await svc.installMinio(
      displayName: form.displayName.value!,
      port: form.port.value ?? 9000,
      consolePort: form.consolePort.value ?? 9001,
      publicUrl: form.publicUrl.value?.isNotEmpty == true
          ? form.publicUrl.value
          : null,
    );
    return _serializeProvider(p);
  }

  @Post('/providers/external', summary: 'Register an external S3 endpoint')
  Future<Map<String, Object?>> addConnector(
    AddConnectorForm form,
    StorageService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final p = await svc.addExternal(
      displayName: form.displayName.value!,
      endpoint: form.endpoint.value!,
      accessKey: form.accessKey.value!,
      secretKey: form.secretKey.value!,
      region: form.region.value?.isNotEmpty == true
          ? form.region.value!
          : 'us-east-1',
      publicUrl: form.publicUrl.value?.isNotEmpty == true
          ? form.publicUrl.value
          : null,
      forcePathStyle: form.forcePathStyle.value ?? true,
    );
    return _serializeProvider(p);
  }

  @Get('/providers/{id}', summary: 'Get a storage provider')
  Future<Map<String, Object?>> getProvider(int id, StorageService svc) async {
    return _serializeProvider(await svc.findProvider(id));
  }

  @Post('/providers/{id}/start', summary: 'Start the MinIO server')
  Future<Map<String, Object?>> startProvider(
    int id,
    StorageService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    return _serializeProvider(await svc.startProvider(id));
  }

  @Post('/providers/{id}/stop', summary: 'Stop the MinIO server')
  Future<Map<String, Object?>> stopProvider(
    int id,
    StorageService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    return _serializeProvider(await svc.stopProvider(id));
  }

  @Delete('/providers/{id}', summary: 'Remove a storage provider')
  Future<Map<String, Object?>> deleteProvider(
    int id,
    StorageService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await svc.uninstallProvider(id);
    return {'detail': 'Provider removal queued.'};
  }

  // ── Buckets ─────────────────────────────────────────────────────────────────

  @Get('/providers/{id}/buckets', summary: 'List buckets in a provider')
  Future<Map<String, Object?>> listBuckets(int id, StorageService svc) async {
    final provider = await svc.findProvider(id);
    final buckets = await svc.listBuckets(id);
    return {
      'results': buckets
          .map((b) => _serializeBucket(b, provider: provider, reveal: false))
          .toList(),
    };
  }

  @Post('/providers/{id}/buckets', summary: 'Create a bucket + scoped key')
  Future<Map<String, Object?>> createBucket(
    int id,
    CreateBucketForm form,
    StorageService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    final provider = await svc.findProvider(id);
    final bucket = await svc.createBucket(
      providerId: id,
      bucketName: form.bucketName.value!,
      isPublic: form.isPublic.value ?? false,
    );
    // Reveal the credentials once on creation.
    return _serializeBucket(bucket, provider: provider, reveal: true);
  }

  @Get('/providers/{id}/buckets/{bid}', summary: 'Get a bucket (with creds)')
  Future<Map<String, Object?>> getBucket(
    int id,
    int bid,
    StorageService svc,
  ) async {
    final provider = await svc.findProvider(id);
    final bucket = await svc.findBucket(bid);
    return _serializeBucket(bucket, provider: provider, reveal: true);
  }

  @Delete('/providers/{id}/buckets/{bid}', summary: 'Delete a bucket')
  Future<Map<String, Object?>> deleteBucket(
    int id,
    int bid,
    StorageService svc,
    RequestContext ctx,
  ) async {
    requireSuperuser(ctx);
    await svc.deleteBucket(bid);
    return {'detail': 'Bucket deletion queued.'};
  }

  // ── App links (credential auto-injection) ─────────────────────────────────────

  @Get('/apps/{appId}/links', summary: "List an app's linked buckets")
  Future<Map<String, Object?>> listAppLinks(
    int appId,
    StorageService svc,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final links = await svc.listAppLinks(user, appId);
    // Enrich each link with its bucket + provider for display.
    final out = <Map<String, Object?>>[];
    for (final link in links) {
      final bucket = await svc.findBucket(link.bucketId);
      final provider = await svc.findProvider(bucket.providerId);
      out.add({
        'id': link.id,
        'appId': link.appId,
        'bucketId': link.bucketId,
        'envPrefix': link.envPrefix ?? 'S3',
        'bucketName': bucket.bucketName,
        'providerName': provider.displayName,
        'providerKind': provider.kind,
        'envVars': StorageService.envVarNames(link.envPrefix ?? 'S3'),
        'createdAt': link.createdAt.toIso8601String(),
      });
    }
    return {'results': out};
  }

  @Post('/apps/{appId}/links', summary: 'Link a bucket to an app')
  Future<Map<String, Object?>> linkBucket(
    int appId,
    LinkBucketForm form,
    StorageService svc,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    final link = await svc.linkToApp(
      user,
      appId,
      form.bucketId.value!,
      envPrefix: form.envPrefix.value?.isNotEmpty == true
          ? form.envPrefix.value!
          : 'S3',
    );
    return {
      'id': link.id,
      'appId': link.appId,
      'bucketId': link.bucketId,
      'envPrefix': link.envPrefix ?? 'S3',
    };
  }

  @Delete('/apps/{appId}/links/{linkId}', summary: 'Unlink a bucket from an app')
  Future<Map<String, Object?>> unlinkBucket(
    int appId,
    int linkId,
    StorageService svc,
    RequestContext ctx,
  ) async {
    final user = ctx.principal!.claims['user'] as User;
    await svc.unlinkFromApp(user, appId, linkId);
    return {'detail': 'Bucket unlinked.'};
  }
}

// ── Serialisers ───────────────────────────────────────────────────────────────

Map<String, Object?> _serializeProvider(StorageProvider p) => {
      'id': p.id,
      'kind': p.kind,
      'displayName': p.displayName,
      'endpoint': p.endpoint,
      'region': p.region,
      'publicUrl': p.publicUrl,
      'forcePathStyle': p.forcePathStyle ?? true,
      'consolePort': p.consolePort,
      'status': p.status,
      'errorMessage': p.errorMessage,
      'installedAt': p.installedAt?.toIso8601String(),
      'createdAt': p.createdAt.toIso8601String(),
      'updatedAt': p.updatedAt?.toIso8601String(),
    };

Map<String, Object?> _serializeBucket(
  StorageBucket b, {
  required StorageProvider provider,
  required bool reveal,
}) {
  final base = <String, Object?>{
    'id': b.id,
    'providerId': b.providerId,
    'bucketName': b.bucketName,
    'isPublic': b.isPublic ?? false,
    'status': b.status,
    'errorMessage': b.errorMessage,
    'createdAt': b.createdAt.toIso8601String(),
    'updatedAt': b.updatedAt?.toIso8601String(),
  };
  if (reveal) {
    final svc = StorageService();
    base['connection'] = svc.connectionInfo(provider, b);
  }
  return base;
}
