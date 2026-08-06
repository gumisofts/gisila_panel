import 'dart:async';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';

/// Handles async Application (runtime/language stack) lifecycle jobs from
/// the `gisila:queue:applications` queue — install/remove a toolchain on the
/// host, independently of any specific app deployment.
///
/// Versioned Applications carry an `applicationVersionId`, and the job settles
/// that [ApplicationVersion] row: several versions of the same runtime can be
/// installing, installed or failed at once, so the [Application] row's own
/// status is derived from its children rather than set directly.
///
/// Actions: install | remove
class ApplicationWorker {
  ApplicationWorker(this.database);

  final Database database;

  Future<void> onApplicationJob(Map<String, Object?> payload) async {
    final action = payload['action'] as String?;
    final applicationId = payload['applicationId'] as int?;
    final version = payload['version'] as String?;
    final versionId = payload['applicationVersionId'] as int?;
    final dropFamily = payload['dropFamily'] as bool? ?? false;
    if (action == null || applicationId == null) return;

    final app = await _findApplication(applicationId);
    if (app == null) {
      logger.w(
          'application_worker: application #$applicationId not found — skipping');
      return;
    }

    switch (action) {
      case 'install':
        await _install(app, version, versionId);
      case 'remove':
        await _remove(app, version, versionId, dropFamily);
      default:
        logger.w('application_worker: unknown action $action — skipping');
    }
  }

  // ── Lifecycle handlers ────────────────────────────────────────────────────

  Future<void> _install(Application app, String? version, int? versionId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _runAgent([
        'runtime',
        'install',
        '--key', app.key!,
        if (version != null && version.isNotEmpty) ...['--version', version],
      ]);
      if (versionId != null) {
        await _patchVersion(versionId, {
          'status': 'installed',
          'installedAt': now,
          'errorMessage': null,
          'updatedAt': now,
        });
      }
      await _patch(app.id!, {
        'status': 'installed',
        'installedAt': now,
        'errorMessage': null,
      });
    } catch (e) {
      logger.w('application_worker: install failed for ${app.key} '
          '${version ?? ''}: $e');
      if (versionId != null) {
        await _patchVersion(versionId, {
          'status': 'failed',
          'errorMessage': e.toString(),
          'updatedAt': now,
        });
      }
      await _settleFamily(app, fallbackError: e.toString());
    }
  }

  Future<void> _remove(
    Application app,
    String? version,
    int? versionId,
    bool dropFamily,
  ) async {
    try {
      await _runAgent([
        'runtime',
        'remove',
        '--key', app.key!,
        if (version != null && version.isNotEmpty) ...['--version', version],
      ]);
    } catch (e) {
      // Removal intent wins even if the agent step errors (e.g. nothing was
      // actually installed on this host) — same rationale as ServiceWorker.
      logger.w('application_worker: agent remove error (continuing): $e');
    }

    if (versionId != null) {
      await Query<ApplicationVersion>(ApplicationVersionTable.metadata)
          .where(ApplicationVersionTable.id.eq(versionId))
          .delete()
          .run(database.context());
    }

    if (dropFamily) {
      // Child rows go with it via ON DELETE CASCADE.
      await Query<Application>(ApplicationTable.metadata)
          .where(ApplicationTable.id.eq(app.id!))
          .delete()
          .run(database.context());
      return;
    }

    await _settleFamily(app);
  }

  /// Recompute the family row's status from its remaining versions, so one
  /// failed version does not mark a runtime with three working ones as failed.
  Future<void> _settleFamily(Application app, {String? fallbackError}) async {
    final versions = await Query<ApplicationVersion>(
      ApplicationVersionTable.metadata,
    )
        .where(ApplicationVersionTable.applicationId.eq(app.id!))
        .all(database.context());

    if (versions.isEmpty) {
      await _patch(app.id!, {
        'status': fallbackError != null ? 'failed' : 'pending',
        if (fallbackError != null) 'errorMessage': fallbackError,
      });
      return;
    }

    final anyInstalled = versions.any((v) => v.status == 'installed');
    final anyWorking =
        versions.any((v) => v.status == 'installing' || v.status == 'removing');
    final failed = versions.where((v) => v.status == 'failed').toList();

    await _patch(app.id!, {
      'status': anyInstalled
          ? 'installed'
          : anyWorking
              ? 'installing'
              : failed.isNotEmpty
                  ? 'failed'
                  : 'pending',
      // Surface a version-level failure on the family only when nothing else
      // works — otherwise the per-version row carries it.
      'errorMessage':
          !anyInstalled && failed.isNotEmpty ? failed.first.errorMessage : null,
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Application?> _findApplication(int id) =>
      Query<Application>(ApplicationTable.metadata)
          .where(ApplicationTable.id.eq(id))
          .first(database.context());

  Future<void> _patch(int id, Map<String, Object?> data) =>
      Query<Application>(ApplicationTable.metadata)
          .where(ApplicationTable.id.eq(id))
          .update(data)
          .run(database.context());

  Future<void> _patchVersion(int id, Map<String, Object?> data) =>
      Query<ApplicationVersion>(ApplicationVersionTable.metadata)
          .where(ApplicationVersionTable.id.eq(id))
          .update(data)
          .run(database.context());

  Future<void> _runAgent(List<String> args) async {
    if (hostConfig.agentMode == 'dev') {
      logger.i('application_worker (dev): agent ${args.join(' ')}');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return;
    }

    final cmd = buildAgentCmd(args);
    logger.i('application_worker: ${cmd.join(' ')}');
    final result = await Process.run(cmd.first, cmd.skip(1).toList());
    if (result.exitCode != 0) {
      throw Exception(
        'Agent exited ${result.exitCode}: ${result.stderr}'.trim(),
      );
    }
  }
}
