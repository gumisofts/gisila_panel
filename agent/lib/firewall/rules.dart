import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A host firewall rule as the panel manages it: inbound only, to any local
/// address, from one source. ufw can express more (outbound, routed,
/// interface and app-profile rules); those are listed as [simple] = false and
/// never changed by the panel.
class FwRule {
  FwRule({
    required this.action,
    required this.proto,
    required this.port,
    required this.from,
    this.comment = '',
    this.families = const {'v4', 'v6'},
    this.simple = true,
    this.raw,
  });

  /// allow | deny | reject | limit
  final String action;

  /// tcp | udp | any
  final String proto;

  /// `22`, `8000:8100`, or null for every port.
  final String? port;

  /// `any`, or an address / CIDR (normalised, e.g. `10.0.0.0/8`).
  final String from;
  final String comment;

  /// Which of ufw's IPv4 / IPv6 tables hold the rule.
  final Set<String> families;
  final bool simple;
  final String? raw;

  static const actions = {'allow', 'deny', 'reject', 'limit'};
  static const protos = {'tcp', 'udp', 'any'};

  /// Every rule the panel adds carries this comment prefix; only those can
  /// be removed from the panel.
  static const panelComment = 'gisila-panel';

  /// The comment on the SSH / web rules added when the panel turns the
  /// firewall on.
  static const baseComment = 'gisila-base';

  /// The comment on the rules that let only some sources reach the web
  /// ports, set as a whole with the `web-sources` change.
  static const webComment = 'gisila-web';

  static final _portRe = RegExp(r'^([0-9]{1,5})(?::([0-9]{1,5}))?$');
  static final _noteRe = RegExp(r'^[A-Za-z0-9 ._:#/@()+-]{0,60}$');

  String get origin => !simple
      ? 'other'
      : comment.startsWith(panelComment)
          ? 'panel'
          : comment.startsWith(baseComment)
              ? 'base'
              : comment.startsWith(webComment)
                  ? 'web'
                  : 'other';

  bool get blocks => action == 'deny' || action == 'reject';

  /// The port range as [lo, hi], or null for every port.
  (int, int)? get range => portRange(port);

  /// Same rule, ignoring comment and families.
  bool sameAs(FwRule o) =>
      action == o.action && proto == o.proto && port == o.port && from == o.from;

  Map<String, Object?> toJson() => {
        'action': action,
        'proto': proto,
        'port': port,
        'from': from,
        'comment': comment,
        'families': families.toList()..sort(),
        'origin': origin,
        if (raw != null) 'raw': raw,
      };

  /// A rule the panel was asked to add or remove. Throws [FormatException]
  /// with a message fit for the user.
  factory FwRule.request(Map<String, Object?> json) {
    final action = '${json['action'] ?? ''}'.toLowerCase();
    if (!actions.contains(action)) {
      throw const FormatException('action must be allow, deny, reject or limit');
    }
    final proto = '${json['proto'] ?? 'any'}'.toLowerCase();
    if (!protos.contains(proto)) {
      throw const FormatException('proto must be tcp, udp or any');
    }
    final rawPort = json['port']?.toString().trim();
    final port = rawPort == null || rawPort.isEmpty ? null : rawPort;
    final range = portRange(port);
    if (port != null && range == null) {
      throw const FormatException(
          'port must be a port (1-65535) or a range like 8000:8100');
    }
    if (range != null && range.$1 != range.$2 && proto == 'any') {
      throw const FormatException('a port range needs proto tcp or udp');
    }
    if (action == 'limit' && (port == null || proto == 'udp')) {
      throw const FormatException('limit needs a tcp port');
    }
    final from = normaliseSource('${json['from'] ?? 'any'}');
    final note = '${json['note'] ?? ''}'.trim();
    if (!_noteRe.hasMatch(note)) {
      throw const FormatException(
          'note may only use letters, digits, spaces and . _ : # / @ ( ) + -');
    }
    return FwRule(
      action: action,
      proto: proto,
      port: port,
      from: from,
      comment: note.isEmpty ? panelComment : '$panelComment: $note',
    );
  }

