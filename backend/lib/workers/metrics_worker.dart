import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';

/// Periodically samples per-app CPU / memory usage from the host and writes
/// rows into `metric_samples`, which the panel's Metrics tab reads back.
///
/// Unlike the queue workers, this is a self-driven [Timer] loop: on every tick
/// it asks the agent for each running app's resource usage (`gisila-agent stat`)
/// and stores a sample. CPU percent is derived from the delta of the cumulative
/// CPU-time counter between two consecutive samples.
class MetricsCollector {
  MetricsCollector(
    this.database, {
    this.interval = const Duration(seconds: 20),
    this.retention = const Duration(hours: 24),
  });

  final Database database;
  final Duration interval;
  final Duration retention;

  /// Last cumulative CPU nanoseconds + wall-clock time, keyed by app id, used to
  /// compute the CPU percentage from the counter delta.
  final Map<int, _CpuMark> _last = {};

  /// Same as [_last] but for Postgres instances (keyed by instance id).
  final Map<int, _CpuMark> _pgLast = {};

  Timer? _timer;
  var _ticking = false;

  void start() {
    if (hostConfig.agentMode == 'dev') {
      logger.i('metrics: collector disabled in dev mode (no systemd/cgroups)');
      return;
    }
    logger.i('metrics: collector started (every ${interval.inSeconds}s)');
    _timer = Timer.periodic(interval, (_) => _safeTick());
    _safeTick(); // run an initial sample immediately
  }

  void stop() => _timer?.cancel();

  Future<void> _safeTick() async {
    if (_ticking) return; // never overlap ticks
    _ticking = true;
    try {
      await _tick();
    } catch (e, st) {
      logger.w('metrics: tick failed: $e', stackTrace: st);
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tick() async {
    final apps = await Query<App>(AppTable.metadata)
        .where(AppTable.status.eq('running'))
        .all(database.context());

    final activeIds = <int>{};
    for (final app in apps) {
      final user = app.linuxUser;
      if (app.id == null || user == null) continue;
      activeIds.add(app.id!);
      try {
        await _sampleApp(app.id!, user);
      } catch (e) {
        logger.w('metrics: sampling app ${app.id} failed: $e');
      }
    }

    // Forget CPU marks for apps that are no longer running so a later restart
    // starts from a fresh baseline rather than a stale (huge) delta.
    _last.removeWhere((id, _) => !activeIds.contains(id));

    await _samplePgInstances();
    await _prune();
  }

  /// Sample host CPU/RAM for each running Postgres instance and stash the latest
  /// snapshot in Redis (`gisila:pgstat:<id>`) for the metrics endpoint to read.
  /// Connection/query stats are read directly by the API; only host-level
  /// resource usage needs the privileged agent, hence this worker path.
  Future<void> _samplePgInstances() async {
    final instances = await Query<PostgresInstance>(
      PostgresInstanceTable.metadata,
    ).where(PostgresInstanceTable.status.eq('running')).all(database.context());

    final activeIds = <int>{};
    for (final inst in instances) {
      if (inst.id == null) continue;
      activeIds.add(inst.id!);
      try {
        final unit = 'postgresql@${inst.version}-main.service';
        final stat = await _agentStat(['stat', '--unit', unit]);
        if (stat == null) continue;
        final memBytes = (stat['memBytes'] as num?)?.toInt() ?? 0;
        final cpuNsec = (stat['cpuUsageNsec'] as num?)?.toInt() ?? 0;
        final now = DateTime.now().toUtc();

        var cpuBasisPoints = 0;
        final prev = _pgLast[inst.id!];
        if (prev != null && cpuNsec >= prev.cpuNsec) {
          final wallNsec = now.difference(prev.at).inMicroseconds * 1000;
          if (wallNsec > 0) {
            cpuBasisPoints =
                ((cpuNsec - prev.cpuNsec) / wallNsec * 10000).round().clamp(0, 1000000);
          }
        }
        _pgLast[inst.id!] = _CpuMark(cpuNsec, now);

        await RedisClient.instance.setEx(
          'gisila:pgstat:${inst.id}',
          interval.inSeconds * 4,
          jsonEncode({
            'cpuPercent': cpuBasisPoints,
            'memBytes': memBytes,
            'sampledAt': now.toIso8601String(),
          }),
        );
      } catch (e) {
        logger.w('metrics: sampling pg instance ${inst.id} failed: $e');
      }
    }
    _pgLast.removeWhere((id, _) => !activeIds.contains(id));
  }

  Future<void> _sampleApp(int appId, String linuxUser) async {
    final stat = await _agentStat(['stat', '--user', linuxUser]);
    if (stat == null) return;

    final memBytes = (stat['memBytes'] as num?)?.toInt() ?? 0;
    final cpuNsec = (stat['cpuUsageNsec'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().toUtc();

    // CPU percent in basis points (value/100 = percent). Relative to a single
    // core, so multi-process apps can legitimately exceed 100%.
    var cpuBasisPoints = 0;
    final prev = _last[appId];
    if (prev != null && cpuNsec >= prev.cpuNsec) {
      final wallNsec = now.difference(prev.at).inMicroseconds * 1000;
      if (wallNsec > 0) {
        final fraction = (cpuNsec - prev.cpuNsec) / wallNsec;
        cpuBasisPoints = (fraction * 10000).round().clamp(0, 1000000);
      }
    }
    _last[appId] = _CpuMark(cpuNsec, now);

    await Query<MetricSample>(MetricSampleTable.metadata).insert(<String, Object?>{
      'appId': appId,
      'cpuPercent': cpuBasisPoints,
      'memBytes': memBytes,
      'rssBytes': memBytes,
      'sampledAt': now.toIso8601String(),
    }).run(database.context());
  }

  /// Delete samples older than [retention] so the table stays bounded.
  Future<void> _prune() async {
    final cutoff = DateTime.now().toUtc().subtract(retention);
    try {
      await Query<MetricSample>(MetricSampleTable.metadata)
          .where(MetricSampleTable.sampledAt.lt(cutoff))
          .delete()
          .run(database.context());
    } catch (e) {
      logger.w('metrics: prune failed: $e');
    }
  }

  /// Run `gisila-agent stat …` and parse the JSON line it prints.
  Future<Map<String, Object?>?> _agentStat(List<String> args) async {
    final cmd = buildAgentCmd(args);
    final result = await Process.run(cmd.first, cmd.skip(1).toList());
    if (result.exitCode != 0) return null;
    // The agent may print info lines before the JSON; scan from the end for the
    // line carrying the metrics object.
    final lines = (result.stdout as String).split('\n');
    for (final line in lines.reversed) {
      final t = line.trim();
      if (t.startsWith('{') && t.contains('memBytes')) {
        try {
          return jsonDecode(t) as Map<String, Object?>;
        } catch (_) {/* keep scanning */}
      }
    }
    return null;
  }
}

class _CpuMark {
  _CpuMark(this.cpuNsec, this.at);
  final int cpuNsec;
  final DateTime at;
}
