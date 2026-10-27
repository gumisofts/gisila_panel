import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// The few S3 calls the agent makes on a provider's behalf: create, empty and
/// delete a bucket, and set a public-read policy. Signature V4, path-style
/// URLs (supported by Garage, MinIO, R2, B2 and AWS).
///
/// Replaces the MinIO client `mc`, which can no longer be downloaded.
class S3Client {
  S3Client({
    required String endpoint,
    required this.accessKey,
    required this.secretKey,
    this.region = 'us-east-1',
    HttpClient? http,
    DateTime Function()? clock,
  })  : endpoint = Uri.parse(endpoint.endsWith('/')
            ? endpoint.substring(0, endpoint.length - 1)
            : endpoint),
        _http = http ?? HttpClient(),
        _clock = clock ?? DateTime.now;

  final Uri endpoint;
  final String accessKey;
  final String secretKey;
  final String region;
  final HttpClient _http;
  final DateTime Function() _clock;

  /// Creates [bucket]; one that already exists and is ours is fine.
  Future<void> createBucket(String bucket) async {
    // Outside us-east-1, AWS wants the region in the body; others ignore it.
    final body = region == 'us-east-1' || region == 'auto' || region.isEmpty
        ? ''
        : '<CreateBucketConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
            '<LocationConstraint>$region</LocationConstraint>'
            '</CreateBucketConfiguration>';
    final r = await send('PUT', '/$bucket', body: utf8.encode(body));
    if (r.status == 409 && r.body.contains('BucketAlreadyOwnedByYou')) return;
    r.check('create bucket $bucket');
  }

  /// Deletes every object in [bucket] (including in-progress multipart
  /// uploads' parts are left to the server's lifecycle). Returns the count.
  Future<int> emptyBucket(String bucket) async {
    var deleted = 0;
    String? token;
    do {
      final r = await send('GET', '/$bucket', query: {
        'list-type': '2',
        'max-keys': '1000',
        if (token != null) 'continuation-token': token,
      });
      if (r.status == 404) return deleted;
      r.check('list $bucket');
      final keys = _tags(r.body, 'Key');
      token = _tags(r.body, 'IsTruncated').firstOrNull == 'true'
          ? _tags(r.body, 'NextContinuationToken').firstOrNull
          : null;
      if (keys.isEmpty) break;
      final xml = StringBuffer('<Delete><Quiet>true</Quiet>');
      for (final k in keys) {
        xml.write('<Object><Key>${_xmlEscape(k)}</Key></Object>');
      }
      xml.write('</Delete>');
      final bytes = utf8.encode(xml.toString());
      final d = await send('POST', '/$bucket',
          query: {'delete': ''},
          body: bytes,
          headers: {'content-md5': base64.encode(md5.convert(bytes).bytes)});
      d.check('delete objects in $bucket');
      final errors = _tags(d.body, 'Code');
      if (errors.isNotEmpty) {
        throw S3Exception('delete objects in $bucket', d.status,
            'some objects were not deleted: ${errors.toSet().join(', ')}');
      }
      deleted += keys.length;
    } while (token != null);
    return deleted;
  }

  /// Deletes [bucket] and everything in it. A missing bucket is fine.
  Future<void> deleteBucket(String bucket) async {
    await emptyBucket(bucket);
    final r = await send('DELETE', '/$bucket');
    if (r.status == 404) return;
    r.check('delete bucket $bucket');
  }

  /// Lets anyone read [bucket]'s objects (not list them).
  Future<void> setPublicRead(String bucket) async {
    final policy = jsonEncode({
      'Version': '2012-10-17',
      'Statement': [
        {
          'Effect': 'Allow',
          'Principal': {'AWS': ['*']},
          'Action': ['s3:GetObject'],
          'Resource': ['arn:aws:s3:::$bucket/*'],
        }
      ],
    });
    final r = await send('PUT', '/$bucket',
        query: {'policy': ''}, body: utf8.encode(policy));
    r.check('set public policy on $bucket');
  }

