import 'dart:convert';
import 'dart:io';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart' show env;
import 'package:gisila_panel/models/models.dart';

/// The host firewall (ufw), for superusers.
///
/// The API never touches the firewall itself: it records a change in
/// `firewall_changes`, and the worker's [FirewallWorker] applies it through
/// `gisila-agent firewall apply`. The agent refuses changes that would cut
/// off SSH or the person making them, and rolls a change back unless it is
/// confirmed in time. The requester's browser confirms it from any page of
/// the panel as soon as it is applied, which proves the panel is still
/// reachable through the new rules.
class FirewallService extends Service {
  Database get _db => db<Database>();

  /// Seconds the requester has to come back to the panel before the agent
  /// puts the old rules back: `FIREWALL_CONFIRM_MINUTES`, 1 to 10, default 5.
  static int get confirmWindow =>
      ((int.tryParse(env['FIREWALL_CONFIRM_MINUTES'] ?? '') ?? 5).clamp(1, 10)) *
      60;

  /// Confirmations are accepted until this long before the agent's own
  /// rollback timer fires, so the worker has time to pass them on.
  static const confirmMargin = 20;

  static const openStatuses = [
    'queued',
    'applying',
    'awaiting_confirmation',
    'confirm_requested',
    'revert_requested',
  ];

  static final _portRe = RegExp(r'^[0-9]{1,5}(:[0-9]{1,5})?$');
  static final _noteRe = RegExp(r'^[A-Za-z0-9 ._:#/@()+-]{0,60}$');

  Future<Map<String, Object?>> overview() async {
    final c = _db.context();
    final stateRows =
        await c.execute('SELECT * FROM firewall_state WHERE id = 1');
    final state = stateRows.isEmpty ? null : stateRows.first.toColumnMap();
    final changes = await c.execute(
      'SELECT f.*, u.email AS requested_by_email FROM firewall_changes f '
      'LEFT JOIN users u ON u.id = f.requested_by ORDER BY f.id DESC LIMIT 20',
    );
    final recent = [for (final r in changes) _changeJson(r.toColumnMap())];
    return {
      ..._decode(state?['state']),
      'refreshedAt': _iso(state?['refreshed_at']),
      'confirmWindow': confirmWindow,
      'open': recent.where((c) => openStatuses.contains(c['status'])).firstOrNull,
      'recent': recent,
    };
  }

  /// The change in progress, if any. Polled from every page of the panel,
  /// so a change is confirmed as soon as its requester is back.
  Future<Map<String, Object?>?> pending() async {
    final rows = await _db.context().execute(
      'SELECT f.*, NULL AS requested_by_email FROM firewall_changes f '
      'WHERE f.status = ANY(\$1::text[]) ORDER BY f.id DESC LIMIT 1',
      parameters: [openStatuses],
    );
    return rows.isEmpty ? null : _changeJson(rows.first.toColumnMap());
  }

  Future<Map<String, Object?>> change(int id) async {
    final rows = await _db.context().execute(
      'SELECT f.*, u.email AS requested_by_email FROM firewall_changes f '
      'LEFT JOIN users u ON u.id = f.requested_by WHERE f.id = \$1',
      parameters: [id],
    );
    if (rows.isEmpty) throw NotFound('Firewall change not found.');
    return _changeJson(rows.first.toColumnMap());
  }

