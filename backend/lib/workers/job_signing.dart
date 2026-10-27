import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:gisila_panel/utils/jwt.dart';

/// Signs the jobs the API puts on Redis for the worker, which runs them as
/// root. Anything else able to write to Redis (a tenant app, if Redis were
/// ever reachable from one) cannot forge a job without the key, which is
/// derived from `JWT_SECRET` in /etc/gisila/.env and never sent to Redis.
///
/// Wire format: `{"p": "<payload JSON>", "s": "<hex HMAC-SHA256 of p>"}`.
class JobSigner {
  static final _hmac =
      Hmac(sha256, utf8.encode(JWTAuth.derivedSecret('job-signing')));

  static String _sign(String payload) =>
      _hmac.convert(utf8.encode(payload)).toString();

  /// Wraps [payloadJson] in a signed envelope.
  static String wrap(String payloadJson) =>
      jsonEncode(<String, String>{'p': payloadJson, 's': _sign(payloadJson)});

  /// The payload JSON of a correctly signed envelope, or null.
  static String? unwrap(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final p = decoded['p'];
    final s = decoded['s'];
    if (p is! String || s is! String) return null;
    return _equal(_sign(p), s) ? p : null;
  }

  static bool _equal(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
