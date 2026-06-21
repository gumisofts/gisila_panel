import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';

/// Handles async object-storage jobs from the [gisila:queue:storage] queue.
///
/// Actions: install_minio | uninstall_minio | start_minio | stop_minio |
///          create_bucket | delete_bucket
class StorageWorker {
  StorageWorker(this.database);

  final Database database;

  Future<void> onStorageJob(Map<String, Object?> payload) async {
    final action = payload['action'] as String?;
    if (action == null) return;
    switch (action) {
      case 'install_minio':
        await _installMinio(payload['providerId'] as int);
      case 'uninstall_minio':
        await _uninstallMinio(payload['providerId'] as int);
      case 'start_minio':
        await _lifecycleMinio(payload['providerId'] as int, 'start-minio',
            okStatus: 'running');
      case 'stop_minio':
        await _lifecycleMinio(payload['providerId'] as int, 'stop-minio',
            okStatus: 'stopped');
      case 'expose_minio':
        await _exposeMinio(
          payload['providerId'] as int,
          issueCert: payload['issueCert'] as bool?,
        );
      case 'create_bucket':
        await _createBucket(
          payload['providerId'] as int,
          payload['bucketId'] as int,
        );
      case 'delete_bucket':
        await _deleteBucket(
          payload['providerId'] as int,
          payload['bucketId'] as int,
        );
      default:
        logger.w('storage_worker: unknown action $action — skipping');
    }
  }

  // ── Providers ───────────────────────────────────────────────────────────────

