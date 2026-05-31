import 'dart:convert';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/catalog.dart';

class ManagedServiceService extends Service {
  Database get _db => db<Database>();

  // ── Catalog ──────────────────────────────────────────────────────────────

  List<Map<String, Object?>> listCatalog() =>
      kServiceCatalog.map((d) => d.toJson()).toList();

  // ── CRUD ─────────────────────────────────────────────────────────────────

  Future<List<ManagedService>> listInstalled() =>
      Query<ManagedService>(ManagedServiceTable.metadata)
          .orderBy(ManagedServiceTable.createdAt, desc: true)
          .all(_db.context());

  Future<ManagedService> findById(int id) async {
    final svc = await Query<ManagedService>(ManagedServiceTable.metadata)
        .where(ManagedServiceTable.id.eq(id))
        .first(_db.context());
    if (svc == null) throw NotFound('Service #$id not found.');
    return svc;
  }

  Future<ManagedService> install({
    required String serviceType,
    required String displayName,
    required Map<String, String> config,
  }) async {
    final def = findService(serviceType);
    if (def == null) {
      throw HttpException(422, 'Unknown service type: $serviceType');
    }

    // Merge caller config over defaults.
    final merged = <String, String>{...defaultConfig(def), ...config};

    final now = DateTime.now().toUtc();
    final svc = await Query<ManagedService>(ManagedServiceTable.metadata)
        .insert(<String, Object?>{
      'serviceType': serviceType,
      'displayName': displayName,
      'status': def.requiresInstall ? 'pending' : 'config_only',
      'config': jsonEncode(merged),
      'createdAt': now.toIso8601String(),
    }).one(_db.context());

    if (def.requiresInstall) {
      await _enqueue('install', svc.id!);
    } else {
      await _patch(svc.id!, {
        'status': 'running',
        'installedAt': now.toIso8601String(),
      });
    }

    return findById(svc.id!);
  }

  Future<ManagedService> configure(int id, Map<String, String> config) async {
    final svc = await findById(id);
    final def = findService(svc.serviceType);
    if (def == null) throw HttpException(422, 'Unknown service type.');

    final existing = jsonDecode(svc.config ?? '{}') as Map<String, dynamic>;
    final merged = <String, String>{
      ...existing.map((k, v) => MapEntry(k, v.toString())),
      ...config,
    };

    await _patch(id, {
      'config': jsonEncode(merged),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    if (def.requiresInstall &&
        svc.status != 'pending' &&
        svc.status != 'installing') {
      await _enqueue('configure', id);
    }

    return findById(id);
  }

  Future<ManagedService> start(int id) async {
    final svc = await findById(id);
    if (svc.status == 'running') return svc;
    await _patch(id, {'status': 'pending'});
    await _enqueue('start', id);
    return findById(id);
  }

  Future<ManagedService> stop(int id) async {
    final svc = await findById(id);
    if (svc.status == 'stopped') return svc;
    await _enqueue('stop', id);
    return findById(id);
  }

  Future<void> uninstall(int id) async {
    await findById(id); // ensures exists
    await _patch(id, {'status': 'uninstalling'});
    await _enqueue('uninstall', id);
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _patch(int id, Map<String, Object?> data) =>
      Query<ManagedService>(ManagedServiceTable.metadata)
          .where(ManagedServiceTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _enqueue(String action, int serviceId) =>
      RedisClient.instance.rpush(
        'gisila:queue:services',
        jsonEncode({'action': action, 'serviceId': serviceId}),
      );
}