  /// Record a change for the worker. [rule] is required for `add` and
  /// `delete`. [requesterIp] is kept able to connect, and [protectPorts]
  /// are extra ports the panel is reached on.
  Future<Map<String, Object?>> request(
    User actor,
    String op, {
    Map<String, Object?>? rule,
    required String? requesterIp,
    List<int> protectPorts = const [],
  }) async {
    final state = _decode((await _db.context().execute(
            'SELECT state FROM firewall_state WHERE id = 1'))
        .firstOrNull
        ?.toColumnMap()['state']);
    if (state['available'] == false) {
      throw BadRequest(
          '${state['reason'] ?? 'The firewall is not available on this server.'}');
    }
    if (requesterIp == null || InternetAddress.tryParse(requesterIp) == null) {
      // The agent keeps this address able to connect; without it, it could
      // not tell whether a block would cut off the requester.
      throw BadRequest('Could not tell your IP address, so the firewall '
          'cannot be changed safely from this connection.');
    }
    final checked = rule == null
        ? null
        : op == 'web-sources'
            ? rule
            : validateRule(rule);
    final rows = await _db.context().execute(
      'INSERT INTO firewall_changes (op, rule, requested_by, requester_ip, '
      'protect_ports) VALUES (\$1, \$2::jsonb, \$3, \$4, \$5::int[]) '
      'ON CONFLICT DO NOTHING RETURNING id',
      parameters: [
        op,
        checked == null ? null : jsonEncode(checked),
        actor.id,
        requesterIp,
        '{${protectPorts.join(',')}}',
      ],
    );
    if (rows.isEmpty) {
      throw Conflict('Another firewall change is still in progress. Wait '
          'for it to be confirmed or rolled back.');
    }
    return change(rows.first.toColumnMap()['id'] as int);
  }

  /// The requester's browser reached the panel through the new rules.
  Future<Map<String, Object?>> confirm(User actor, int id) async {
    final rows = await _db.context().execute(
      "UPDATE firewall_changes SET status = 'confirm_requested' "
      "WHERE id = \$1 AND requested_by = \$2 AND status = 'awaiting_confirmation' "
      'AND confirm_by > now() RETURNING id',
      parameters: [id, actor.id],
    );
    if (rows.isEmpty) {
      final current = await change(id);
      if (current['requestedBy'] != actor.id) {
        throw Forbidden('Only the person who made a change can confirm it.');
      }
      throw Conflict('This change can no longer be confirmed '
          '(it is ${current['status']}).');
    }
    return change(id);
  }

  /// Put the rules back from before the change, without waiting.
  Future<Map<String, Object?>> revert(int id) async {
    final rows = await _db.context().execute(
      "UPDATE firewall_changes SET status = 'revert_requested' "
      "WHERE id = \$1 AND status = 'awaiting_confirmation' RETURNING id",
      parameters: [id],
    );
    if (rows.isEmpty) {
      final current = await change(id);
      throw Conflict('This change can no longer be reverted '
          '(it is ${current['status']}).');
    }
    return change(id);
  }

  /// Ask the worker to read the firewall status again.
  Future<void> refresh() => _db.context().execute(
        'INSERT INTO firewall_state (id, refresh_requested_at) VALUES (1, now()) '
        'ON CONFLICT (id) DO UPDATE SET refresh_requested_at = now()',
      );

  /// Cloudflare's published ranges (https://www.cloudflare.com/ips/, read
  /// 2026-10-30), for letting only Cloudflare reach the web ports.
  static const cloudflareRanges = [
    '173.245.48.0/20',
    '103.21.244.0/22',
    '103.22.200.0/22',
    '103.31.4.0/22',
    '141.101.64.0/18',
    '108.162.192.0/18',
    '190.93.240.0/20',
    '188.114.96.0/20',
    '197.234.240.0/22',
    '198.41.128.0/17',
    '162.158.0.0/15',
    '104.16.0.0/13',
    '104.24.0.0/14',
    '172.64.0.0/13',
    '131.0.72.0/22',
    '2400:cb00::/32',
    '2606:4700::/32',
    '2803:f800::/32',
    '2405:b500::/32',
    '2405:8100::/32',
    '2a06:98c0::/29',
    '2c0f:f248::/32',
  ];

  static const presets = {'cloudflare': cloudflareRanges};

  /// The most sources the web ports can be limited to (two ufw rules each).
  static const maxWebSources = 100;