  /// `[lo, hi]` for `22` or `8000:8100`; null for no port or a bad value.
  static (int, int)? portRange(String? port) {
    if (port == null) return null;
    final m = _portRe.firstMatch(port);
    if (m == null) return null;
    final lo = int.parse(m.group(1)!);
    final hi = m.group(2) == null ? lo : int.parse(m.group(2)!);
    if (lo < 1 || hi > 65535 || hi < lo) return null;
    return (lo, hi);
  }

  /// Whether the rule applies to [port].
  bool coversPort(int port) {
    final r = range;
    return r == null || (r.$1 <= port && port <= r.$2);
  }

  /// Whether the rule applies to TCP traffic to [port].
  bool coversTcp(int port) => proto != 'udp' && coversPort(port);

  /// Whether the rule's source includes [ip].
  bool fromIncludes(InternetAddress ip) =>
      from == 'any' || Cidr.parse(from).contains(ip);

  /// The `ufw` arguments that add this rule (`prepend` puts blocking rules
  /// ahead of the allows, since ufw stops at the first rule that matches).
  List<String> addArgs() => [
        if (blocks) 'prepend',
        ..._spec(),
        'comment',
        comment,
      ];

  List<String> deleteArgs() => ['delete', ..._spec()];

  List<String> _spec() => [
        action,
        if (proto != 'any') ...['proto', proto],
        'from',
        from,
        'to',
        'any',
        if (port != null) ...['port', port!],
      ];
}

/// The `{"sources": [...]}` of a `web-sources` change: normalised and
/// deduplicated, and empty for everyone. Throws [FormatException].
List<String> parseWebSources(String rule) {
  final json = jsonDecode(rule);
  final list = json is Map ? json['sources'] : null;
  if (list is! List) {
    throw const FormatException('--rule needs a "sources" list');
  }
  final out = {for (final s in list) normaliseSource('$s')};
  if (out.contains('any')) return const [];
  return out.toList()..sort();
}

/// The sources the web ports are limited to, from the `gisila-web` rules;
/// empty when they are open to everyone.
List<String> webSources(List<FwRule> live) => {
      for (final r in live)
        if (r.origin == 'web') r.from,
    }.toList()
      ..sort();

/// A rule that would still let everyone in on one of [ports] once they are
/// limited to [sources], which would make the limit pointless. Only the
/// panel's own base rules are swapped out.
String? openWebRule(List<FwRule> live, List<String> sources, Set<int> ports) {
  if (sources.isEmpty) return null;
  for (final r in live) {
    if (!r.simple || r.blocks || r.from != 'any' || r.origin == 'base') {
      continue;
    }
    for (final p in ports) {
      if (r.coversTcp(p)) {
        return 'Another rule (${r.action} ${r.port ?? 'every port'} from '
            'anywhere) still lets everyone in on port $p. Remove it first.';
      }
    }
  }
  return null;
}

/// The ufw commands that let only [sources] reach [ports] over TCP, or
/// everyone when it is empty. New rules go in before old ones come out, so
/// the ports are never closed in between.
List<List<String>> webSourcesCommands(
    List<FwRule> live, List<String> sources, Set<int> ports) {
  String name(int p) => p == 80 ? 'http' : p == 443 ? 'https' : '$p';
  final wanted = [
    for (final p in ports.toList()..sort())
      for (final from in sources.isEmpty ? const ['any'] : sources)
        FwRule(
          action: 'allow',
          proto: 'tcp',
          port: '$p',
          from: from,
          comment: sources.isEmpty
              ? '${FwRule.baseComment}: ${name(p)}'
              : '${FwRule.webComment}: ${name(p)}',
        ),
  ];
  final current = [
    for (final r in live)
      if (r.simple &&
          (r.origin == 'web' || r.origin == 'base') &&
          ports.any((p) => r.port == '$p'))
        r,
  ];
  return [
    for (final w in wanted)
      if (!current.any((c) => c.sameAs(w) && c.origin == w.origin))
        w.addArgs(),
    for (final c in current)
      if (!wanted.any((w) => w.sameAs(c) && w.origin == c.origin))
        c.deleteArgs(),
  ];
}

/// `any`, or the canonical text of an address / CIDR. Throws
/// [FormatException].
String normaliseSource(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty || s == 'any' || s == 'anywhere') return 'any';
  final c = Cidr.parse(s);
  if (c.prefix == 0) return 'any';
  return c.toString();
}

