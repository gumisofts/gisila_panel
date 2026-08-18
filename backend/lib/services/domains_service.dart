import 'dart:convert';
import 'dart:math';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/authz/authz.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/apps_service.dart';

class DomainsService extends Service {
  static final _rng = Random.secure();
  Database get _db => db<Database>();

  Future<List<Domain>> list(User actor, int appId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.findForUser(actor, appId);
    return Query<Domain>(DomainTable.metadata)
        .where(DomainTable.appId.eq(app.id!))
        .all(_db.context());
  }

  Future<Domain> add(
    User actor,
    int appId, {
    required String hostname,
    bool isPrimary = false,
  }) async {
    final appsSvc = AppsService();
    appsSvc.attach(ctx);
    final app = await appsSvc.requireAppRole(actor, appId, TeamRole.developer);
    if (app.exposeMode != null && app.exposeMode != 'web') {
      throw BadRequest(
        'Domains are only supported for web apps. This app is exposed as '
        '"${app.exposeMode}" — see its Overview tab for the direct '
        'connection info.',
      );
    }

    final host = hostname.trim().toLowerCase();
    final existing = await Query<Domain>(DomainTable.metadata)
        .where(DomainTable.hostname.eq(host))
        .first(_db.context());
    if (existing != null) {
      if (existing.appId == app.id) {
        throw Conflict(
          'This domain is already attached to this app.',
          code: 'domain_already_attached',
        );
      }
      throw Conflict(
        'This domain is already attached to another app.',
        code: 'domain_in_use',
      );
    }

    final domain =
        await Query<Domain>(DomainTable.metadata).insert(<String, Object?>{
      'appId': app.id,
      'hostname': host,
      'isPrimary': isPrimary,
      'isVerified': false,
      'verificationToken': _randomToken(),
      'sslStatus': 'none',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());

    // Tell the worker to (re)write the Nginx vhost.
    await RedisClient.instance.rpush(
      'gisila:queue:vhosts',
      jsonEncode(<String, Object?>{
        'appId': app.id,
        'reason': 'domain_add',
        'domainId': domain.id,
      }),
    );

    return domain;
  }

  Future<void> issueCert(User actor, int appId, int domainId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.requireAppRole(actor, appId, TeamRole.developer);

    final domain = await Query<Domain>(DomainTable.metadata)
        .where(DomainTable.id.eq(domainId))
        .where(DomainTable.appId.eq(app.id!))
        .first(_db.context());
    if (domain == null) throw NotFound('Domain not found.');

    await Query<Domain>(DomainTable.metadata)
        .where(DomainTable.id.eq(domain.id!))
        .update(<String, Object?>{'sslStatus': 'pending'}).run(_db.context());

    await RedisClient.instance.rpush(
      'gisila:queue:ssl',
      jsonEncode(<String, Object?>{
        'domainId': domain.id,
        'appId': app.id,
        'hostname': domain.hostname,
      }),
    );
  }

  Future<void> delete(User actor, int appId, int domainId) async {
    final appsSvc = AppsService()..attach(ctx);
    final app = await appsSvc.requireAppRole(actor, appId, TeamRole.developer);

    await Query<Domain>(DomainTable.metadata)
        .where(DomainTable.id.eq(domainId))
        .where(DomainTable.appId.eq(app.id!))
        .delete()
        .run(_db.context());

    await RedisClient.instance.rpush(
      'gisila:queue:vhosts',
      jsonEncode(<String, Object?>{
        'appId': app.id,
        'reason': 'domain_remove',
      }),
    );
  }

  String _randomToken() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
