import 'package:gisila/gisila.dart';

/// A host firewall rule: inbound traffic [from] a source to a [port].
class FirewallRuleForm extends Form {
  // allow | deny | reject | limit
  final action = StringField(name: 'action', required: true, maxLength: 10);
  // tcp | udp | any
  final proto = StringField(name: 'proto', maxLength: 3);
  // `22`, `8000:8100`, or empty for every port.
  final port = StringField(name: 'port', maxLength: 11);
  // `any`, an IP address or a CIDR range.
  final from = StringField(name: 'from', maxLength: 64);
  final note = StringField(name: 'note', maxLength: 60);

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        action,
        proto,
        port,
        from,
        note,
      ];

  Map<String, Object?> toRule() => {
        'action': action.value,
        'proto': proto.value,
        'port': port.value,
        'from': from.value,
        'note': note.value,
      };
}

/// Which sources may reach the web ports (80 and 443): a [preset] such as
/// `cloudflare`, or a list of [sources]. Empty or `any` means everyone.
class WebSourcesForm extends Form {
  // IP addresses / CIDR ranges, separated by commas, spaces or new lines.
  final sources = StringField(name: 'sources', maxLength: 5000);
  // cloudflare, or empty.
  final preset = StringField(name: 'preset', maxLength: 20);

  @override
  List<FormField<Object?>> collectFields() => <FormField<Object?>>[
        sources,
        preset,
      ];
}
