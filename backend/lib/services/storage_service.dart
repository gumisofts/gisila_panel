import 'dart:convert';
import 'dart:math';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';

/// S3-compatible object storage (Model B).
///
/// A [StorageProvider] is an endpoint — either the self-hosted MinIO managed
/// service (`kind=minio`, installed/run by the panel) or an external connector
/// (`kind=external`, credentials only). [StorageBucket]s are provisioned inside
/// a provider and surfaced to apps as `<prefix>_*` env vars via
/// [AppStorageLink], which injects the credentials into the app's env on link.
class StorageService extends Service {
  Database get _db => db<Database>();

  // ── Providers ───────────────────────────────────────────────────────────────

  Future<List<StorageProvider>> listProviders() =>
      Query<StorageProvider>(StorageProviderTable.metadata)
          .orderBy(StorageProviderTable.createdAt, desc: true)
          .all(_db.context());

  Future<StorageProvider> findProvider(int id) async {
    final row = await Query<StorageProvider>(StorageProviderTable.metadata)
        .where(StorageProviderTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Storage provider #$id not found.');
    return row;
  }

  /// Install (or re-install) the self-hosted MinIO server. Only one MinIO
  /// provider is allowed; an existing failed one is replaced.
  Future<StorageProvider> installMinio({
    required String displayName,
    int port = 9000,
    int consolePort = 9001,
    String? publicUrl,
  }) async {
    final existing = await Query<StorageProvider>(StorageProviderTable.metadata)
        .where(StorageProviderTable.kind.eq('minio'))
        .first(_db.context());
    if (existing != null) {
      if (existing.status == 'failed') {
        await Query<StorageProvider>(StorageProviderTable.metadata)
            .where(StorageProviderTable.id.eq(existing.id!))
            .delete()
            .run(_db.context());
      } else {
        throw HttpException(409, 'MinIO is already installed.');
      }
    }
    if (port < 1024 || port > 65535 || consolePort < 1024 || consolePort > 65535) {
      throw HttpException(422, 'Ports must be between 1024 and 65535.');
    }

    final now = DateTime.now().toUtc();
    final provider =
        await Query<StorageProvider>(StorageProviderTable.metadata)
            .insert(<String, Object?>{
      'kind': 'minio',
      'displayName': displayName,
      'endpoint': 'http://127.0.0.1:$port',
      'region': 'us-east-1',
      'publicUrl': publicUrl,
      // Root credentials the worker passes to the agent on install.
      'accessKey': _generateAccessKey(),
      'secretKey': _generateSecret(),
      'forcePathStyle': true,
      'consolePort': consolePort,
      'status': 'pending',
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await _enqueue('install_minio', {'providerId': provider.id});
    return findProvider(provider.id!);
  }

  /// Register an external S3-compatible endpoint (R2, AWS S3, Backblaze B2 …).
  /// Nothing is installed — it is usable immediately (`config_only`).
  Future<StorageProvider> addExternal({
    required String displayName,
    required String endpoint,
    required String accessKey,
    required String secretKey,
    String region = 'us-east-1',
    String? publicUrl,
    bool forcePathStyle = true,
  }) async {
    if (!endpoint.startsWith('http://') && !endpoint.startsWith('https://')) {
      throw HttpException(422, 'Endpoint must start with http:// or https://');
    }
    final now = DateTime.now().toUtc();
    final provider =
        await Query<StorageProvider>(StorageProviderTable.metadata)
            .insert(<String, Object?>{
      'kind': 'external',
      'displayName': displayName,
      'endpoint': endpoint,
      'region': region,
      'publicUrl': publicUrl,
      'accessKey': accessKey,
      'secretKey': secretKey,
      'forcePathStyle': forcePathStyle,
      'status': 'config_only',
      'installedAt': now.toIso8601String(),
      'createdAt': now.toIso8601String(),
    }).one(_db.context());
    return findProvider(provider.id!);
  }

  Future<StorageProvider> startProvider(int id) async {
    final p = await findProvider(id);
    if (p.kind != 'minio') return p; // external is always "on"
    if (p.status == 'running') return p;
    await _patchProvider(id, {'status': 'pending'});
    await _enqueue('start_minio', {'providerId': id});
    return findProvider(id);
  }

  Future<StorageProvider> stopProvider(int id) async {
    final p = await findProvider(id);
    if (p.kind != 'minio') {
      throw HttpException(422, 'Only the MinIO server can be stopped.');
    }
    if (p.status == 'stopped') return p;
    await _enqueue('stop_minio', {'providerId': id});
    return findProvider(id);
  }

  /// Remove a provider. For MinIO this enqueues an agent uninstall; for external
  /// it just drops the record. Either way, every bucket linked to an app first
  /// has its injected env vars stripped so apps aren't left with dead creds.
  Future<void> uninstallProvider(int id) async {
    final p = await findProvider(id);
    // Strip injected env vars for all buckets under this provider.
    final buckets = await listBuckets(id);
    for (final b in buckets) {
      await _removeAllLinksForBucket(b.id!);
    }
    if (p.kind == 'minio') {
      await _patchProvider(id, {'status': 'uninstalling'});
      await _enqueue('uninstall_minio', {'providerId': id});
    } else {
      await Query<StorageProvider>(StorageProviderTable.metadata)
          .where(StorageProviderTable.id.eq(id))
          .delete()
          .run(_db.context());
    }
  }

  // ── Buckets ─────────────────────────────────────────────────────────────────

  Future<List<StorageBucket>> listBuckets(int providerId) =>
      Query<StorageBucket>(StorageBucketTable.metadata)
          .where(StorageBucketTable.providerId.eq(providerId))
          .orderBy(StorageBucketTable.createdAt, desc: true)
          .all(_db.context());

  Future<StorageBucket> findBucket(int id) async {
    final row = await Query<StorageBucket>(StorageBucketTable.metadata)
        .where(StorageBucketTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Bucket #$id not found.');
    return row;
  }

  Future<StorageBucket> createBucket({
    required int providerId,
    required String bucketName,
    bool isPublic = false,
  }) async {
    final provider = await findProvider(providerId);
    if (provider.kind == 'minio' && provider.status != 'running') {
      throw HttpException(422, 'MinIO must be running to create a bucket.');
    }
    _validateBucketName(bucketName);

    // MinIO mints a dedicated, bucket-scoped user; external providers reuse the
    // provider credentials (no IAM user minting over plain S3).
    final scopedAccess =
        provider.kind == 'minio' ? _generateAccessKey() : provider.accessKey;
    final scopedSecret =
        provider.kind == 'minio' ? _generateSecret() : provider.secretKey;

    final now = DateTime.now().toUtc();
    final bucket = await Query<StorageBucket>(StorageBucketTable.metadata)
        .insert(<String, Object?>{
      'providerId': providerId,
      'bucketName': bucketName,
      'accessKey': scopedAccess,
      'secretKey': scopedSecret,
      'isPublic': isPublic,
      'status': 'pending',
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await _enqueue('create_bucket', {
      'providerId': providerId,
      'bucketId': bucket.id,
    });
    return findBucket(bucket.id!);
  }

  Future<void> deleteBucket(int id) async {
    final bucket = await findBucket(id);
    // Strip injected env vars from every app this bucket is linked to.
    await _removeAllLinksForBucket(id);

    if (bucket.status == 'pending' || bucket.status == 'failed') {
      // Never provisioned on the server — drop the row directly.
      await Query<StorageBucket>(StorageBucketTable.metadata)
          .where(StorageBucketTable.id.eq(id))
          .delete()
          .run(_db.context());
      return;
    }
    await _patchBucket(id, {'status': 'deleted'});
    await _enqueue('delete_bucket', {
      'providerId': bucket.providerId,
      'bucketId': id,
    });
  }

  /// Connection details for a bucket (used by serializers + env injection).
  Map<String, Object?> connectionInfo(
      StorageProvider provider, StorageBucket bucket) {
    return {
      'endpoint': provider.endpoint,
      'region': provider.region ?? 'us-east-1',
      'bucket': bucket.bucketName,
      'accessKey': bucket.accessKey,
      'secretKey': bucket.secretKey,
      'publicUrl': provider.publicUrl,
      'forcePathStyle': provider.forcePathStyle ?? true,
    };
  }

  // ── App links (credential auto-injection) ─────────────────────────────────────

  Future<List<AppStorageLink>> listAppLinks(User actor, int appId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.findForUser(actor, appId);
    return Query<AppStorageLink>(AppStorageLinkTable.metadata)
        .where(AppStorageLinkTable.appId.eq(app.id!))
        .orderBy(AppStorageLinkTable.createdAt, desc: true)
        .all(_db.context());
  }

  /// Link a bucket to an app and inject `<prefix>_*` env vars (live on the next
  /// deploy). Developer role on the app is required.
  Future<AppStorageLink> linkToApp(
    User actor,
    int appId,
    int bucketId, {
    String envPrefix = 'S3',
  }) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.requireAppRole(actor, appId, TeamRole.developer);
    final bucket = await findBucket(bucketId);
    final provider = await findProvider(bucket.providerId);

    final prefix = _sanitizePrefix(envPrefix);

    final existing = await Query<AppStorageLink>(AppStorageLinkTable.metadata)
        .where(AppStorageLinkTable.appId.eq(app.id!))
        .where(AppStorageLinkTable.bucketId.eq(bucketId))
        .first(_db.context());
    if (existing != null) {
      throw Conflict('This bucket is already linked to the app.',
          code: 'bucket_already_linked');
    }

    final now = DateTime.now().toUtc();
    final link = await Query<AppStorageLink>(AppStorageLinkTable.metadata)
        .insert(<String, Object?>{
      'appId': app.id,
      'bucketId': bucketId,
      'envPrefix': prefix,
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    await _injectEnv(app.id!, prefix, provider, bucket);
    return link;
  }

  Future<void> unlinkFromApp(User actor, int appId, int linkId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.requireAppRole(actor, appId, TeamRole.developer);
    final link = await Query<AppStorageLink>(AppStorageLinkTable.metadata)
        .where(AppStorageLinkTable.id.eq(linkId))
        .where(AppStorageLinkTable.appId.eq(app.id!))
        .first(_db.context());
    if (link == null) throw NotFound('Storage link #$linkId not found.');
    await _removeEnv(app.id!, link.envPrefix ?? 'S3');
    await Query<AppStorageLink>(AppStorageLinkTable.metadata)
        .where(AppStorageLinkTable.id.eq(linkId))
        .delete()
        .run(_db.context());
  }

  // ── Env injection helpers ─────────────────────────────────────────────────────

  /// The env var names injected for a given [prefix].
  static List<String> envVarNames(String prefix) => [
        '${prefix}_ENDPOINT',
        '${prefix}_REGION',
        '${prefix}_BUCKET',
        '${prefix}_ACCESS_KEY',
        '${prefix}_SECRET_KEY',
        '${prefix}_PUBLIC_URL',
        '${prefix}_FORCE_PATH_STYLE',
      ];

  Future<void> _injectEnv(
    int appId,
    String prefix,
    StorageProvider provider,
    StorageBucket bucket,
  ) async {
    final values = <String, ({String value, bool secret})>{
      '${prefix}_ENDPOINT': (value: provider.endpoint, secret: false),
      '${prefix}_REGION': (value: provider.region ?? 'us-east-1', secret: false),
      '${prefix}_BUCKET': (value: bucket.bucketName, secret: false),
      '${prefix}_ACCESS_KEY': (value: bucket.accessKey, secret: true),
      '${prefix}_SECRET_KEY': (value: bucket.secretKey, secret: true),
      if (provider.publicUrl != null && provider.publicUrl!.isNotEmpty)
        '${prefix}_PUBLIC_URL': (value: provider.publicUrl!, secret: false),
      '${prefix}_FORCE_PATH_STYLE': (
        value: (provider.forcePathStyle ?? true).toString(),
        secret: false
      ),
    };
    final now = DateTime.now().toUtc().toIso8601String();
    for (final entry in values.entries) {
      final existing = await Query<EnvVar>(EnvVarTable.metadata)
          .where(EnvVarTable.appId.eq(appId))
          .where(EnvVarTable.name.eq(entry.key))
          .first(_db.context());
      if (existing == null) {
        await Query<EnvVar>(EnvVarTable.metadata).insert(<String, Object?>{
          'appId': appId,
          'name': entry.key,
          'value': entry.value.value,
          'isSecret': entry.value.secret,
          'updatedAt': now,
        }).run(_db.context());
      } else {
        await Query<EnvVar>(EnvVarTable.metadata)
            .where(EnvVarTable.id.eq(existing.id!))
            .update(<String, Object?>{
          'value': entry.value.value,
          'isSecret': entry.value.secret,
          'updatedAt': now,
        }).run(_db.context());
      }
    }
  }

  Future<void> _removeEnv(int appId, String prefix) async {
    for (final name in envVarNames(prefix)) {
      await Query<EnvVar>(EnvVarTable.metadata)
          .where(EnvVarTable.appId.eq(appId))
          .where(EnvVarTable.name.eq(name))
          .delete()
          .run(_db.context());
    }
  }

  /// Remove every app link for a bucket and strip the injected env vars. Used
  /// when a bucket or its provider is deleted.
  Future<void> _removeAllLinksForBucket(int bucketId) async {
    final links = await Query<AppStorageLink>(AppStorageLinkTable.metadata)
        .where(AppStorageLinkTable.bucketId.eq(bucketId))
        .all(_db.context());
    for (final link in links) {
      await _removeEnv(link.appId, link.envPrefix ?? 'S3');
    }
    await Query<AppStorageLink>(AppStorageLinkTable.metadata)
        .where(AppStorageLinkTable.bucketId.eq(bucketId))
        .delete()
        .run(_db.context());
  }

  // ── Validation + helpers ──────────────────────────────────────────────────────

  void _validateBucketName(String name) {
    // S3 bucket naming: 3–63 chars, lowercase letters, digits, hyphens; must
    // start/end alphanumeric; no consecutive dots (we disallow dots entirely
    // for path-style + TLS simplicity).
    final re = RegExp(r'^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$');
    if (!re.hasMatch(name)) {
      throw HttpException(
          422,
          'Invalid bucket name "$name". Use 3–63 lowercase letters, digits and '
          'hyphens, starting and ending alphanumerically.');
    }
  }

  String _sanitizePrefix(String? raw) {
    final p = (raw ?? 'S3').trim().toUpperCase();
    final re = RegExp(r'^[A-Z][A-Z0-9_]{0,30}$');
    if (!re.hasMatch(p)) {
      throw HttpException(
          422,
          'Invalid env prefix "$raw". Use letters, digits and underscores, '
          'starting with a letter.');
    }
    return p;
  }

  Future<void> _patchProvider(int id, Map<String, Object?> data) =>
      Query<StorageProvider>(StorageProviderTable.metadata)
          .where(StorageProviderTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _patchBucket(int id, Map<String, Object?> data) =>
      Query<StorageBucket>(StorageBucketTable.metadata)
          .where(StorageBucketTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _enqueue(String action, Map<String, Object?> payload) =>
      RedisClient.instance.rpush(
        'gisila:queue:storage',
        jsonEncode({'action': action, ...payload}),
      );
}

// S3-style credential generators. Access keys are 20 uppercase-alnum chars,
// secrets are 40 URL-safe alnum chars (so they embed cleanly in an MC_HOST URL
// and an .env file without escaping).
const _accessAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const _secretAlphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

String _generateAccessKey() {
  final rng = Random.secure();
  return List.generate(20, (_) => _accessAlphabet[rng.nextInt(_accessAlphabet.length)])
      .join();
}

String _generateSecret() {
  final rng = Random.secure();
  return List.generate(40, (_) => _secretAlphabet[rng.nextInt(_secretAlphabet.length)])
      .join();
}
