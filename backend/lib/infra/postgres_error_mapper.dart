import 'package:gisila/gisila.dart';
import 'package:gisila_orm/gisila.dart' hide PostgresErrorMapper;

/// Translates PostgreSQL constraint violations rethrown by `gisila_orm` as
/// [PostgresException]s into well-typed [HttpException]s. The framework's
/// `gisilaErrorMiddleware` then renders them as JSON envelopes.
class PostgresDbErrorMapper extends DbErrorMapper {
  const PostgresDbErrorMapper();

  @override
  HttpException? map(Object error, StackTrace stack) {
    if (error is PostgresUniqueViolationException) {
      return Conflict(
        _detailFor(error) ?? 'A record with this value already exists.',
        code: 'unique_violation',
      );
    }
    if (error is PostgresForeignKeyViolationException) {
      return BadRequest(
        _detailFor(error) ?? 'Foreign key violation.',
        code: 'foreign_key_violation',
      );
    }
    if (error is PostgresNotNullViolationException) {
      return BadRequest(
        _detailFor(error) ?? 'A required field was null.',
        code: 'not_null_violation',
      );
    }
    if (error is PostgresCheckViolationException) {
      return BadRequest(
        _detailFor(error) ?? 'Check constraint violation.',
        code: 'check_violation',
      );
    }
    return null;
  }

  String? _detailFor(PostgresException e) {
    final detail = e.details?['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    return null;
  }
}
