import 'dart:async';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';

/// Handles async Application (runtime/language stack) lifecycle jobs from
/// the `gisila:queue:applications` queue — install/remove a toolchain on the
/// host, independently of any specific app deployment.
///
/// Actions: install | remove
class ApplicationWorker {
  ApplicationWorker(this.database);

  final Database database;

  Future<void> onApplicationJob(Map<String, Object?> payload) async {
    final action = payload['action'] as String?;
    final applicationId = payload['applicationId'] as int?;
    final version = payload['version'] as String?;
    if (action == null || applicationId == null) return;

    final app = await _findApplication(applicationId);
    if (app == null) {
      logger.w(
          'application_worker: application #$applicationId not found — skipping');
      return;
    }

    switch (action) {
      case 'install':
        await _install(app, version);
      case 'remove':
        await _remove(app, version);
      default:
        logger.w('application_worker: unknown action $action — skipping');
    }
  }

  // ── Lifecycle handlers ────────────────────────────────────────────────────

  Future<void> _install(Application app, String? version) async {
    try {
      await _runAgent([
        'runtime',
        'install',
        '--key', app.key!,
        if (version != null && version.isNotEmpty) ...['--version', version],
      ]);
      await _patch(app.id!, {
        'status': 'installed',
        'installedAt': DateTime.now().toUtc().toIso8601String(),
        'errorMessage': null,
      });
    } catch (e) {
      logger.w('application_worker: install failed for ${app.key}: $e');
      await _patch(app.id!, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
    }
  }

  Future<void> _remove(Application app, String? version) async {
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
    await Query<Application>(ApplicationTable.metadata)
        .where(ApplicationTable.id.eq(app.id!))
        .delete()
        .run(database.context());
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
