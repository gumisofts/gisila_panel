import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
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
    final id = svc.id!;
    // Start a fresh log buffer so re-installs don't show stale output.
    await _clearLogs(id);
    await _setStatus(id, 'installing');
    await _log(id, 'system', 'Installing ${svc.displayName} (${svc.serviceType})…');
    try {
      final cfg = _config(svc);
      await _runAgent([
        'service',
        'install',
        '--type',
        svc.serviceType,
        '--config',
        jsonEncode(cfg),
      ], serviceId: id);
      await _patch(id, {
        'status': 'running',
        'installedAt': DateTime.now().toUtc().toIso8601String(),
        'errorMessage': null,
      });
      await _log(id, 'system', 'Installation complete — service is running.');
    } catch (e) {
      await _log(id, 'stderr', 'Installation failed: $e');
      // Attempt best-effort rollback so we don't leave a partially-installed
      // service on the host.
      try {
        await _log(id, 'system', 'Rolling back partial installation…');
        await _runAgent(['service', 'uninstall', '--type', svc.serviceType],
            serviceId: id);
      } catch (rollbackErr) {
        logger.w(
            'service_worker: rollback uninstall failed (ignored): $rollbackErr');
      }
      await _patch(id, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _configure(ManagedService svc) async {
    final id = svc.id!;
    try {
      final cfg = _config(svc);
      await _log(id, 'system', 'Applying configuration…');
      await _runAgent([
        'service',
        'configure',
        '--type',
        svc.serviceType,
        '--config',
        jsonEncode(cfg),
      ], serviceId: id);
      await _log(id, 'system', 'Configuration applied.');
    } catch (e) {
      await _log(id, 'stderr', 'Configuration failed: $e');
      await _patch(id, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _start(ManagedService svc) async {
    final id = svc.id!;
    try {
      await _log(id, 'system', 'Starting service…');
      await _runAgent(['service', 'start', '--type', svc.serviceType],
          serviceId: id);
      await _setStatus(id, 'running');
      await _log(id, 'system', 'Service started.');
    } catch (e) {
      await _log(id, 'stderr', 'Start failed: $e');
      await _patch(id, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _stop(ManagedService svc) async {
    final id = svc.id!;
    try {
      await _log(id, 'system', 'Stopping service…');
      await _runAgent(['service', 'stop', '--type', svc.serviceType],
          serviceId: id);
      await _setStatus(id, 'stopped');
      await _log(id, 'system', 'Service stopped.');
    } catch (e) {
      await _log(id, 'stderr', 'Stop failed: $e');
      await _patch(id, {
        'status': 'failed',
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }

  Future<void> _uninstall(ManagedService svc) async {
    try {
      await _log(svc.id!, 'system', 'Uninstalling service…');
      await _runAgent(['service', 'uninstall', '--type', svc.serviceType],
          serviceId: svc.id);
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

  /// Run the agent. When [serviceId] is provided the agent's stdout/stderr are
  /// streamed live to the service's log channel (and buffered for replay).
  Future<void> _runAgent(List<String> args, {int? serviceId}) async {
    if (hostConfig.agentMode == 'dev') {
      final line = 'agent (dev) ${args.join(' ')}';
      logger.i('service_worker (dev): $line');
      if (serviceId != null) await _log(serviceId, 'system', line);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return;
    }

    final cmd = buildAgentCmd(args);
    logger.i('service_worker: ${cmd.join(' ')}');

    // Blocking path when there is no live consumer.
    if (serviceId == null) {
      final result = await Process.run(cmd.first, cmd.skip(1).toList());
      if (result.exitCode != 0) {
        throw Exception(
          'Agent exited ${result.exitCode}: ${result.stderr}'.trim(),
        );
      }
      return;
    }

    // Streaming path: pipe each line to Redis as it arrives.
    final process = await Process.start(cmd.first, cmd.skip(1).toList());
    final outputs = await Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
        _log(serviceId, 'stdout', line);
        return line;
      }).toList(),
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map((line) {
        _log(serviceId, 'stderr', line);
        return line;
      }).toList(),
    ]);

    final exit = await process.exitCode;
    if (exit != 0) {
      throw Exception(
        'Agent exited $exit: ${outputs[1].join('\n')}'.trim(),
      );
    }
  }

  // ── Live log streaming ──────────────────────────────────────────────────────

  String _historyKey(int serviceId) => 'gisila:logs:service:$serviceId:history';
  String _channel(int serviceId) => 'gisila:logs:service:$serviceId';

  /// Publish one log line live and append it to the capped replay buffer.
  Future<void> _log(int serviceId, String stream, String line) async {
    final payload = jsonEncode({'stream': stream, 'line': line});
    try {
      await RedisClient.instance.rpush(_historyKey(serviceId), payload);
      await RedisClient.instance.ltrim(_historyKey(serviceId), -500, -1);
      await RedisClient.instance.expire(_historyKey(serviceId), 86400);
      await RedisClient.instance.publish(_channel(serviceId), payload);
    } catch (e) {
      logger.w('service_worker: failed to publish log line: $e');
    }
  }

  Future<void> _clearLogs(int serviceId) async {
    try {
      await RedisClient.instance.del(_historyKey(serviceId));
    } catch (_) {/* best-effort */}
  }
}
