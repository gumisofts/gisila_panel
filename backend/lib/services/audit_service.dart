import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/models/models.dart';

/// Read access to the [AuditLog] — the record of every action a user performed.
///
/// Writes are handled globally by `auditMiddleware`; this service only serves
/// the panel's Activity view.
class AuditService extends Service {
  Database get _db => db<Database>();

  /// A page of [actor]'s most recent actions, newest first, plus the total
  /// row count so the caller can render page numbers.
  Future<({List<AuditLog> items, int count})> listForActor(
    User actor, {
    int limit = 100,
    int offset = 0,
  }) async {
    final capped = limit.clamp(1, 500);
    final safeOffset = offset < 0 ? 0 : offset;
    final db = _db.context();

    // Two separate builders: `.count()` must run without the LIMIT/OFFSET/
    // ORDER BY the page query sets, or it would count only the current page.
    final items = await Query<AuditLog>(AuditLogTable.metadata)
        .where(AuditLogTable.actorId.eq(actor.id!))
        .orderBy(AuditLogTable.createdAt, desc: true)
        .limit(capped)
        .offset(safeOffset)
        .all(db);
    final count = await Query<AuditLog>(AuditLogTable.metadata)
        .where(AuditLogTable.actorId.eq(actor.id!))
        .count(db);

    return (items: items, count: count);
  }
}
