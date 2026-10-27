import 'package:shelf/shelf.dart';

final _hostRe = RegExp(r'^[A-Za-z0-9.\-]+(:[0-9]{1,5})?$');

/// Security headers for the panel UI's HTML shell.
///
/// The session token lives in `localStorage`, so an injected script could
/// read it; the policy allows scripts only from this origin (the Vite bundle
/// has no inline or eval'd code) and keeps the page out of frames. Styles
/// allow inline because Carbon and the chart library inject `<style>`
/// elements. Fonts come from Google Fonts (see frontend/index.html).
Map<String, String> panelUiHeaders(Request request) {
  final host = request.headers['host'];
  // `'self'` covers ws(s):// to the same host in current browsers; listed
  // explicitly for older ones. The Host header only shapes this response.
  final sockets =
      host != null && _hostRe.hasMatch(host) ? ' wss://$host ws://$host' : '';
  final csp = [
    "default-src 'self'",
    "script-src 'self'",
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
    "font-src 'self' data: https://fonts.gstatic.com",
    "img-src 'self' data: blob:",
    "connect-src 'self'$sockets",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join('; ');
  return {
    'content-security-policy': csp,
    'x-frame-options': 'DENY',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'same-origin',
  };
}

/// Adds [panelUiHeaders] to HTML responses from [inner].
Handler withPanelUiHeaders(Handler inner) => (Request request) async {
      final response = await inner(request);
      final type = response.headers['content-type'] ?? '';
      if (!type.startsWith('text/html')) return response;
      return response.change(headers: panelUiHeaders(request));
    };
