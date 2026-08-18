import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';

/// Redis key the latest whole-host snapshot is published under. Read by both
/// the [AlertEvaluator] (system-scope rules) and the `GET /notifications/
/// host-stats` endpoint (so the rule editor can show current usage next to
/// the threshold field).
const hostStatsRedisKey = 'gisila:hoststat:latest';

/// Samples whole-host CPU, memory and root-filesystem usage every [interval]
/// and publishes a JSON snapshot to Redis.
///
/// Unlike [MetricsCollector] (per-app cgroup accounting via `gisila-agent
/// stat`), this needs no privileged agent: `/proc/stat`, `/proc/meminfo` and
/// `df` are all readable by the unprivileged `gisila` service user, so the
/// worker samples the host directly.
class HostStatsSampler {
  HostStatsSampler({this.interval = const Duration(seconds: 20)});

  final Duration interval;
  Timer? _timer;
  var _ticking = false;
  _CpuMark? _lastCpu;

  void start() {
    logger.i('hoststats: sampler started (every ${interval.inSeconds}s)');
    _timer = Timer.periodic(interval, (_) => _safeTick());
    _safeTick();
  }

  void stop() => _timer?.cancel();

  Future<void> _safeTick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await _tick();
    } catch (e, st) {
      logger.w('hoststats: tick failed: $e', stackTrace: st);
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tick() async {
    final cpuPercent = await _sampleCpu();
    final mem = await _sampleMemory();
    final disk = await _sampleDisk();

    final snapshot = <String, Object?>{
      'cpuPercent': cpuPercent,
      'memTotalBytes': mem.totalBytes,
      'memUsedBytes': mem.usedBytes,
      'memPercent': mem.percent,
      'diskTotalBytes': disk.totalBytes,
      'diskUsedBytes': disk.usedBytes,
      'diskPercent': disk.percent,
      'sampledAt': DateTime.now().toUtc().toIso8601String(),
    };

    await RedisClient.instance.setEx(
      hostStatsRedisKey,
      interval.inSeconds * 4,
      jsonEncode(snapshot),
    );
  }

  /// Whole-host CPU percent from the aggregate `cpu ` line in `/proc/stat`,
  /// derived from the delta between two consecutive samples (a single
  /// snapshot only gives cumulative jiffies since boot). Returns null on the
  /// very first tick, once the baseline exists.
  Future<int?> _sampleCpu() async {
    final file = File('/proc/stat');
    if (!await file.exists()) return null;
    final lines = await file.readAsLines();
    final line = lines.firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
    if (line.isEmpty) return null;

    final fields = line
        .substring(3)
        .trim()
        .split(RegExp(r'\s+'))
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    // user nice system idle iowait irq softirq steal [guest guest_nice]
    if (fields.length < 4) return null;
    final idle = fields[3] + (fields.length > 4 ? fields[4] : 0);
    final total = fields.fold<int>(0, (a, b) => a + b);

    final now = _CpuMark(total: total, idle: idle);
    final prev = _lastCpu;
    _lastCpu = now;
    if (prev == null) return null;

    final totalDelta = now.total - prev.total;
    if (totalDelta <= 0) return null;
    final idleDelta = now.idle - prev.idle;
    final busyFraction = (totalDelta - idleDelta) / totalDelta;
    return (busyFraction * 100).round().clamp(0, 100);
  }

  Future<_Sample> _sampleMemory() async {
    final file = File('/proc/meminfo');
    if (!await file.exists()) return const _Sample(totalBytes: 0, usedBytes: 0, percent: null);
    final lines = await file.readAsLines();
    int? totalKb;
    int? availKb;
    for (final line in lines) {
      if (line.startsWith('MemTotal:')) totalKb = _extractKb(line);
      if (line.startsWith('MemAvailable:')) availKb = _extractKb(line);
    }
    if (totalKb == null || totalKb == 0) {
      return const _Sample(totalBytes: 0, usedBytes: 0, percent: null);
    }
    final usedKb = (totalKb - (availKb ?? 0)).clamp(0, totalKb);
    return _Sample(
      totalBytes: totalKb * 1024,
      usedBytes: usedKb * 1024,
      percent: ((usedKb / totalKb) * 100).round().clamp(0, 100),
    );
  }

  int? _extractKb(String line) {
    final match = RegExp(r'(\d+)').firstMatch(line);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Root filesystem usage via `df` (covers whatever [hostConfig.appsRoot]
  /// lives on for a typical single-disk install; multi-volume hosts are a
  /// future enhancement).
  Future<_Sample> _sampleDisk() async {
    try {
      final result = await Process.run('df', ['-k', '--output=size,used', '/']);
      if (result.exitCode != 0) return const _Sample(totalBytes: 0, usedBytes: 0, percent: null);
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length < 2) return const _Sample(totalBytes: 0, usedBytes: 0, percent: null);
      final parts = lines[1].trim().split(RegExp(r'\s+'));
      if (parts.length < 2) return const _Sample(totalBytes: 0, usedBytes: 0, percent: null);
      final totalKb = int.tryParse(parts[0]) ?? 0;
      final usedKb = int.tryParse(parts[1]) ?? 0;
      if (totalKb == 0) return const _Sample(totalBytes: 0, usedBytes: 0, percent: null);
      return _Sample(
        totalBytes: totalKb * 1024,
        usedBytes: usedKb * 1024,
        percent: ((usedKb / totalKb) * 100).round().clamp(0, 100),
      );
    } catch (e) {
      logger.w('hoststats: df sampling failed: $e');
      return const _Sample(totalBytes: 0, usedBytes: 0, percent: null);
    }
  }
}

/// Reads back the latest snapshot [HostStatsSampler] published, or null if
/// none has landed yet (e.g. right after a worker restart).
Future<Map<String, Object?>?> readLatestHostStats() async {
  final raw = await RedisClient.instance.get(hostStatsRedisKey);
  if (raw == null) return null;
  try {
    return jsonDecode(raw) as Map<String, Object?>;
  } catch (_) {
    return null;
  }
}

class _CpuMark {
  const _CpuMark({required this.total, required this.idle});
  final int total;
  final int idle;
}

class _Sample {
  const _Sample({required this.totalBytes, required this.usedBytes, required this.percent});
  final int totalBytes;
  final int usedBytes;
  final int? percent;
}
