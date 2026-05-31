import 'package:gisila/gisila.dart';
import 'package:gisila_orm/gisila.dart';

/// A [DatabaseProvider] that hands out a process-wide [Database] pool to
/// every request. The pool manages individual connections internally —
/// [Database.context] borrows one for each query and releases it on
/// completion, so nothing needs to be opened or closed per request.
class GisilaOrmDatabaseProvider extends DatabaseProvider<Database> {
  GisilaOrmDatabaseProvider(this._database);

  final Database _database;

  @override
  Future<Database> open(Request request) async => _database;

  @override
  Future<void> close(Database session, {required bool ok}) async {}
}
