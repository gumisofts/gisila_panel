import 'dart:async';
import 'dart:convert';

import 'package:gisila_orm/gisila.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;
import 'package:postgres/postgres.dart' as pg;
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/services/notification_service.dart';
import 'package:gisila_panel/workers/health_monitor_worker.dart';
import 'package:gisila_panel/workers/host_stats_sampler.dart';

/// Self-driven [Timer] loop that walks every enabled [AlertRule], samples the
/// metric it watches, and fires/resolves [AlertEvent]s through
/// [NotificationCore]. Mirrors the [MetricsCollector] / `BackupScheduler`
/// pattern: no Redis queue, just a periodic tick.
///
/// A rule with no data source available yet (e.g. an app that hasn't been
/// sampled once, or a database whose monitor role isn't provisioned) is
/// silently skipped for that tick rather than treated as a breach — alerting
/// on missing data would be noisier than useful for a self-hosted panel.
class AlertEvaluator {
  AlertEvaluator(this.database, {this.interval = const Duration(seconds: 30)});

  final Database database;
  final Duration interval;

  Timer? _timer;
  var _ticking = false;

  NotificationCore get _core => NotificationCore(database);

  void start() {
    logger.i('alerts: evaluator started (every ${interval.inSeconds}s)');
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
      logger.w('alerts: tick failed: $e', stackTrace: st);
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tick() async {
    final rules = await _core.listEnabledRules();
    for (final rule in rules) {
      try {
        await _evaluateRule(rule);
      } catch (e, st) {
        logger.w('alerts: rule ${rule.id} evaluation failed: $e', stackTrace: st);
      }
    }
  }

  Future<void> _evaluateRule(AlertRule rule) async {
    final observation = await _observe(rule);
    if (observation == null) return; // no data yet — skip this tick

    final breaching = _breaches(rule, observation);
    final openEvent = await _core.findOpenEvent(rule.id!);

    if (breaching) {
      // Already firing: wait for it to resolve before alerting again — never
      // spam on every tick while the condition persists.
      if (openEvent != null) return;

      final last = rule.lastTriggeredAt;
      if (last != null) {
        final cooldown = Duration(minutes: rule.cooldownMinutes ?? 15);
        if (DateTime.now().toUtc().difference(last) < cooldown) return;
      }

      await _core.fireEvent(
        rule,
        observedPercent: observation.percent,
        message: _messageFor(rule, observation),
      );
    } else if (openEvent != null) {
      await _core.resolveEvent(openEvent, rule);
    }
  }

  bool _breaches(AlertRule rule, _Observation obs) {
    if (rule.metric == 'status_down') return obs.isDown;
    final percent = obs.percent;
    final threshold = rule.thresholdPercent;
    if (percent == null || threshold == null) return false;
    return rule.comparison == 'lte' ? percent <= threshold : percent >= threshold;
  }

  String _messageFor(AlertRule rule, _Observation obs) {
    final target = switch (rule.scope) {
      'system' => 'The server',
      'app' => 'App ${obs.targetLabel ?? '#${rule.appId}'}',
      'postgres' => 'Postgres instance ${obs.targetLabel ?? '#${rule.postgresInstanceId}'}',
      'mongo' => 'Mongo instance ${obs.targetLabel ?? '#${rule.mongoInstanceId}'}',
      'mail' => 'The mail stack',
      'service' => 'Service ${obs.targetLabel ?? '#${rule.managedServiceId}'}',
      'runtime' => 'Runtime ${obs.targetLabel ?? '#${rule.applicationId}'}',
      _ => 'A resource',
    };
    if (rule.metric == 'status_down') return '$target is down.';
    final metricLabel = switch (rule.metric) {
      'cpu_percent' => 'CPU usage',
      'memory_percent' => 'memory usage',
      'disk_percent' => 'disk usage',
      'connections_percent' => 'connection usage',
      _ => rule.metric,
    };
    return '$target $metricLabel is at ${obs.percent}% '
        '(threshold ${rule.thresholdPercent}%).';
  }

  // ── Sampling ─────────────────────────────────────────────────────────────

  Future<_Observation?> _observe(AlertRule rule) => switch (rule.scope) {
        'system' => _observeSystem(rule),
        'app' => _observeApp(rule),
        'postgres' => _observePostgres(rule),
        'mongo' => _observeMongo(rule),
        'mail' => _observeMail(rule),
        'service' => _observeService(rule),
        'runtime' => _observeRuntime(rule),
        _ => Future.value(null),
      };

  Future<_Observation?> _observeSystem(AlertRule rule) async {
    final snapshot = await readLatestHostStats();
    if (snapshot == null) return null;
    final percent = switch (rule.metric) {
      'cpu_percent' => snapshot['cpuPercent'] as int?,
      'memory_percent' => snapshot['memPercent'] as int?,
      'disk_percent' => snapshot['diskPercent'] as int?,
      _ => null,
    };
    if (percent == null && rule.metric != 'status_down') return null;
    return _Observation(percent: percent, isDown: false, targetLabel: null);
  }

  Future<_Observation?> _observeApp(AlertRule rule) async {
    final appId = rule.appId;
    if (appId == null) return null;
    final app = await Query<App>(AppTable.metadata)
        .where(AppTable.id.eq(appId))
        .first(database.context());
    if (app == null) return null;

    if (rule.metric == 'status_down') {
      final down = app.status == 'crashed' || app.status == 'failed' || app.status == 'stopped';
      return _Observation(percent: null, isDown: down, targetLabel: app.name);
    }

    final sample = await Query<MetricSample>(MetricSampleTable.metadata)
        .where(MetricSampleTable.appId.eq(appId))
        .orderBy(MetricSampleTable.sampledAt, desc: true)
        .first(database.context());
    if (sample == null) return null;

    // Stale samples (app stopped a while ago, sampler caught up already)
    // shouldn't drive an alert — treat as "no current data".
    if (DateTime.now().toUtc().difference(sample.sampledAt) > const Duration(minutes: 5)) {
      return null;
    }

    final cpuQuota = app.cpuQuotaPercent ?? 0;
    final memLimitMb = app.memoryMbLimit ?? 0;
    final sampleCpuPercent = sample.cpuPercent ?? 0;
    final sampleMemBytes = sample.memBytes ?? 0;
    final percent = switch (rule.metric) {
      // sample.cpuPercent is basis points relative to a single core;
      // app.cpuQuotaPercent is the systemd CPUQuota configured for the app —
      // both are "percent of one core", so the ratio is the percent of quota.
      'cpu_percent' => (cpuQuota > 0)
          ? ((sampleCpuPercent / 100) / cpuQuota * 100).round().clamp(0, 1000)
          : null,
      'memory_percent' => (memLimitMb > 0)
          ? (sampleMemBytes / (memLimitMb * 1024 * 1024) * 100).round().clamp(0, 1000)
          : null,
      _ => null,
    };
    if (percent == null) return null;
    return _Observation(percent: percent, isDown: false, targetLabel: app.name);
  }

  Future<_Observation?> _observePostgres(AlertRule rule) async {
    final id = rule.postgresInstanceId;
    if (id == null) return null;
    final inst = await Query<PostgresInstance>(PostgresInstanceTable.metadata)
        .where(PostgresInstanceTable.id.eq(id))
        .first(database.context());
    if (inst == null) return null;

    if (rule.metric == 'status_down') {
      return _Observation(percent: null, isDown: inst.status != 'running', targetLabel: inst.displayName);
    }
    if (inst.status != 'running') return null;

    if (rule.metric == 'cpu_percent') {
      final raw = await RedisClient.instance.get('gisila:pgstat:$id');
      if (raw == null) return null;
      try {
        final snapshot = jsonDecode(raw) as Map<String, Object?>;
        final basisPoints = (snapshot['cpuPercent'] as num?)?.toInt();
        if (basisPoints == null) return null;
        return _Observation(
          percent: (basisPoints / 100).round().clamp(0, 1000),
          isDown: false,
          targetLabel: inst.displayName,
        );
      } catch (_) {
        return null;
      }
    }

    if (rule.metric == 'connections_percent') {
      final percent = await _pgConnectionsPercent(inst);
      if (percent == null) return null;
      return _Observation(percent: percent, isDown: false, targetLabel: inst.displayName);
    }

    return null; // memory_percent / disk_percent not sampled for db instances yet
  }

  Future<int?> _pgConnectionsPercent(PostgresInstance inst) async {
    if (inst.monitorPassword == null || inst.monitorPassword!.isEmpty) return null;
    pg.Connection? conn;
    try {
      conn = await pg.Connection.open(
        pg.Endpoint(
          host: '127.0.0.1',
          port: inst.port,
          database: 'postgres',
          username: 'gisila_monitor',
          password: inst.monitorPassword,
        ),
        settings: pg.ConnectionSettings(
          sslMode: pg.SslMode.disable,
          connectTimeout: const Duration(seconds: 3),
          queryTimeout: const Duration(seconds: 5),
        ),
      );
      final activity = (await conn.execute(
        "SELECT count(*) AS total FROM pg_stat_activity WHERE backend_type='client backend'",
      ))
          .first
          .toColumnMap();
      final maxConnRow = (await conn.execute(
        "SELECT setting::int AS v FROM pg_settings WHERE name='max_connections'",
      ))
          .first
          .toColumnMap();
      final total = _toInt(activity['total']);
      final max = _toInt(maxConnRow['v']);
      if (max <= 0) return null;
      return ((total / max) * 100).round().clamp(0, 100);
    } catch (e) {
      logger.d('alerts: postgres connections sample failed for instance ${inst.id}: $e');
      return null;
    } finally {
      await conn?.close();
    }
  }

  Future<_Observation?> _observeMongo(AlertRule rule) async {
    final id = rule.mongoInstanceId;
    if (id == null) return null;
    final inst = await Query<MongoInstance>(MongoInstanceTable.metadata)
        .where(MongoInstanceTable.id.eq(id))
        .first(database.context());
    if (inst == null) return null;

    if (rule.metric == 'status_down') {
      return _Observation(percent: null, isDown: inst.status != 'running', targetLabel: inst.displayName);
    }
    if (inst.status != 'running') return null;

    if (rule.metric == 'connections_percent') {
      final percent = await _mongoConnectionsPercent(inst);
      if (percent == null) return null;
      return _Observation(percent: percent, isDown: false, targetLabel: inst.displayName);
    }

    return null; // cpu_percent / memory_percent / disk_percent not sampled for Mongo yet
  }

  Future<int?> _mongoConnectionsPercent(MongoInstance inst) async {
    if (inst.monitorPassword == null || inst.monitorPassword!.isEmpty) return null;
    mongo.Db? conn;
    try {
      final uri =
          'mongodb://gisila_monitor:${inst.monitorPassword}@127.0.0.1:${inst.port}/admin?authSource=admin';
      conn = await mongo.Db.create(uri);
      await conn.open();
      final status = await conn.runCommand({'serverStatus': 1});
      final connections = (status['connections'] as Map?) ?? const {};
      final current = _toInt(connections['current']);
      final available = _toInt(connections['available']);
      final max = current + available;
      if (max <= 0) return null;
      return ((current / max) * 100).round().clamp(0, 100);
    } catch (e) {
      logger.d('alerts: mongo connections sample failed for instance ${inst.id}: $e');
      return null;
    } finally {
      await conn?.close();
    }
  }

  /// The mail stack is a system-wide singleton — no target to look up, just
  /// the cached health snapshot [HealthMonitorWorker] publishes.
  Future<_Observation?> _observeMail(AlertRule rule) async {
    if (rule.metric != 'status_down') return null; // nothing else sampled yet
    final cached = await readCachedHealth(mailHealthRedisKey);
    if (cached == null) return null; // no probe has landed yet
    return _Observation(percent: null, isDown: cached['healthy'] != true, targetLabel: null);
  }

  Future<_Observation?> _observeService(AlertRule rule) async {
    final id = rule.managedServiceId;
    if (id == null) return null;
    final svc = await Query<ManagedService>(ManagedServiceTable.metadata)
        .where(ManagedServiceTable.id.eq(id))
        .first(database.context());
    if (svc == null) return null;
    if (rule.metric != 'status_down') return null; // nothing else sampled yet

    final cached = await readCachedHealth(serviceHealthRedisKey(id));
    if (cached == null) return null; // no probe has landed yet
    return _Observation(
      percent: null,
      isDown: cached['healthy'] != true,
      targetLabel: svc.displayName,
    );
  }

  /// Runtime alerts are per-family (not per-version, see the schema comment
  /// on `AlertRule.application`) — down when *any* installed version's
  /// cached probe reports unhealthy, since a broken toolchain version still
  /// needs a superuser's attention even if a sibling version works fine.
  Future<_Observation?> _observeRuntime(AlertRule rule) async {
    final id = rule.applicationId;
    if (id == null) return null;
    final app = await Query<Application>(ApplicationTable.metadata)
        .where(ApplicationTable.id.eq(id))
        .first(database.context());
    if (app == null) return null;
    if (rule.metric != 'status_down') return null; // nothing else sampled yet

    final versions = await Query<ApplicationVersion>(ApplicationVersionTable.metadata)
        .where(ApplicationVersionTable.applicationId.eq(id))
        .where(ApplicationVersionTable.status.eq('installed'))
        .all(database.context());
    if (versions.isEmpty) return null; // nothing installed yet — no data

    var anyChecked = false;
    var anyUnhealthy = false;
    for (final v in versions) {
      final cached = await readCachedHealth(runtimeHealthRedisKey(v.id!));
      if (cached == null) continue;
      anyChecked = true;
      if (cached['healthy'] != true) anyUnhealthy = true;
    }
    if (!anyChecked) return null; // no probe has landed yet

    return _Observation(percent: null, isDown: anyUnhealthy, targetLabel: app.displayName);
  }

  static int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

class _Observation {
  const _Observation({required this.percent, required this.isDown, required this.targetLabel});
  final int? percent;
  final bool isDown;
  final String? targetLabel;
}