  /// The `web-sources` change for a [preset] or [sources] (addresses and
  /// ranges separated by commas, spaces or new lines): empty means
  /// everyone. Throws [BadRequest].
  static Map<String, Object?> validateWebSources(
      {String? sources, String? preset}) {
    final name = preset?.trim().toLowerCase() ?? '';
    final raw = name.isNotEmpty
        ? presets[name] ??
            (throw BadRequest(
                'preset must be one of: ${presets.keys.join(', ')}.'))
        : (sources ?? '').split(RegExp(r'[\s,]+'));
    final out = <String>[];
    for (final s in raw) {
      final from = s.trim();
      if (from.isEmpty) continue;
      if (from.toLowerCase() == 'any') return {'sources': const <String>[]};
      if (!_isSource(from)) {
        throw BadRequest('"$from" is not an IP address or a CIDR range like '
            '203.0.113.0/24.');
      }
      if (!out.contains(from)) out.add(from);
    }
    if (out.length > maxWebSources) {
      throw BadRequest('At most $maxWebSources sources.');
    }
    return {'sources': out, if (name.isNotEmpty) 'preset': name};
  }

  static bool _isSource(String from) {
    final slash = from.indexOf('/');
    final addr =
        InternetAddress.tryParse(slash < 0 ? from : from.substring(0, slash));
    final bits = addr == null ? 0 : addr.rawAddress.length * 8;
    final prefix =
        slash < 0 ? bits : int.tryParse(from.substring(slash + 1)) ?? -1;
    return addr != null && prefix >= 0 && prefix <= bits;
  }

  /// Check a rule's shape; the agent decides whether it is safe. Throws
  /// [BadRequest].
  static Map<String, Object?> validateRule(Map<String, Object?> rule) {
    final action = '${rule['action'] ?? ''}'.toLowerCase();
    if (!const {'allow', 'deny', 'reject', 'limit'}.contains(action)) {
      throw BadRequest('action must be allow, deny, reject or limit.');
    }
    final proto = '${rule['proto'] ?? 'any'}'.toLowerCase();
    if (!const {'tcp', 'udp', 'any'}.contains(proto)) {
      throw BadRequest('proto must be tcp, udp or any.');
    }
    final port = rule['port']?.toString().trim();
    if (port != null && port.isNotEmpty) {
      final parts = port.split(':').map(int.tryParse).toList();
      if (!_portRe.hasMatch(port) ||
          parts.any((p) => p == null || p < 1 || p > 65535) ||
          (parts.length == 2 && parts[1]! <= parts[0]!)) {
        throw BadRequest('port must be 1-65535, or a range like 8000:8100.');
      }
      if (parts.length == 2 && proto == 'any') {
        throw BadRequest('A port range needs proto tcp or udp.');
      }
    }
    final from = '${rule['from'] ?? 'any'}'.trim();
    if (from.isNotEmpty && from.toLowerCase() != 'any' && !_isSource(from)) {
      throw BadRequest('from must be "any", an IP address or a CIDR '
          'range like 203.0.113.0/24.');
    }
    final note = '${rule['note'] ?? ''}'.trim();
    if (!_noteRe.hasMatch(note)) {
      throw BadRequest('The note may only use letters, digits, spaces and '
          '. _ : # / @ ( ) + -');
    }
    return {
      'action': action,
      'proto': proto,
      'port': port == null || port.isEmpty ? null : port,
      'from': from.isEmpty ? 'any' : from,
      if (note.isNotEmpty) 'note': note,
    };
  }

  static Map<String, Object?> _decode(Object? json) => switch (json) {
        Map() => Map<String, Object?>.from(json),
        String() when json.isNotEmpty =>
          Map<String, Object?>.from(jsonDecode(json) as Map),
        _ => <String, Object?>{},
      };

  static String? _iso(Object? t) =>
      t is DateTime ? t.toUtc().toIso8601String() : null;

  static Map<String, Object?> _changeJson(Map<String, Object?> r) => {
        'id': r['id'],
        'op': r['op'],
        'rule': r['rule'] == null ? null : _decode(r['rule']),
        'status': r['status'],
        'error': r['error'],
        'requestedBy': r['requested_by'],
        'requestedByEmail': r['requested_by_email'],
        'requesterIp': r['requester_ip'],
        'confirmBy': _iso(r['confirm_by']),
        'createdAt': _iso(r['created_at']),
        'finishedAt': _iso(r['finished_at']),
      };
}