  Future<void> _installMinio(int providerId) async {
    final p = await _findProvider(providerId);
    if (p == null) return;
    await _patchProvider(providerId, {'status': 'installing'});
    try {
      final port = Uri.parse(p.endpoint).port;
      await _runAgent([
        'storage',
        'install-minio',
        '--data-dir', _minioDataDir,
        '--port', '$port',
        '--console-port', '${p.consolePort ?? 9001}',
        '--root-user', p.accessKey,
        '--root-secret', p.secretKey,
      ]);
      await _patchProvider(providerId, {
        'status': 'running',
        'installedAt': DateTime.now().toUtc().toIso8601String(),
        'errorMessage': null,
      });
      // If a public URL was configured at install time, front MinIO with nginx
      // so that URL actually serves (MinIO binds 127.0.0.1 only).
      if ((p.publicUrl ?? '').isNotEmpty) {
        await _exposeMinio(providerId);
      }
    } catch (e) {
      logger.e('storage_worker: minio install failed', error: e);
      await _patchProvider(providerId, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
    }
  }

  Future<void> _uninstallMinio(int providerId) async {
    final p = await _findProvider(providerId);
    if (p == null) return;
    try {
      await _runAgent([
        'storage',
        'uninstall-minio',
        '--data-dir', _minioDataDir,
      ]);
    } catch (e) {
      logger.w('storage_worker: minio uninstall error (continuing): $e');
    }
    await Query<StorageProvider>(StorageProviderTable.metadata)
        .where(StorageProviderTable.id.eq(providerId))
        .delete()
        .run(database.context());
  }

  Future<void> _lifecycleMinio(int providerId, String agentAction,
      {required String okStatus}) async {
    final p = await _findProvider(providerId);
    if (p == null) return;
    try {
      await _runAgent(['storage', agentAction]);
      await _patchProvider(providerId, {'status': okStatus, 'errorMessage': null});
    } catch (e) {
      await _patchProvider(providerId, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
    }
  }

  /// (Re)create or remove the nginx reverse-proxy vhost for MinIO's public URL.
  ///
  /// [issueCert] controls whether certbot is run: when null it defaults to
  /// "yes, if the URL is https" (e.g. the post-install auto-expose). Callers can
  /// pass false to skip issuance entirely — useful when TLS is terminated
  /// upstream (Cloudflare proxy, an external load balancer).
  Future<void> _exposeMinio(int providerId, {bool? issueCert}) async {
    final p = await _findProvider(providerId);
    if (p == null || p.kind != 'minio') return;
    final url = (p.publicUrl ?? '').trim();
    final consoleUrl = (p.consoleUrl ?? '').trim();
    final apiPort = Uri.parse(p.endpoint).port;
    try {
      if (url.isEmpty) {
        await _runAgent(['storage', 'unexpose-minio']);
      } else {
        final uri = Uri.parse(url);
        final consoleHost =
            consoleUrl.isNotEmpty ? Uri.parse(consoleUrl).host : null;
        // Only request a cert when the operator opted in AND the URL is https.
        final wantCert = (issueCert ?? true) && uri.scheme == 'https';
        await _runAgent([
          'storage',
          'expose-minio',
          '--hostname', uri.host,
          '--port', '$apiPort',
          '--console-port', '${p.consolePort ?? 9001}',
          if (consoleHost != null) ...['--console-hostname', consoleHost],
          if (wantCert) '--tls',
        ]);
      }
    } catch (e) {
      logger.w('storage_worker: minio expose error (continuing): $e');
      await _patchProvider(providerId, {'errorMessage': 'Expose failed: $e'});
    }
  }

  // ── Buckets ─────────────────────────────────────────────────────────────────

  Future<void> _createBucket(int providerId, int bucketId) async {
    final p = await _findProvider(providerId);
    final b = await _findBucket(bucketId);
    if (p == null || b == null) return;
    try {
      await _runAgent([
        'storage',
        'create-bucket',
        '--kind', p.kind,
        '--endpoint', p.endpoint,
        '--access-key', p.accessKey,
        '--secret-key', p.secretKey,
        '--bucket', b.bucketName,
        '--scoped-access-key', b.accessKey,
        '--scoped-secret-key', b.secretKey,
        if (b.isPublic == true) '--public',
      ]);
      await _patchBucket(bucketId, {'status': 'active', 'errorMessage': null});
    } catch (e) {
      logger.e('storage_worker: bucket create failed', error: e);
      await _patchBucket(bucketId, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
    }
  }

  Future<void> _deleteBucket(int providerId, int bucketId) async {
    final p = await _findProvider(providerId);
    final b = await _findBucket(bucketId);
    if (p != null && b != null) {
      try {
        await _runAgent([
          'storage',
          'delete-bucket',
          '--kind', p.kind,
          '--endpoint', p.endpoint,
          '--access-key', p.accessKey,
          '--secret-key', p.secretKey,
          '--bucket', b.bucketName,
          '--scoped-access-key', b.accessKey,
        ]);
      } catch (e) {
        logger.w('storage_worker: bucket delete error (continuing): $e');
      }
    }
    // Drop the row regardless — the intent is removal.
    await Query<StorageBucket>(StorageBucketTable.metadata)
        .where(StorageBucketTable.id.eq(bucketId))
        .delete()
        .run(database.context());
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  static const _minioDataDir = '/var/lib/gisila/minio';

  Future<StorageProvider?> _findProvider(int id) =>
      Query<StorageProvider>(StorageProviderTable.metadata)
          .where(StorageProviderTable.id.eq(id))
          .first(database.context());

  Future<StorageBucket?> _findBucket(int id) =>
      Query<StorageBucket>(StorageBucketTable.metadata)
          .where(StorageBucketTable.id.eq(id))
          .first(database.context());

  Future<void> _patchProvider(int id, Map<String, Object?> data) =>
      Query<StorageProvider>(StorageProviderTable.metadata)
          .where(StorageProviderTable.id.eq(id))
          .update({...data, 'updatedAt': DateTime.now().toUtc().toIso8601String()})
          .run(database.context());

  Future<void> _patchBucket(int id, Map<String, Object?> data) =>
      Query<StorageBucket>(StorageBucketTable.metadata)
          .where(StorageBucketTable.id.eq(id))
          .update({...data, 'updatedAt': DateTime.now().toUtc().toIso8601String()})
          .run(database.context());

  Future<void> _runAgent(List<String> args) async {
    if (hostConfig.agentMode == 'dev') {
      logger.i('storage_worker (dev): agent ${args.join(' ')}');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return;
    }
    final cmd = buildAgentCmd(args);
    logger.i('storage_worker: agent ${cmd.join(' ')}');
    final result = await Process.run(cmd.first, cmd.skip(1).toList());
    if (result.exitCode != 0) {
      throw Exception(
          'Agent exited ${result.exitCode}: ${result.stderr}'.trim());
    }
  }
}
