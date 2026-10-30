import 'dart:io';

import 'package:gisila_agent/firewall/rules.dart';
import 'package:test/test.dart';

FwRule req(Map<String, Object?> json) => FwRule.request(json);

void main() {
  group('parseUfwRules', () {
    // Captured from ufw 0.36.2 on Debian 12.
    const v4 = '''
*filter
### RULES ###

### tuple ### deny udp 53 0.0.0.0/0 any 0.0.0.0/0 in
### tuple ### deny tcp 22 0.0.0.0/0 any 203.0.113.7 in comment=676973696c612d70616e656c3a2062616420626f74
### tuple ### allow tcp 22 0.0.0.0/0 any 0.0.0.0/0 in
### tuple ### allow tcp 8000:8100 0.0.0.0/0 any 10.0.0.0/8 in
### tuple ### limit tcp 2222 0.0.0.0/0 any 0.0.0.0/0 in
### tuple ### allow any any 0.0.0.0/0 any 0.0.0.0/0 out
''';
    const v6 = '''
### tuple ### deny udp 53 ::/0 any ::/0 in
### tuple ### deny any any ::/0 any 2001:db8::/32 in
### tuple ### allow tcp 22 ::/0 any ::/0 in
### tuple ### limit tcp 2222 ::/0 any ::/0 in
''';

    test('reads rules, comments and merges IPv4 / IPv6 twins', () {
      final rules = parseUfwRules(v4, v6);
      final json = [for (final r in rules) r.toJson()];
      expect(json[0], containsPair('families', ['v4', 'v6']));
      expect(json[0], containsPair('port', '53'));
      expect(json[1]['comment'], 'gisila-panel: bad bot');
      expect(json[1]['origin'], 'panel');
      expect(json[1]['from'], '203.0.113.7');
      expect(json[1]['families'], ['v4']);
      expect(json[2]['families'], ['v4', 'v6']);
      expect(json[3]['port'], '8000:8100');
      expect(json[4]['action'], 'limit');
      expect(json[5]['origin'], 'other', reason: 'outbound');
      expect(json[6]['from'], '2001:db8::/32');
      expect(json[6]['port'], isNull);
      expect(rules, hasLength(7));
    });
  });

  group('FwRule.request', () {
    test('normalises and builds ufw arguments', () {
      final r = req({
        'action': 'deny',
        'proto': 'tcp',
        'port': '22',
        'from': '203.0.113.9/24',
        'note': 'scanner',
      });
      expect(r.from, '203.0.113.0/24');
      expect(r.addArgs(), [
        'prepend', 'deny', 'proto', 'tcp', 'from', '203.0.113.0/24', 'to',
        'any', 'port', '22', 'comment', 'gisila-panel: scanner',
      ]);
      expect(r.deleteArgs(), [
        'delete', 'deny', 'proto', 'tcp', 'from', '203.0.113.0/24', 'to',
        'any', 'port', '22',
      ]);
      final allow = req({'action': 'allow', 'port': '8080'});
      expect(allow.addArgs().first, 'allow', reason: 'allows are appended');
      expect(allow.from, 'any');
    });

    test('rejects bad input', () {
      for (final bad in [
        {'action': 'drop'},
        {'action': 'allow', 'proto': 'icmp'},
        {'action': 'allow', 'port': '0'},
        {'action': 'allow', 'port': '70000'},
        {'action': 'allow', 'port': '90:80', 'proto': 'tcp'},
        {'action': 'allow', 'port': '80:90'},
        {'action': 'allow', 'port': '22; rm -rf /'},
        {'action': 'allow', 'from': 'example.com'},
        {'action': 'allow', 'from': '10.0.0.0/33'},
        {'action': 'limit'},
        {'action': 'allow', 'note': "it's"},
      ]) {
        expect(() => req(bad), throwsFormatException, reason: '$bad');
      }
    });
  });

  group('FwGuard', () {
    final me = InternetAddress('198.51.100.20');
    final guard = FwGuard(
      sshPorts: {22, 2222},
      webPorts: {80, 443},
      keepIps: [me],
    );

    test('refuses to block the requester', () {
      expect(guard.checkAdd(req({'action': 'deny', 'from': '198.51.100.0/24'})),
          contains('your own address'));
      expect(
          guard.checkAdd(
              req({'action': 'deny', 'from': '198.51.100.20', 'port': '5432', 'proto': 'tcp'})),
          isNotNull);
      final mapped = FwGuard(
          sshPorts: {22}, webPorts: {443}, keepIps: [InternetAddress('::ffff:198.51.100.20')]);
      expect(mapped.checkAdd(req({'action': 'deny', 'from': '198.51.100.0/24'})),
          isNotNull, reason: 'IPv4-mapped IPv6 client');
    });

    test('refuses to block SSH or the panel for everyone', () {
      expect(guard.checkAdd(req({'action': 'deny', 'port': '22'})), contains('SSH'));
      expect(guard.checkAdd(req({'action': 'reject', 'port': '2000:3000', 'proto': 'tcp'})),
          contains('2222'));
      expect(guard.checkAdd(req({'action': 'deny', 'port': '443', 'proto': 'tcp'})),
          contains('panel'));
      expect(guard.checkAdd(req({'action': 'deny'})), contains('every port'));
      expect(guard.checkAdd(req({'action': 'deny', 'port': '443', 'proto': 'udp'})),
          isNull, reason: 'UDP 443 is not the panel');
    });

    test('allows blocking other sources and other ports', () {
      expect(guard.checkAdd(req({'action': 'deny', 'from': '203.0.113.7'})), isNull);
      expect(guard.checkAdd(req({'action': 'deny', 'from': '203.0.113.7', 'port': '22'})),
          isNull, reason: 'blocking an attacker from SSH is fine');
      expect(guard.checkAdd(req({'action': 'deny', 'port': '5432', 'proto': 'tcp'})), isNull);
      expect(guard.checkAdd(req({'action': 'allow', 'port': '22'})), isNull);
      expect(guard.checkAdd(req({'action': 'limit', 'port': '22', 'proto': 'tcp'})), isNull);
      expect(guard.checkAdd(req({'action': 'limit', 'port': '443', 'proto': 'tcp'})),
          contains('throttle'));
    });

    FwRule live(String action, String? port, String from, String comment) => FwRule(
        action: action, proto: 'tcp', port: port, from: from, comment: comment);

    test('removing rules: only panel rules, never the last way in', () {
      final base = live('allow', '22', 'any', 'gisila-base: ssh');
      final mine = live('allow', '22', '198.51.100.0/24', 'gisila-panel');
      final other = live('allow', '9000', 'any', '');
      final rules = [base, mine, other];

      expect(guard.checkDelete(req({'action': 'allow', 'port': '9000', 'proto': 'tcp'}), rules, true),
          contains('Only rules added from the panel'));
      expect(guard.checkDelete(req({'action': 'allow', 'port': '1', 'proto': 'tcp'}), rules, true),
          contains('not on the firewall'));
      expect(
          guard.checkDelete(
              req({'action': 'allow', 'port': '22', 'proto': 'tcp', 'from': '198.51.100.0/24'}),
              rules, true),
          isNull, reason: 'the base rule still lets SSH in');

      final only = [live('allow', '22', '198.51.100.0/24', 'gisila-panel')];
      final del = req({'action': 'allow', 'port': '22', 'proto': 'tcp', 'from': '198.51.100.0/24'});
      expect(guard.checkDelete(del, only, true), contains('No other rule'));
      expect(guard.checkDelete(del, only, false), isNull,
          reason: 'nothing is blocked while the firewall is off');
    });

    test('turning on: refuses when a rule already blocks the requester', () {
      expect(guard.checkEnable([live('deny', null, '198.51.100.0/24', '')]),
          contains('blocks your address'));
      expect(guard.checkEnable([live('deny', null, '203.0.113.0/24', '')]), isNull);
    });

    test('web sources: the requester must be among them', () {
      expect(guard.checkWebSources(['173.245.48.0/20']), contains('cut you off'));
      expect(guard.checkWebSources(['173.245.48.0/20', '198.51.100.0/24']), isNull);
      expect(guard.checkWebSources([]), isNull, reason: 'open to everyone');
    });
  });

  group('web sources', () {
    FwRule live(String port, String from, String comment, {String action = 'allow'}) =>
        FwRule(action: action, proto: 'tcp', port: port, from: from, comment: comment);
    final base = [
      live('22', 'any', 'gisila-base: ssh'),
      live('80', 'any', 'gisila-base: http'),
      live('443', 'any', 'gisila-base: https'),
    ];
    const ports = {80, 443};

    test('parses and normalises the sources', () {
      expect(parseWebSources('{"sources": ["10.1.2.3/8", "2400:cb00::/32", "10.0.0.0/8"]}'),
          ['10.0.0.0/8', '2400:cb00::/32']);
      expect(parseWebSources('{"sources": ["10.0.0.0/8", "any"]}'), isEmpty);
      expect(() => parseWebSources('{"sources": "10.0.0.0/8"}'), throwsFormatException);
      expect(() => parseWebSources('{"sources": ["nope"]}'), throwsFormatException);
    });

    test('limits 80 and 443: adds the new rules, then drops the base ones', () {
      final cmds = webSourcesCommands(base, ['10.0.0.0/8', '2400:cb00::/32'], ports);
      expect(cmds, [
        ['allow', 'proto', 'tcp', 'from', '10.0.0.0/8', 'to', 'any', 'port', '80', 'comment', 'gisila-web: http'],
        ['allow', 'proto', 'tcp', 'from', '2400:cb00::/32', 'to', 'any', 'port', '80', 'comment', 'gisila-web: http'],
        ['allow', 'proto', 'tcp', 'from', '10.0.0.0/8', 'to', 'any', 'port', '443', 'comment', 'gisila-web: https'],
        ['allow', 'proto', 'tcp', 'from', '2400:cb00::/32', 'to', 'any', 'port', '443', 'comment', 'gisila-web: https'],
        ['delete', 'allow', 'proto', 'tcp', 'from', 'any', 'to', 'any', 'port', '80'],
        ['delete', 'allow', 'proto', 'tcp', 'from', 'any', 'to', 'any', 'port', '443'],
      ]);
    });

    test('changes only what differs, and can open up again', () {
      final limited = [
        base[0],
        live('80', '10.0.0.0/8', 'gisila-web: http'),
        live('443', '10.0.0.0/8', 'gisila-web: https'),
        live('80', '192.0.2.0/24', 'gisila-web: http'),
        live('443', '192.0.2.0/24', 'gisila-web: https'),
      ];
      expect(webSources(limited), ['10.0.0.0/8', '192.0.2.0/24']);
      expect(webSources(base), isEmpty);
      expect(webSourcesCommands(limited, ['10.0.0.0/8'], ports), [
        ['delete', 'allow', 'proto', 'tcp', 'from', '192.0.2.0/24', 'to', 'any', 'port', '80'],
        ['delete', 'allow', 'proto', 'tcp', 'from', '192.0.2.0/24', 'to', 'any', 'port', '443'],
      ]);
      final open = webSourcesCommands(limited, [], ports);
      expect(open.take(2), [
        ['allow', 'proto', 'tcp', 'from', 'any', 'to', 'any', 'port', '80', 'comment', 'gisila-base: http'],
        ['allow', 'proto', 'tcp', 'from', 'any', 'to', 'any', 'port', '443', 'comment', 'gisila-base: https'],
      ]);
      expect(open.skip(2).every((c) => c.first == 'delete'), isTrue);
      expect(open, hasLength(6));
      expect(webSourcesCommands(base, [], ports), isEmpty);
    });

    test('refuses when another rule keeps a web port open to everyone', () {
      expect(openWebRule([...base, live('443', 'any', 'gisila-panel')], ['10.0.0.0/8'], ports),
          contains('port 443'));
      expect(openWebRule([...base, live('80', 'any', 'gisila-panel', action: 'deny')], ['10.0.0.0/8'], ports),
          isNull);
      expect(openWebRule(base, ['10.0.0.0/8'], ports), isNull, reason: 'base rules are swapped out');
      expect(openWebRule([...base, live('443', 'any', '')], [], ports), isNull);
    });
  });
}
