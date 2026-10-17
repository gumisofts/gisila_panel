import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/version.dart';

part 'system.g.dart';

@Controller('/system', ['System'])
@RequireAuth()
class SystemApi {
  @Get('/info', summary: 'Server addresses and the running Gisila version')
  Future<Map<String, Object?>> info(RequestContext ctx) async {
    return <String, Object?>{
      'hostname': Platform.localHostname,
      'publicIp': await _publicIp(),
      'privateIps': await _privateIps(),
      'version': <String, Object?>{
        'panel': <String, Object?>{
          'version': gisilaVersion,
          'commit': gisilaCommit,
          'builtAt': gisilaBuiltAt,
        },
        'agent': await _agentVersion(),
      },
    };
  }
}

Map<String, Object?>? _agentInfo;
DateTime? _agentAt;

/// The installed gisila-agent's build stamp, or null when it can't be asked.
///
/// The agent is a separate binary that is often updated on its own, and a
/// panel newer than its agent passes flags the agent doesn't know — so the
/// two are reported side by side. `version` needs no root, so this runs the
/// binary directly (the API itself can never sudo). Cached briefly: an agent
/// swap needs no panel restart, so it must show up without one.
Future<Map<String, Object?>?> _agentVersion() async {
  final at = _agentAt;
  if (at != null && DateTime.now().difference(at) < const Duration(minutes: 2)) {
    return _agentInfo;
  }
  Map<String, Object?>? info;
  try {
    final cmd = buildAgentCmdNoSudo(['version']);
    final res = await Process.run(cmd.first, cmd.skip(1).toList())
        .timeout(const Duration(seconds: 5));
    for (final line in (res.stdout as String).split('\n').reversed) {
      if (!line.trim().startsWith('{') || !line.contains('"version"')) continue;
      final decoded = jsonDecode(line.trim());
      if (decoded is Map<String, Object?>) info = decoded;
      break;
    }
  } catch (_) {
    // Missing binary, or an agent too old to have `version` — report unknown.
  }
  _agentInfo = info;
  _agentAt = DateTime.now();
  return info;
}

String? _cachedIp;
DateTime? _cachedAt;

/// The address DNS records for app domains should point at.
///
/// `PUBLIC_IP` in /etc/gisila/.env wins — behind NAT or with several
/// addresses only the operator knows which one the world reaches. Otherwise
/// ask the same echo service the mail setup uses, the way the agent does for
/// DKIM/SPF records, and cache the answer: it changes rarely and the lookup
/// must not slow down every page that shows it.
Future<String?> _publicIp() async {
  final configured = env['PUBLIC_IP']?.trim();
  if (configured != null && configured.isNotEmpty) return configured;

  final at = _cachedAt;
  if (at != null && DateTime.now().difference(at) < const Duration(hours: 1)) {
    return _cachedIp;
  }
  String? ip;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await client.getUrl(Uri.parse('https://api.ipify.org'));
    final res = await req.close().timeout(const Duration(seconds: 4));
    final body = (await res.transform(utf8.decoder).join()).trim();
    if (res.statusCode == 200 && InternetAddress.tryParse(body) != null) {
      ip = body;
    }
  } catch (_) {
    // Offline or blocked egress — fall back to the first local address.
  } finally {
    client.close(force: true);
  }
  ip ??= (await _privateIps()).firstOrNull;
  _cachedIp = ip;
  _cachedAt = DateTime.now();
  return ip;
}

/// Non-loopback IPv4 addresses on this host's interfaces.
Future<List<String>> _privateIps() async {
  try {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    return [
      for (final i in interfaces)
        // Container bridges are never what a client should connect to.
        if (!i.name.startsWith('docker') && !i.name.startsWith('br-'))
          for (final a in i.addresses) a.address,
    ];
  } catch (_) {
    return const [];
  }
}
