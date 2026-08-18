import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';

/// Redis key the mail stack's cached health snapshot is published under.
/// There's only ever one mail stack per host, so unlike services/runtimes
/// below it needs no id suffix.
const mailHealthRedisKey = 'gisila:healthstat:mail';

/// Redis key a [ManagedService]'s or [ApplicationVersion]'s cached health
/// snapshot is published under.
String serviceHealthRedisKey(int serviceId) => 'gisila:healthstat:service:$serviceId';
String runtimeHealthRedisKey(int applicationVersionId) =>
    'gisila:healthstat:runtime:$applicationVersionId';

/// Read back a cached health snapshot, or null if no probe has landed yet
/// (e.g. right after a worker restart) — used by both the health/repair
/// endpoints and [AlertEvaluator].
Future<Map<String, Object?>?> readCachedHealth(String key) async {
  final raw = await RedisClient.instance.get(key);
  if (raw == null) return null;
  try {
    return jsonDecode(raw) as Map<String, Object?>;
  } catch (_) {
    return null;
  }
}

/// Periodically probes the mail stack, every installed [ManagedService], and
/// every installed [ApplicationVersion] (runtime toolchain) for live health —
/// beyond what their lifecycle `status` column tracks, which only reflects
/// "did the last install/start job succeed", not "is it actually up right
/// now" (a crashed daemon, a corrupted binary, a config drift…).
///
/// Mail and Services get automatic restart → reinstall repair (rate-limited
/// by [repairCooldown]) when found unhealthy, by enqueueing the same `repair`
/// action their own lifecycle queues already handle. Runtime versions are
/// cache-only — flagged for a superuser to manually reinstall, never
/// auto-repaired.
class HealthMonitorWorker {
  HealthMonitorWorker(
    this.database, {
    this.interval = const Duration(seconds: 60),
    this.repairCooldown = const Duration(minutes: 15),
  });

  final Database database;
  final Duration interval;
  final Duration repairCooldown;

  Timer? _timer;
  var _ticking = false;

  void start() {
    logger.i('health_monitor: started (every ${interval.inSeconds}s)');
    _timer = Timer.periodic(interval, (_) => _safeTick());
    _safeTick();
  }

  void stop() => _timer?.cancel();

