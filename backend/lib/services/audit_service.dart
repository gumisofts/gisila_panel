import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/models/models.dart';

/// Read access to the [AuditLog] — the record of every action a user performed.
///
/// Writes are handled globally by `auditMiddleware`; this service only serves
/// the panel's Activity view.
class AuditService extends Service {
  Database get _db => db<Database>();

  /// The most recent actions performed by [actor], newest first.
  Future<List<AuditLog>> listForActor(User actor, {int limit = 100}) {
    final capped = limit.clamp(1, 500);
    return Query<AuditLog>(AuditLogTable.metadata)
        .where(AuditLogTable.actorId.eq(actor.id!))
        .orderBy(AuditLogTable.createdAt, desc: true)
        .limit(capped)
        .all(_db.context());
  }
}