/// An IPv4 or IPv6 network.
class Cidr {
  Cidr._(this.bytes, this.prefix);

  final List<int> bytes;
  final int prefix;

  bool get isV6 => bytes.length == 16;

  factory Cidr.parse(String s) {
    final slash = s.indexOf('/');
    final addr = InternetAddress.tryParse(slash < 0 ? s : s.substring(0, slash));
    if (addr == null || s.contains('%')) {
      throw FormatException('"$s" is not an IP address or CIDR');
    }
    final bits = addr.rawAddress.length * 8;
    final prefix = slash < 0 ? bits : int.tryParse(s.substring(slash + 1));
    if (prefix == null || prefix < 0 || prefix > bits) {
      throw FormatException('"$s" has a bad prefix length');
    }
    // Zero the host bits, as ufw does.
    final bytes = List<int>.of(addr.rawAddress);
    for (var i = 0; i < bytes.length; i++) {
      final keep = (prefix - i * 8).clamp(0, 8);
      bytes[i] &= (0xff << (8 - keep)) & 0xff;
    }
    return Cidr._(bytes, prefix);
  }

  bool contains(InternetAddress ip) {
    var raw = ip.rawAddress;
    // An IPv4-mapped IPv6 client (::ffff:a.b.c.d) against an IPv4 network.
    if (!isV6 && raw.length == 16 && _isMapped(raw)) raw = raw.sublist(12);
    if (raw.length != bytes.length) return false;
    for (var bit = 0; bit < prefix; bit++) {
      final mask = 0x80 >> (bit % 8);
      if ((raw[bit ~/ 8] & mask) != (bytes[bit ~/ 8] & mask)) return false;
    }
    return true;
  }

  static bool _isMapped(List<int> raw) {
    for (var i = 0; i < 10; i++) {
      if (raw[i] != 0) return false;
    }
    return raw[10] == 0xff && raw[11] == 0xff;
  }

  @override
  String toString() {
    final addr = InternetAddress.fromRawAddress(Uint8List.fromList(bytes)).address;
    return prefix == bytes.length * 8 ? addr : '$addr/$prefix';
  }
}

/// Rules from ufw's `user.rules` / `user6.rules` (`### tuple ###` lines),
/// with IPv4 and IPv6 copies of the same rule merged.
List<FwRule> parseUfwRules(String v4, String v6) {
  final out = <FwRule>[];
  for (final (text, family) in [(v4, 'v4'), (v6, 'v6')]) {
    for (final line in LineSplitter.split(text)) {
      if (!line.startsWith('### tuple ### ')) continue;
      final rule = _parseTuple(line.substring(14).trim(), family);
      final twin = out.indexWhere((r) =>
          r.simple &&
          rule.simple &&
          r.sameAs(rule) &&
          r.comment == rule.comment &&
          !r.families.contains(family));
      if (twin >= 0) {
        final r = out[twin];
        out[twin] = FwRule(
          action: r.action,
          proto: r.proto,
          port: r.port,
          from: r.from,
          comment: r.comment,
          families: {...r.families, family},
        );
      } else {
        out.add(rule);
      }
    }
  }
  return out;
}

FwRule _parseTuple(String tuple, String family) {
  var comment = '';
  var body = tuple;
  final c = tuple.indexOf(' comment=');
  if (c >= 0) {
    comment = _unhex(tuple.substring(c + 9).trim());
    body = tuple.substring(0, c);
  }
  final t = body.split(' ');
  FwRule other() => FwRule(
        action: t.first,
        proto: t.length > 1 ? t[1] : 'any',
        port: null,
        from: 'any',
        comment: comment,
        families: {family},
        simple: false,
        raw: body,
      );
  // action proto dport dst sport src direction
  if (t.length != 7) return other();
  final action = t[0].replaceAll(RegExp(r'_log(-all)?$'), '');
  final anyDst = t[3] == '0.0.0.0/0' || t[3] == '::/0';
  if (!FwRule.actions.contains(action) ||
      !FwRule.protos.contains(t[1]) ||
      !anyDst ||
      t[4] != 'any' ||
      t[6] != 'in') {
    return other();
  }
  final port = t[2] == 'any' ? null : t[2];
  if (port != null && FwRule.portRange(port) == null) return other();
  final String from;
  try {
    from = normaliseSource(t[5]);
  } on FormatException {
    return other();
  }
  return FwRule(
    action: action,
    proto: t[1],
    port: port,
    from: from,
    comment: comment,
    families: {family},
  );
}