  /// One signed request. Public for tests and one-off calls.
  Future<S3Response> send(
    String method,
    String path, {
    Map<String, String> query = const {},
    List<int> body = const [],
    Map<String, String> headers = const {},
  }) async {
    final now = _clock().toUtc();
    final amzDate = _amzDate(now);
    final day = amzDate.substring(0, 8);
    final payloadHash = sha256.convert(body).toString();
    final basePath = endpoint.path;
    final canonicalPath = '$basePath$path'
        .split('/')
        .map(_uriEncode)
        .join('/');
    final sortedQuery = query.keys.toList()..sort();
    final canonicalQuery = sortedQuery
        .map((k) => '${_uriEncode(k)}=${_uriEncode(query[k]!)}')
        .join('&');
    final host = endpoint.hasPort &&
            !((endpoint.scheme == 'http' && endpoint.port == 80) ||
                (endpoint.scheme == 'https' && endpoint.port == 443))
        ? '${endpoint.host}:${endpoint.port}'
        : endpoint.host;
    final signed = <String, String>{
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      for (final e in headers.entries) e.key.toLowerCase(): e.value.trim(),
    };
    final names = signed.keys.toList()..sort();
    final canonicalRequest = [
      method,
      canonicalPath,
      canonicalQuery,
      for (final n in names) '$n:${signed[n]}',
      '',
      names.join(';'),
      payloadHash,
    ].join('\n');
    final scope = '$day/$region/s3/aws4_request';
    final toSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    var key = _hmac(utf8.encode('AWS4$secretKey'), day);
    key = _hmac(key, region);
    key = _hmac(key, 's3');
    key = _hmac(key, 'aws4_request');
    final signature =
        Hmac(sha256, key).convert(utf8.encode(toSign)).toString();

    final uri = Uri.parse('${endpoint.scheme}://$host$canonicalPath'
        '${canonicalQuery.isEmpty ? '' : '?$canonicalQuery'}');
    final req = await _http.openUrl(method, uri);
    req.followRedirects = false;
    // `host` is set by HttpClient from the URI; the rest goes as signed.
    for (final n in names) {
      if (n != 'host') req.headers.set(n, signed[n]!, preserveHeaderCase: true);
    }
    req.headers.set('authorization',
        'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, '
        'SignedHeaders=${names.join(';')}, Signature=$signature');
    req.contentLength = body.length;
    if (body.isNotEmpty) req.add(body);
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return S3Response(res.statusCode, text);
  }

  void close() => _http.close(force: true);

  static List<int> _hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  static String _amzDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}'
        'T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  }

  /// RFC 3986 encoding as SigV4 wants it (unreserved characters kept).
  static String _uriEncode(String s) {
    final out = StringBuffer();
    for (final b in utf8.encode(s)) {
      final c = String.fromCharCode(b);
      if (RegExp(r'[A-Za-z0-9\-._~]').hasMatch(c)) {
        out.write(c);
      } else {
        out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  static List<String> _tags(String xml, String tag) => [
        for (final m in RegExp('<$tag>([^<]*)</$tag>').allMatches(xml))
          _xmlUnescape(m.group(1)!),
      ];

  static String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _xmlUnescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

class S3Response {
  S3Response(this.status, this.body);
  final int status;
  final String body;

  void check(String what) {
    if (status >= 200 && status < 300) return;
    throw S3Exception(what, status, body);
  }
}

class S3Exception implements Exception {
  S3Exception(this.what, this.status, this.body);
  final String what;
  final int status;
  final String body;

  @override
  String toString() {
    final code = RegExp('<Code>([^<]*)</Code>').firstMatch(body)?.group(1);
    final msg = RegExp('<Message>([^<]*)</Message>').firstMatch(body)?.group(1);
    return 'S3 $what failed: HTTP $status'
        '${code != null ? ' $code' : ''}${msg != null ? ': $msg' : ''}';
  }
}

