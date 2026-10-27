import 'package:gisila/gisila.dart' show HttpException;
import 'package:gisila_orm/gisila.dart';

/// A team's resource quota (null = unlimited) and what its apps use now.
class TeamQuota {
  const TeamQuota({
    this.maxApps,
    this.maxMemoryMb,
    this.maxCpuPercent,
    this.apps = 0,
    this.memoryMb = 0,
    this.cpuPercent = 0,
  });

  final int? maxApps;
  final int? maxMemoryMb;
  final int? maxCpuPercent;
  final int apps;
  final int memoryMb;
  final int cpuPercent;

  Map<String, Object?> toJson() => <String, Object?>{
        'maxApps': maxApps,
        'maxMemoryMb': maxMemoryMb,
        'maxCpuPercent': maxCpuPercent,
        'usage': <String, Object?>{
          'apps': apps,
          'memoryMb': memoryMb,
          'cpuPercent': cpuPercent,
        },
      };
}

/// Reads and enforces per-team quotas (columns on `teams`, see migration
/// 20261028_team_quotas). Plain SQL: the generated `Team` model doesn't
/// carry these columns.
class TeamQuotas {
  const TeamQuotas(this._db);

  final Database _db;

  /// [teamId]'s quota and current usage, leaving out [excludeAppId].
  Future<TeamQuota> load(int teamId, {int? excludeAppId}) async {
    final c = _db.context();
    final limits = await c.execute(
      'SELECT max_apps, max_memory_mb, max_cpu_percent FROM teams '
      'WHERE id = \$1',
      parameters: [teamId],
    );
    final usage = await c.execute(
      'SELECT count(*)::int, coalesce(sum(a.memory_mb_limit), 0)::int, '
      'coalesce(sum(a.cpu_quota_percent), 0)::int '
      'FROM apps a JOIN projects p ON p.id = a.project_id '
      'WHERE p.team_id = \$1 AND a.id <> \$2',
      parameters: [teamId, excludeAppId ?? -1],
    );
    final List<Object?> l =
        limits.isEmpty ? const [null, null, null] : limits.first;
    final u = usage.first;
    return TeamQuota(
      maxApps: l[0] as int?,
      maxMemoryMb: l[1] as int?,
      maxCpuPercent: l[2] as int?,
      apps: u[0] as int,
      memoryMb: u[1] as int,
      cpuPercent: u[2] as int,
    );
  }

  /// Throws a 409 when adding [apps] apps using [memoryMb] and [cpuPercent]
  /// to [teamId] (on top of its apps other than [excludeAppId]) would go
  /// over a quota.
  Future<void> check(
    int teamId, {
    int apps = 0,
    required int memoryMb,
    required int cpuPercent,
    int? excludeAppId,
  }) async {
    final q = await load(teamId, excludeAppId: excludeAppId);
    final problems = <String>[
      if (q.maxApps case final max? when q.apps + apps > max)
        'at most $max apps (it has ${q.apps})',
      if (q.maxMemoryMb case final max? when q.memoryMb + memoryMb > max)
        'at most $max MB of memory in total '
            '(${max - q.memoryMb} MB left)',
      if (q.maxCpuPercent case final max? when q.cpuPercent + cpuPercent > max)
        'at most $max% CPU in total (${max - q.cpuPercent}% left)',
    ];
    if (problems.isEmpty) return;
    throw HttpException(
      409,
      'This team may use ${problems.join(', ')}. Lower the limits, remove '
      'an app, or ask an administrator to raise the quota.',
      code: 'team_quota_exceeded',
    );
  }

  /// Sets [teamId]'s quota; null clears a limit.
  Future<void> set(int teamId,
      {int? maxApps, int? maxMemoryMb, int? maxCpuPercent}) async {
    await _db.context().execute(
      'UPDATE teams SET max_apps = \$1, max_memory_mb = \$2, '
      'max_cpu_percent = \$3 WHERE id = \$4',
      parameters: [maxApps, maxMemoryMb, maxCpuPercent, teamId],
    );
  }
}
