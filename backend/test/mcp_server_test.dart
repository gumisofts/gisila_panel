import 'dart:convert';

import 'package:gisila/gisila.dart' show Authenticator, Principal;
import 'package:gisila_doc/gisila_doc.dart'
    show ApiInfo, OpenApiSpec, Operation, Parameter;
import 'package:gisila_panel/mcp/mcp_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _TokenAuth extends Authenticator {
  @override
  Future<Principal?> authenticate(Request request) async =>
      request.headers['authorization'] == 'Bearer gsl_ok'
          ? const Principal(id: '1')
          : null;
}

void main() {
  final calls = <Request>[];
  final spec = OpenApiSpec(info: const ApiInfo(title: 't', version: '1'))
    ..putOperation('/apps/', 'get',
        Operation(summary: 'List apps', tags: ['Apps']))
    ..putOperation(
        '/apps/{id}/restart', 'post',
        Operation(summary: 'Restart an app', tags: ['Apps'], parameters: [
          const Parameter(name: 'id', location: 'path', schema: {'type': 'integer'}),
        ]))
    ..putOperation('/auth/login', 'post', Operation(summary: 'Sign in', tags: ['Auth']))
    ..putOperation('/webhooks/apps/{appId}', 'post',
        Operation(summary: 'Webhook delivery', tags: ['Webhooks']));
  final mcp = McpServer(
    spec: spec,
    authenticator: _TokenAuth(),
    api: (req) async {
      calls.add(req);
      final body = await req.readAsString();
      return Response(req.method == 'GET' ? 200 : 202,
          body: jsonEncode({'path': req.url.path, 'body': body}),
          headers: {'content-type': 'application/json'});
    },
  );

  Future<Response> post(Object? body, {String token = 'gsl_ok'}) => mcp.call(
      Request('POST', Uri.parse('http://panel.test/mcp'),
          headers: {'authorization': 'Bearer $token'}, body: jsonEncode(body)));

  Future<Map<String, Object?>> tool(String name, Map<String, Object?> args) async {
    final res = await post({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': name, 'arguments': args},
    });
    return (jsonDecode(await res.readAsString()) as Map)['result']
        as Map<String, Object?>;
  }

  String text(Map<String, Object?> r) =>
      ((r['content'] as List).first as Map)['text'] as String;

  test('needs a token', () async {
    expect((await post({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}, token: 'bad')).statusCode, 401);
  });

  test('initialize agrees on a protocol version', () async {
    final res = await post({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': '2025-03-26'},
    });
    final result = (jsonDecode(await res.readAsString()) as Map)['result'] as Map;
    expect(result['protocolVersion'], '2025-03-26');
    final other = await post({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'initialize',
      'params': {'protocolVersion': '1999-01-01'},
    });
    expect(((jsonDecode(await other.readAsString()) as Map)['result'] as Map)['protocolVersion'],
        '2025-06-18');
  });

  test('notifications get 202, batches get an array', () async {
    expect((await post({'jsonrpc': '2.0', 'method': 'notifications/initialized'})).statusCode, 202);
    final res = await post([
      {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
      {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      {'jsonrpc': '2.0', 'id': 2, 'method': 'ping'},
    ]);
    expect((jsonDecode(await res.readAsString()) as List).length, 2);
  });

  test('search hides sign-in and webhook routes', () async {
    expect(mcp.ops.map((o) => o.path), ['/apps/', '/apps/{id}/restart']);
    final r = await tool('search_api', {'query': 'restart'});
    expect(text(r), contains('POST /apps/{id}/restart'));
  });

  test('calls go to the API with the caller\'s token', () async {
    calls.clear();
    var r = await tool('api_get', {'path': '/apps'});
    expect(r['isError'], false);
    expect(calls.single.url.path, 'apps/', reason: 'canonical trailing slash');
    expect(calls.single.headers['authorization'], 'Bearer gsl_ok');

    r = await tool('api_change', {'method': 'POST', 'path': '/apps/7/restart', 'body': {'force': true}});
    expect(text(r), startsWith('HTTP 202'));
    expect(calls.last.method, 'POST');
    expect(text(r), contains(r'\"force\":true'));
  });

  test('refuses routes that do not exist or use another method', () async {
    calls.clear();
    expect(text(await tool('api_get', {'path': '/apps/7/restart'})), contains('takes POST'));
    expect(text(await tool('api_change', {'method': 'POST', 'path': '/auth/login'})),
        contains('No API route'));
    expect(text(await tool('api_change', {'method': 'GET', 'path': '/apps/'})), contains('api_get'));
    expect((await tool('api_get', {'path': '/../x'}))['isError'], true);
    expect(calls, isEmpty);
  });
}
