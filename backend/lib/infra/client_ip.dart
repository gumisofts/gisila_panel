import 'dart:io';

import 'package:shelf/shelf.dart';

/// The address of the client that sent [request].
///
/// Proxy headers are believed only when the connection itself comes from
/// loopback, i.e. from the host's own nginx (which sets `X-Real-IP` to the
/// peer it saw). The panel also listens on 0.0.0.0, so a client reaching it
/// directly could otherwise claim any address. Even behind nginx the leftmost
/// `X-Forwarded-For` entry is whatever the client sent, so it is never used.
String? clientIp(Request request) {
  final info =
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
  final peer = info?.remoteAddress;
  if (peer == null) return null;
  if (!peer.isLoopback) return peer.address;

  final realIp = request.headers['x-real-ip']?.trim();
  if (realIp != null && InternetAddress.tryParse(realIp) != null) {
    return realIp;
  }
  // nginx's `$proxy_add_x_forwarded_for` appends the peer it saw last.
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null) {
    final last = forwarded.split(',').last.trim();
    if (InternetAddress.tryParse(last) != null) return last;
  }
  return peer.address;
}

/// Replace `X-Forwarded-For` with the single address [clientIp] trusts,
/// before anything downstream reads it.
///
/// The framework's rate limiter keys on the header's leftmost entry, which the
/// client controls: a fresh value per request would get a fresh bucket,
/// defeating the limit and growing the bucket map without bound. Generated
/// routes can't take a custom key function (the code generator drops it), so
/// the header itself is made trustworthy instead. Mount this outermost.
Middleware trustedForwardedFor() => (Handler inner) => (Request request) {
      final ip = clientIp(request);
      return inner(request.change(headers: {
        'x-forwarded-for': ip,
        // shelf merges change() headers, so drop X-Real-IP rather than let a
        // forged one through to code that might read it.
        'x-real-ip': null,
      }));
    };
