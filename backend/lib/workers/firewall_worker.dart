import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/services/firewall_service.dart';

/// Self-driven [Timer] loop that carries out firewall changes recorded by
/// [FirewallService], and keeps `firewall_state` in step with the host.
///
/// It polls the table instead of taking jobs from the Redis queue: the queue
/// runs one job at a time, and a confirmation stuck behind a long build
/// would arrive after the agent had already rolled the change back.
class FirewallWorker {
  FirewallWorker(
    this.database, {
    this.interval = const Duration(seconds: 2),
    Future<Map<String, Object?>> Function(List<String> args)? agent,
  }) : _agent = agent ?? _runAgent;

  final Database database;
  final Duration interval;
  final Future<Map<String, Object?>> Function(List<String> args) _agent;

  /// How often the firewall status is read even when nothing changed, to
  /// pick up rules changed outside the panel.
  static const refreshEvery = Duration(minutes: 1);

  Timer? _timer;
  var _ticking = false;
  var _started = false;

  void start() {
    logger.i('firewall: started (every ${interval.inSeconds}s)');
    _timer = Timer.periodic(interval, (_) => _safeTick());
  }

  void stop() => _timer?.cancel();

  Future<void> _safeTick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await tick();
    } catch (e, st) {
      logger.w('firewall: tick failed: $e', stackTrace: st);
    } finally {
      _ticking = false;
    }
  }

  Future<void> tick() async {
    var changed = false;
    if (!_started) {
      _started = true;
      changed |= await _recover();
    }
    changed |= await _applyQueued();
    changed |= await _settle();
    await _refresh(force: changed);
  }

  Future<List<Map<String, Object?>>> _query(String sql,
          [List<Object?> params = const []]) async =>
      [
        for (final r
            in await database.context().execute(sql, parameters: params))
          r.toColumnMap(),
      ];

  Future<void> _finish(int id, String status, [String? error]) => _query(
        'UPDATE firewall_changes SET status = \$2, error = \$3, '
        'finished_at = now() WHERE id = \$1',
        [id, status, error],
      );

  /// A change left `applying` by a worker that died mid-way: put the old
  /// rules back rather than guess how far it got.
  Future<bool> _recover() async {
    final stuck = await _query(
        "SELECT id FROM firewall_changes WHERE status = 'applying'");
    for (final row in stuck) {
      final id = row['id'] as int;
      await _agent(['firewall', 'rollback', '--change-id', '$id']);
      await _finish(id, 'rolled_back',
          'The worker restarted while applying this change, so it was rolled back.');
    }
    return stuck.isNotEmpty;
  }

  Future<bool> _applyQueued() async {
    final claimed = await _query(
      "UPDATE firewall_changes SET status = 'applying' WHERE id = ("
      "SELECT id FROM firewall_changes WHERE status = 'queued' "
      'ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED) RETURNING *',
    );
    if (claimed.isEmpty) return false;
    final c = claimed.first;
    final id = c['id'] as int;
    final rule = c['rule'];
    final res = await _agent([
      'firewall',
      'apply',
      '--change-id',
      '$id',
      '--op',
      c['op'] as String,
      if (rule != null) ...[
        '--rule',
        rule is String ? rule : jsonEncode(rule),
      ],
      '--keep-ip',
      c['requester_ip'] as String,
      for (final p in (c['protect_ports'] as List?) ?? const [])
        ...['--protect-port', '$p'],
      '--confirm-within',
      '${FirewallService.confirmWindow}',
    ]);
    if (res['ok'] != true) {
      await _finish(id, 'failed', '${res['error'] ?? 'The agent failed.'}');
      return true;
    }
    await _query(
      "UPDATE firewall_changes SET status = 'awaiting_confirmation', "
      'confirm_by = now() + make_interval(secs => \$2) WHERE id = \$1',
      [id, FirewallService.confirmWindow - FirewallService.confirmMargin],
    );
    logger.i('firewall: change #$id applied, waiting for confirmation');
    return true;
  }

  /// Confirmations, reverts and changes nobody confirmed in time.
  Future<bool> _settle() async {
    final rows = await _query(
      'SELECT id, status, confirm_by < now() AS expired FROM firewall_changes '
      "WHERE status IN ('confirm_requested', 'revert_requested', "
      "'awaiting_confirmation')",
    );
    var changed = false;
    for (final row in rows) {
      final id = row['id'] as int;
      switch (row['status']) {
        case 'confirm_requested':
          final res =
              await _agent(['firewall', 'confirm', '--change-id', '$id']);
          if (res['ok'] == true) {
            await _finish(id, 'applied');
          } else {
            await _finish(id, 'rolled_back',
                'It was rolled back before the confirmation arrived.');
          }
          changed = true;
        case 'revert_requested':
          await _agent(['firewall', 'rollback', '--change-id', '$id']);
          await _finish(id, 'rolled_back', 'Reverted from the panel.');
          changed = true;
        case 'awaiting_confirmation' when row['expired'] == true:
          await _agent(['firewall', 'rollback', '--change-id', '$id']);
          await _finish(
              id,
              'rolled_back',
              'Not confirmed in time: your browser could not reach the panel '
                  'through the new rules, so they were rolled back.');
          logger.w('firewall: change #$id not confirmed, rolled back');
          changed = true;
      }
    }
    return changed;
  }

  Future<void> _refresh({required bool force}) async {
    final rows = await _query(
      'SELECT refreshed_at IS NULL OR refreshed_at < now() - make_interval(secs => \$1) '
      'OR refresh_requested_at > refreshed_at AS due FROM firewall_state WHERE id = 1',
      [refreshEvery.inSeconds],
    );
    if (!force && rows.isNotEmpty && rows.first['due'] != true) return;
    final res = await _agent(['firewall', 'status']);
    final state = Map<String, Object?>.of(res)..remove('ok');
    if (res['ok'] != true) {
      state
        ..clear()
        ..addAll({
          'available': false,
          'reason': '${res['error'] ?? 'Could not read the firewall status.'}',
        });
    }
    await _query(
      'INSERT INTO firewall_state (id, state, refreshed_at) '
      'VALUES (1, \$1::jsonb, now()) ON CONFLICT (id) DO UPDATE '
      'SET state = EXCLUDED.state, refreshed_at = now()',
      [jsonEncode(state)],
    );
  }

  /// Run the agent and return its JSON line (the last line of stdout).
  static Future<Map<String, Object?>> _runAgent(List<String> args) async {
    if (hostConfig.agentMode == 'dev') {
      return {
        'ok': false,
        'error': 'The firewall cannot be managed in dev mode.',
      };
    }
    final cmd = buildAgentCmd(args);
    final result = await Process.run(cmd.first, cmd.skip(1).toList(),
        environment: agentEnvironment, includeParentEnvironment: false);
    final lines = const LineSplitter()
        .convert('${result.stdout}')
        .where((l) => l.startsWith('{'))
        .toList();
    if (lines.isNotEmpty) {
      try {
        return Map<String, Object?>.from(jsonDecode(lines.last) as Map);
      } catch (_) {}
    }
    final err = '${result.stderr}'.trim().split('\n').first;
    return {
      'ok': false,
      'error': err.isEmpty ? 'The agent exited ${result.exitCode}.' : err,
    };
  }
}
