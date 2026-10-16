import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_panel/config.dart';

part 'system.g.dart';

@Controller('/system', ['System'])
@RequireAuth()
class SystemApi {
  @Get('/info', summary: 'Addresses of the server the panel runs on')
  Future<Map<String, Object?>> info(RequestContext ctx) async {
    return <String, Object?>{
      'hostname': Platform.localHostname,
      'publicIp': await _publicIp(),
      'privateIps': await _privateIps(),
    };
  }
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
