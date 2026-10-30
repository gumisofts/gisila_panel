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
}
