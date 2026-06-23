import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_panel/services/database_engine.dart';

part 'db_engines.g.dart';

/// Discovery endpoint for the Databases UI: lists the database engines the panel
/// can manage (PostgreSQL, MongoDB, …) plus their versions, capabilities and
/// vocabulary, so the frontend can render each engine's controls generically.
@Controller('/db-engines', ['Databases'])
@RequireAuth()
class DbEnginesApi {
  @Get('/', summary: 'List manageable database engines')
  Future<Map<String, Object?>> list() async {
    return <String, Object?>{
      'results': kDatabaseEngines.map((e) => e.toJson()).toList(),
    };
  }
}