  Future<void> _safeTick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await _checkMail();
      await _checkServices();
      await _checkRuntimes();
    } catch (e, st) {
      logger.w('health_monitor: tick failed', error: e, stackTrace: st);
    } finally {
      _ticking = false;
    }
  }

  // ── Mail ────────────────────────────────────────────────────────────────

  Future<void> _checkMail() async {
    // Nothing to probe until the operator has installed the tooling — same
    // gate the panel's Mail page uses before showing anything else.
    final status = await _probe(['mail', 'status'], resultKey: 'installed');
    if (status?['installed'] != true) return;

    final report = await _probe(['mail', 'health'], resultKey: 'healthy');
    if (report == null) return;
    await _cache(mailHealthRedisKey, report);

    if (report['healthy'] != true && await _cooldownElapsed(mailHealthRedisKey)) {
      logger.i('health_monitor: mail stack unhealthy — enqueueing repair');
      await RedisClient.instance.rpush(
        'gisila:queue:mail',
        jsonEncode({'action': 'repair'}),
      );
      await _markRepairAttempt(mailHealthRedisKey);
    }
  }

  // ── Services ────────────────────────────────────────────────────────────

  Future<void> _checkServices() async {
    // Only services that are (or were) actually installed have anything to
    // probe on the host — `pending`/`installing`/`uninstalling` are mid-job
    // and would just produce noisy false negatives.
    final services = await Query<ManagedService>(ManagedServiceTable.metadata)
        .where(ManagedServiceTable.status.inList(['running', 'failed']))
        .all(database.context());

    for (final svc in services) {
      final cfg = _decodeConfig(svc.config);
      final report = await _probe(
        ['service', 'health', '--type', svc.serviceType, '--config', jsonEncode(cfg)],
        resultKey: 'healthy',
      );
      if (report == null) continue;

      final key = serviceHealthRedisKey(svc.id!);
      await _cache(key, report);

      if (report['healthy'] != true && await _cooldownElapsed(key)) {
        logger.i(
            'health_monitor: service #${svc.id} (${svc.serviceType}) unhealthy — enqueueing repair');
        await RedisClient.instance.rpush(
          'gisila:queue:services',
          jsonEncode({'action': 'repair', 'serviceId': svc.id}),
        );
        await _markRepairAttempt(key);
      }
    }
  }

  // ── Runtimes ────────────────────────────────────────────────────────────

  Future<void> _checkRuntimes() async {
    final versions = await Query<ApplicationVersion>(ApplicationVersionTable.metadata)
        .where(ApplicationVersionTable.status.eq('installed'))
        .all(database.context());
    if (versions.isEmpty) return;

    final apps = await Query<Application>(ApplicationTable.metadata).all(database.context());
    final keyById = {for (final a in apps) a.id!: a.key};

    // One `runtime health` probe per family (the agent reports every
    // installed version of a key in a single call) rather than per version.
    final versionsByKey = <String, List<ApplicationVersion>>{};
    for (final v in versions) {
      final key = keyById[v.applicationId];
      if (key == null) continue;
      versionsByKey.putIfAbsent(key, () => []).add(v);
    }

    for (final entry in versionsByKey.entries) {
      final report = await _probe(['runtime', 'health', '--key', entry.key], resultKey: 'healthy');
      if (report == null) continue;

      final perVersion = (report['versions'] as List?) ?? const [];
      final healthyByVersion = <String, bool>{
        for (final raw in perVersion)
          if (raw is Map)
            (raw['version'] as String?) ?? '': raw['healthy'] == true,
      };

      for (final v in entry.value) {
        // A version the agent no longer reports on (e.g. removed since the
        // panel's last DB sync) has nothing to flag — leave it be rather than
        // guessing.
        final healthy = healthyByVersion[v.version];
        if (healthy == null) continue;
        // No repair enqueue — runtime versions are surfaced only, per the
        // "flag it, let a superuser click Reinstall" design.
        await _cache(runtimeHealthRedisKey(v.id!), {
          'healthy': healthy,
          'version': v.version,
        });
      }
    }
  }

  // ── Cache + cooldown ────────────────────────────────────────────────────

  /// Merge [report] into the cached snapshot at [key], tracking how long the
  /// resource has been continuously unhealthy (cleared as soon as it's seen
  /// healthy again) alongside whatever repair bookkeeping already lives
  /// there.
  Future<void> _cache(String key, Map<String, Object?> report) async {
    final now = DateTime.now().toUtc();
    final prev = await readCachedHealth(key);
    final healthy = report['healthy'] == true;
    final unhealthySince = healthy
        ? null
        : (prev?['unhealthySince'] as String?) ?? now.toIso8601String();

    final snapshot = <String, Object?>{
      ...report,
      'checkedAt': now.toIso8601String(),
      if (unhealthySince != null) 'unhealthySince': unhealthySince,
      if (prev?['lastRepairAt'] != null) 'lastRepairAt': prev!['lastRepairAt'],
    };
    // Keep the cache alive for a few missed ticks so a single failed probe
    // doesn't make the resource appear to vanish from the UI.
    await RedisClient.instance.setEx(key, interval.inSeconds * 6, jsonEncode(snapshot));
  }

  Future<bool> _cooldownElapsed(String key) async {
    final cached = await readCachedHealth(key);
    final lastRepairAt = cached?['lastRepairAt'] as String?;
    if (lastRepairAt == null) return true;
    final last = DateTime.tryParse(lastRepairAt);
    if (last == null) return true;
    return DateTime.now().toUtc().difference(last) >= repairCooldown;
  }

  Future<void> _markRepairAttempt(String key) async {
    final snapshot = Map<String, Object?>.from(await readCachedHealth(key) ?? {});
    snapshot['lastRepairAt'] = DateTime.now().toUtc().toIso8601String();
    await RedisClient.instance.setEx(key, interval.inSeconds * 6, jsonEncode(snapshot));
  }

  // ── Agent probing ───────────────────────────────────────────────────────

  /// Run a read-only agent probe and pull out the JSON line containing
  /// [resultKey]. The agent's `main()` always prints a trailing
  /// `{"ok":true,...}` wrapper line after a command's real output, so a
  /// naive last-line parse would return that instead — scan bottom-up for
  /// the line that actually has the field we want.
  Future<Map<String, Object?>?> _probe(
    List<String> args, {
    required String resultKey,
  }) async {
    if (hostConfig.agentMode == 'dev') return null;
    try {
      final cmd = buildAgentCmd(args);
      final result = await Process.run(cmd.first, cmd.skip(1).toList());
      if (result.exitCode != 0) {
        logger.w('health_monitor: probe ${args.join(' ')} exited ${result.exitCode}: '
            '${result.stderr}');
        return null;
      }
      return _findJsonWith(result.stdout as String? ?? '', resultKey);
    } catch (e) {
      logger.w('health_monitor: probe ${args.join(' ')} failed: $e');
      return null;
    }
  }

  Map<String, Object?>? _findJsonWith(String text, String key) {
    final lines = text.trim().split('\n');
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (!line.startsWith('{') || !line.contains('"$key"')) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, Object?> && decoded.containsKey(key)) {
          return decoded;
        }
      } catch (_) {
        // Not the line we want — keep scanning upward.
      }
    }
    return null;
  }

  Map<String, dynamic> _decodeConfig(String? raw) {
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
