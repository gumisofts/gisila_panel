import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';

/// Handles async service lifecycle jobs from the [gisila:queue:services] queue.
///
/// Actions: install | configure | start | stop | uninstall
class ServiceWorker {
  ServiceWorker(this.database);

  final Database database;

  Future<void> onServiceJob(Map<String, Object?> payload) async {
    final action = payload['action'] as String?;
    final serviceId = payload['serviceId'] as int?;
    if (action == null || serviceId == null) return;

    final svc = await _findService(serviceId);
    if (svc == null) {
      logger.w('service_worker: service #$serviceId not found — skipping');
      return;
    }

    switch (action) {
      case 'install':
        await _install(svc);
      case 'configure':
        await _configure(svc);
      case 'start':
        await _start(svc);
      case 'stop':
        await _stop(svc);
      case 'uninstall':
        await _uninstall(svc);
      default:
        logger.w('service_worker: unknown action $action — skipping');
    }
  }

  // ── Lifecycle handlers ────────────────────────────────────────────────────

  Future<void> _install(ManagedService svc) async {
    await _setStatus(svc.id!, 'installing');
    try {
      final cfg = _config(svc);
      await _runAgent([
        'service',
        'install',
        '--type',
        svc.serviceType,
        '--config',
        jsonEncode(cfg),
      ]);
      await _patch(svc.id!, {
        'status': 'running',
        'installedAt': DateTime.now().toUtc().toIso8601String(),
        'errorMessage': null,
      });
    } catch (e) {
      // Attempt best-effort rollback so we don't leave a partially-installed
      // service on the host.
      try {
        await _runAgent(['service', 'uninstall', '--type', svc.serviceType]);
      } catch (rollbackErr) {
        logger.w(
            'service_worker: rollback uninstall failed (ignored): $rollbackErr');
      }
      await _patch(svc.id!, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _configure(ManagedService svc) async {
    try {
      final cfg = _config(svc);
      await _runAgent([
        'service',
        'configure',
        '--type',
        svc.serviceType,
        '--config',
        jsonEncode(cfg),
      ]);
    } catch (e) {
      await _patch(svc.id!, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _start(ManagedService svc) async {
    try {
      await _runAgent(['service', 'start', '--type', svc.serviceType]);
      await _setStatus(svc.id!, 'running');
    } catch (e) {
      await _patch(svc.id!, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _stop(ManagedService svc) async {
    try {
      await _runAgent(['service', 'stop', '--type', svc.serviceType]);
      await _setStatus(svc.id!, 'stopped');
    } catch (e) {
      await _patch(svc.id!, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _uninstall(ManagedService svc) async {
    try {
      await _runAgent(['service', 'uninstall', '--type', svc.serviceType]);
    } catch (e) {
      // Log but do not re-throw: the agent may fail when nothing was actually
      // installed (e.g., a previous install failed before the package landed).
      // The intent of uninstall is removal, so we always delete the record.
      logger.w('service_worker: agent uninstall error (continuing): $e');
    }
    // Hard-delete the record regardless of whether the agent succeeded.
    await Query<ManagedService>(ManagedServiceTable.metadata)
        .where(ManagedServiceTable.id.eq(svc.id!))
        .delete()
        .run(database.context());
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<ManagedService?> _findService(int id) =>
      Query<ManagedService>(ManagedServiceTable.metadata)
          .where(ManagedServiceTable.id.eq(id))
          .first(database.context());

  Map<String, dynamic> _config(ManagedService svc) {
    try {
      return jsonDecode(svc.config ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _setStatus(int id, String status) =>
      _patch(id, {'status': status});

  Future<void> _patch(int id, Map<String, Object?> data) =>
      Query<ManagedService>(ManagedServiceTable.metadata)
          .where(ManagedServiceTable.id.eq(id))
          .update(data)
          .run(database.context());

  Future<void> _runAgent(List<String> args) async {
    if (hostConfig.agentMode == 'dev') {
      logger.i('service_worker (dev): agent ${args.join(' ')}');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return;
    }

    // When AGENT_BIN=dart, call: dart run <entry> <args>
    // When AGENT_MODE=sudo, prepend sudo.
    final List<String> cmd;
    if (hostConfig.agentBin == 'dart') {
      cmd = ['dart', 'run', hostConfig.agentDartEntry, ...args];
    } else if (hostConfig.agentMode == 'sudo') {
      cmd = ['sudo', '--non-interactive', hostConfig.agentBin, ...args];
    } else {
      cmd = [hostConfig.agentBin, ...args];
    }

    logger.i('service_worker: ${cmd.join(' ')}');
    final result = await Process.run(cmd.first, cmd.skip(1).toList());
    if (result.exitCode != 0) {
      throw Exception(
        'Agent exited ${result.exitCode}: ${result.stderr}'.trim(),
      );
    }
  }
}
