import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/infra/secret_box.dart';

/// Handles async object-storage jobs from the [gisila:queue:storage] queue.
///
/// Actions: install_server | uninstall_server | start_server | stop_server |
///          expose_server | create_bucket | delete_bucket. The server actions
/// act on the provider's kind (`garage`, or `minio` on hosts installed before
/// MinIO stopped publishing downloads); the `*_minio` names are accepted for
/// jobs queued by an older panel.
class StorageWorker {
  StorageWorker(this.database);

  final Database database;

  Future<void> onStorageJob(Map<String, Object?> payload) async {
    final action = payload['action'] as String?;
    if (action == null) return;
    switch (action) {
      case 'install_server' || 'install_minio':
        await _installServer(payload['providerId'] as int);
      case 'uninstall_server' || 'uninstall_minio':
        await _uninstallServer(payload['providerId'] as int);
      case 'start_server' || 'start_minio':
        await _lifecycle(payload['providerId'] as int, 'start',
            okStatus: 'running');
      case 'stop_server' || 'stop_minio':
        await _lifecycle(payload['providerId'] as int, 'stop',
            okStatus: 'stopped');
      case 'expose_server' || 'expose_minio':
        await _expose(
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

  Future<void> _installServer(int providerId) async {
    final p = await _findProvider(providerId);
    if (p == null) return;
    await _patchProvider(providerId, {'status': 'installing'});
    try {
      final port = Uri.parse(p.endpoint).port;
      await _runAgent([
        'storage',
        'install-${p.kind}',
        '--data-dir', _dataDir(p.kind),
        '--port', '$port',
        if (p.kind == 'minio')
          ...['--console-port', '${p.consolePort ?? 9001}'],
        '--root-user', p.accessKey,
        '--root-secret', p.plainSecretKey,
      ]);
      await _patchProvider(providerId, {
        'status': 'running',
        'installedAt': DateTime.now().toUtc().toIso8601String(),
        'errorMessage': null,
      });
      // If a public URL was configured at install time, front the server with
      // nginx so that URL actually serves (it binds 127.0.0.1 only).
      if ((p.publicUrl ?? '').isNotEmpty) {
        await _expose(providerId);
      }
    } catch (e) {
      logger.e('storage_worker: ${p.kind} install failed', error: e);
      await _patchProvider(providerId, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
    }
  }

  Future<void> _uninstallServer(int providerId) async {
    final p = await _findProvider(providerId);
    if (p == null) return;
    try {
      await _runAgent([
        'storage',
        'uninstall-${p.kind}',
        '--data-dir', _dataDir(p.kind),
      ]);
    } catch (e) {
      logger.w('storage_worker: ${p.kind} uninstall error (continuing): $e');
    }
    await Query<StorageProvider>(StorageProviderTable.metadata)
        .where(StorageProviderTable.id.eq(providerId))
        .delete()
        .run(database.context());
  }

  Future<void> _lifecycle(int providerId, String verb,
      {required String okStatus}) async {
    final p = await _findProvider(providerId);
    if (p == null) return;
    try {
      await _runAgent(['storage', '$verb-${p.kind}']);
      await _patchProvider(providerId, {'status': okStatus, 'errorMessage': null});
    } catch (e) {
      await _patchProvider(providerId, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
    }
  }

  /// (Re)create or remove the nginx reverse-proxy vhost for the server's
  /// public URL.
  ///
  /// [issueCert] controls whether certbot is run: when null it defaults to
  /// "yes, if the URL is https" (e.g. the post-install auto-expose). Callers can
  /// pass false to skip issuance entirely — useful when TLS is terminated
  /// upstream (Cloudflare proxy, an external load balancer).
  Future<void> _expose(int providerId, {bool? issueCert}) async {
    final p = await _findProvider(providerId);
    if (p == null) return;
    if (p.kind == 'garage') return _exposeGarage(p, issueCert: issueCert);
    if (p.kind != 'minio') return;
    final url = (p.publicUrl ?? '').trim();
    final consoleUrl = (p.consoleUrl ?? '').trim();
    final apiPort = Uri.parse(p.endpoint).port;
    try {
      if (url.isEmpty) {
        await _runAgent(['storage', 'unexpose-minio']);
      } else {
        final uri = Uri.parse(url);
        final consoleUri =
            consoleUrl.isNotEmpty ? Uri.parse(consoleUrl) : null;
        final consoleHost = consoleUri?.host;
        // Issue certs when the operator opted in AND any public URL is https
        // (API, console, or both). The agent then re-renders listen 443.
        final anyHttps =
            uri.scheme == 'https' || consoleUri?.scheme == 'https';
        final wantCert = (issueCert ?? true) && anyHttps;
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

  /// Garage has no console: one vhost, S3 API plus anonymous reads.
  Future<void> _exposeGarage(StorageProvider p, {bool? issueCert}) async {
    final url = (p.publicUrl ?? '').trim();
    try {
      if (url.isEmpty) {
        await _runAgent(['storage', 'unexpose-garage']);
        return;
      }
      final uri = Uri.parse(url);
      await _runAgent([
        'storage',
        'expose-garage',
        '--hostname', uri.host,
        '--port', '${Uri.parse(p.endpoint).port}',
        if ((issueCert ?? true) && uri.scheme == 'https') '--tls',
      ]);
    } catch (e) {
      logger.w('storage_worker: garage expose error (continuing): $e');
      await _patchProvider(p.id!, {'errorMessage': 'Expose failed: $e'});
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
        '--region', p.region ?? 'us-east-1',
        '--endpoint', p.endpoint,
        '--access-key', p.accessKey,
        '--secret-key', p.plainSecretKey,
        '--bucket', b.bucketName,
        '--scoped-access-key', b.accessKey,
        '--scoped-secret-key', b.plainSecretKey,
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
          '--region', p.region ?? 'us-east-1',
          '--endpoint', p.endpoint,
          '--access-key', p.accessKey,
          '--secret-key', p.plainSecretKey,
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

  static String _dataDir(String kind) => '/var/lib/gisila/$kind';

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
    final result = await Process.run(cmd.first, cmd.skip(1).toList(),
        environment: agentEnvironment, includeParentEnvironment: false);
    if (result.exitCode != 0) {
      throw Exception(
          'Agent exited ${result.exitCode}: ${result.stderr}'.trim());
    }
  }
}
