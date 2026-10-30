import 'package:gisila/gisila.dart';
import 'package:gisila_panel/services/firewall_service.dart';
import 'package:test/test.dart';

void main() {
  group('FirewallService.validateRule', () {
    test('normalises a rule', () {
      expect(
          FirewallService.validateRule({
            'action': 'DENY',
            'port': ' 22 ',
            'from': '203.0.113.0/24',
            'note': 'scanner',
          }),
          {
            'action': 'deny',
            'proto': 'any',
            'port': '22',
            'from': '203.0.113.0/24',
            'note': 'scanner',
          });
      expect(FirewallService.validateRule({'action': 'allow', 'from': ''}),
          containsPair('from', 'any'));
      expect(
          FirewallService.validateRule(
              {'action': 'allow', 'port': '8000:8100', 'proto': 'tcp'}),
          containsPair('port', '8000:8100'));
    });

    test('rejects bad input', () {
      for (final bad in [
        {'action': 'drop'},
        {'action': 'allow', 'proto': 'icmp'},
        {'action': 'allow', 'port': '0'},
        {'action': 'allow', 'port': '65536'},
        {'action': 'allow', 'port': '100:90', 'proto': 'tcp'},
        {'action': 'allow', 'port': '80:90'},
        {'action': 'allow', 'port': '22 ; ls'},
        {'action': 'allow', 'from': 'example.com'},
        {'action': 'allow', 'from': '10.0.0.0/40'},
        {'action': 'allow', 'from': '::1/129'},
        {'action': 'allow', 'note': 'a\$b'},
      ]) {
        expect(() => FirewallService.validateRule(bad),
            throwsA(isA<BadRequest>()),
            reason: '$bad');
      }
    });
  });

  group('FirewallService.validateWebSources', () {
    test('a preset, a list, or everyone', () {
      final cf = FirewallService.validateWebSources(preset: 'Cloudflare');
      expect(cf['preset'], 'cloudflare');
      expect(cf['sources'], contains('173.245.48.0/20'));
      expect(cf['sources'], contains('2400:cb00::/32'));
      expect(
          FirewallService.validateWebSources(
              sources: '203.0.113.0/24, 2001:db8::/32\n203.0.113.0/24  198.51.100.7'),
          {
            'sources': ['203.0.113.0/24', '2001:db8::/32', '198.51.100.7'],
          });
      expect(FirewallService.validateWebSources(sources: ''), {'sources': []});
      expect(FirewallService.validateWebSources(),
          {'sources': []});
      expect(FirewallService.validateWebSources(sources: '10.0.0.0/8 any'),
          {'sources': []});
    });

    test('rejects bad input', () {
      for (final bad in ['example.com', '10.0.0.0/40', '10.0.0.0/8;ls']) {
        expect(() => FirewallService.validateWebSources(sources: bad),
            throwsA(isA<BadRequest>()),
            reason: bad);
      }
      expect(() => FirewallService.validateWebSources(preset: 'fastly'),
          throwsA(isA<BadRequest>()));
      expect(
          () => FirewallService.validateWebSources(
              sources: [for (var i = 0; i < 101; i++) '10.0.$i.0/24'].join(' ')),
          throwsA(isA<BadRequest>()));
    });
  });
}