String _unhex(String hex) {
  try {
    final bytes = <int>[
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return '';
  }
}

/// Why a change would cut off SSH or the panel, or null when it is safe.
///
/// [sshPorts] are the host's SSH ports, [webPorts] the ports the panel is
/// reached on (80 and 443, plus its own port when users reach it directly),
/// and [keepIps] the addresses of whoever asked for the change.
class FwGuard {
  FwGuard({
    required this.sshPorts,
    required this.webPorts,
    required this.keepIps,
  });

  final Set<int> sshPorts;
  final Set<int> webPorts;
  final List<InternetAddress> keepIps;

  Set<int> get protectedPorts => {...sshPorts, ...webPorts};

  String? checkAdd(FwRule rule) {
    if (rule.blocks) {
      for (final ip in keepIps) {
        if (rule.fromIncludes(ip) && rule.from != 'any') {
          return '${rule.from} includes your own address (${ip.address}), '
              'so this would block you.';
        }
      }
      if (rule.from == 'any') {
        if (rule.port == null) {
          return 'Blocking every port from anywhere would cut off SSH and '
              'the panel. Block a specific source or port instead.';
        }
        for (final p in protectedPorts) {
          if (rule.coversTcp(p)) return _whyProtected(p, 'block');
        }
      }
    }
    if (rule.action == 'limit') {
      for (final p in webPorts) {
        if (rule.coversTcp(p)) {
          return 'Rate limiting port $p would throttle the panel (browsers '
              'open many connections). Limit other ports, such as SSH.';
        }
      }
    }
    return null;
  }

  /// [live] are the current rules; [active] whether ufw is on.
  String? checkDelete(FwRule rule, List<FwRule> live, bool active) {
    final target = live.where((r) => r.simple && r.sameAs(rule)).toList();
    if (target.isEmpty) return 'That rule is not on the firewall.';
    if (target.every((r) => r.origin != 'panel')) {
      return 'Only rules added from the panel can be removed here.';
    }
    if (!active || rule.blocks) return null;
    final rest = live.where((r) => !(r.simple && r.sameAs(rule))).toList();
    for (final p in protectedPorts) {
      if (!rule.coversTcp(p) || !letsIn(rule)) continue;
      if (!rest.any((r) => !r.blocks && r.coversTcp(p) && letsIn(r))) {
        return '${_whyProtected(p, 'close')} No other rule lets you in on it.';
      }
    }
    return null;
  }

  /// Before letting only [sources] reach the web ports: every address that
  /// must keep reaching the panel has to be among them. [sources] are
  /// normalised, and empty means everyone.
  String? checkWebSources(List<String> sources) {
    if (sources.isEmpty) return null;
    for (final ip in keepIps) {
      if (!sources.any((s) => Cidr.parse(s).contains(ip))) {
        return 'Your address (${ip.address}) is not in these ranges, so '
            'this would cut you off from the panel. If you reach the panel '
            'through a proxy such as Cloudflare, include its ranges.';
      }
    }
    return null;
  }

  /// Before turning the firewall on: any rule that would block the
  /// requester on a protected port.
  String? checkEnable(List<FwRule> live) {
    for (final r in live) {
      if (!r.simple || !r.blocks || r.from == 'any') continue;
      for (final ip in keepIps) {
        if (!r.fromIncludes(ip)) continue;
        for (final p in protectedPorts) {
          if (r.coversTcp(p)) {
            return 'An existing rule (${r.action} from ${r.from}) blocks your '
                'address on port $p. Remove it before turning the firewall on.';
          }
        }
      }
    }
    return null;
  }

  /// Whether [r] lets the addresses that must keep reaching the panel in.
  bool letsIn(FwRule r) =>
      r.from == 'any' || keepIps.any((ip) => r.fromIncludes(ip));

  String _whyProtected(int p, String verb) => sshPorts.contains(p)
      ? 'Port $p is this server\'s SSH port. The panel will not $verb it.'
      : 'Port $p is how the panel is reached. The panel will not $verb it.';
}
