import 'dart:async';
import 'dart:convert';

import 'package:gisila/gisila.dart' show Authenticator;
import 'package:gisila_doc/gisila_doc.dart' show OpenApiSpec;
import 'package:gisila_panel/version.dart';
import 'package:shelf/shelf.dart';

/// Model Context Protocol endpoint at `/mcp`, so AI assistants (Claude
/// Code, Claude Desktop, Cursor, …) can work with the panel.
///
/// Streamable HTTP transport, stateless: every JSON-RPC message is a POST and
/// gets a JSON answer, with no session and no server-sent stream.
///
/// The tools are generated from the panel's own OpenAPI document, so they
/// cover every API route and stay in step with it. Rather than one tool per
/// route (hundreds, which would crowd the assistant's context), there are
/// three: [_searchTool] finds the routes for a task, [_getTool] calls read
/// routes and [_changeTool] calls the rest. Calls go through the full API
/// [_api] handler with the caller's token, so they are authenticated,
/// authorized, validated, rate limited and audited exactly like the UI.
class McpServer {
  McpServer({
    required Handler api,
    required OpenApiSpec spec,
    required Authenticator authenticator,
  })  : _api = api,
        _spec = spec,
        _authenticator = authenticator;

  final Handler _api;
  final OpenApiSpec _spec;
  final Authenticator _authenticator;

  static const _protocolVersions = ['2025-06-18', '2025-03-26', '2024-11-05'];

  /// Largest JSON-RPC request accepted, and largest API response passed on
  /// whole (longer ones are cut, with a note).
  static const maxRequestBytes = 1024 * 1024;
  static const maxResultChars = 100000;

  static const _searchTool = 'search_api';
  static const _getTool = 'api_get';
  static const _changeTool = 'api_change';

  /// Routes the assistant can't use with a token: signing in, and the
  /// public endpoints called by git hosts.
  static final _hidden = RegExp(r'^/(auth/(login|logout)|webhooks/|mcp)');

  List<McpRoute>? _ops;

  List<McpRoute> get ops => _ops ??= _buildOps();

  Future<Response> call(Request request) async {
    if (request.method != 'POST') {
      // No server-initiated stream (GET) and no sessions to end (DELETE).
      return Response(405,
          headers: {'allow': 'POST', 'content-type': 'text/plain'},
          body: 'This MCP endpoint only takes POST.');
    }
    // A browser page on another site must not drive the API with an
    // ambient credential (DNS rebinding). MCP clients send no Origin.
    final origin = request.headers['origin'];
    if (origin != null && Uri.tryParse(origin)?.host != request.requestedUri.host) {
      return Response.forbidden('Cross-origin requests are not allowed.');
    }
    final principal = await _authenticator.authenticate(request);
    if (principal == null) {
      return Response(401,
          headers: {
            'www-authenticate': 'Bearer realm="gisila-panel"',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'error': 'Send a panel API token: Authorization: Bearer gsl_… '
                '(Settings → API tokens).',
          }));
    }

    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > maxRequestBytes) {
        return _json(_error(null, -32600, 'Request too large.'), status: 413);
      }
    }
    final Object? message;
    try {
      message = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return _json(_error(null, -32700, 'Parse error.'), status: 400);
    }

    if (message is List) {
      final answers = <Object?>[];
      for (final m in message) {
        final a = await _handle(m, request);
        if (a != null) answers.add(a);
      }
      return answers.isEmpty ? Response(202) : _json(answers);
    }
    final answer = await _handle(message, request);
    return answer == null ? Response(202) : _json(answer);
  }

  /// One JSON-RPC message; null for notifications and responses.
  Future<Map<String, Object?>?> _handle(Object? message, Request request) async {
    if (message is! Map) return _error(null, -32600, 'Invalid request.');
    final id = message['id'];
    final method = message['method'];
    if (method is! String) return null; // a response to us, or junk
    final params = message['params'] is Map
        ? Map<String, Object?>.from(message['params'] as Map)
        : <String, Object?>{};
    if (!message.containsKey('id')) return null; // notification

    try {
      final result = switch (method) {
        'initialize' => _initialize(params),
        'ping' => <String, Object?>{},
        'tools/list' => {'tools': _tools()},
        'tools/call' => await _callTool(params, request),
        _ => throw _RpcError(-32601, 'Method not found: $method'),
      };
      return {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on _RpcError catch (e) {
      return _error(id, e.code, e.message);
    }
  }

  Map<String, Object?> _initialize(Map<String, Object?> params) {
    final asked = params['protocolVersion'];
    return {
      'protocolVersion':
          _protocolVersions.contains(asked) ? asked : _protocolVersions.first,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {'name': 'gisila-panel', 'version': gisilaVersion},
      'instructions': '''
Gisila Panel is a PaaS control plane: teams own projects, projects hold apps,
apps are deployed (git, binary or ZIP sources) and have deployments, env vars,
domains, cron jobs, metrics and logs. Superusers also manage node-wide
services, databases, storage, mail and the firewall.

Use $_searchTool to find the routes for a task (it returns each route's
parameters and body), then $_getTool for reads and $_changeTool for changes.
Calls run as the owner of your API token, with their permissions, and are
recorded in the panel's activity log. Runtime logs: GET
/apps/{appId}/runtime-logs/?lines=200. Build logs: GET /deployments/{id}/logs.
Firewall changes roll back unless confirmed with POST
/firewall/changes/{id}/confirm once applied.''',
    };
  }

  List<Map<String, Object?>> _tools() => [
        {
          'name': _searchTool,
          'title': 'Find panel API routes',
          'description': 'Search the Gisila Panel API for the routes that do '
              'something, by words like "deploy", "env vars", "restart", '
              '"logs" or a resource name. Returns each route\'s method, '
              'path, parameters and request body. With no query, lists the '
              'route groups.',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'query': {
                'type': 'string',
                'description': 'Words to search for.',
              },
              'limit': {
                'type': 'integer',
                'minimum': 1,
                'maximum': 50,
                'description': 'Most routes to return (default 15).',
              },
            },
          },
          'annotations': {'readOnlyHint': true, 'openWorldHint': false},
        },
        {
          'name': _getTool,
          'title': 'Read from the panel',
          'description': 'Call a GET route of the Gisila Panel API, e.g. '
              '{"path": "/apps/12"} or {"path": "/apps/12/deployments/", '
              '"query": {"page": 1}}. Fill in path parameters. Returns the '
              'HTTP status and JSON body.',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': 'Route path, starting with /.'},
              'query': {
                'type': 'object',
                'description': 'Query parameters.',
                'additionalProperties': true,
              },
            },
            'required': ['path'],
          },
          'annotations': {
            'readOnlyHint': true,
            'idempotentHint': true,
            'openWorldHint': false,
          },
        },
        {
          'name': _changeTool,
          'title': 'Change something in the panel',
          'description': 'Call a POST, PUT, PATCH or DELETE route of the '
              'Gisila Panel API: deploy, restart, set env vars, create or '
              'delete resources and so on. Takes effect on the real server. '
              'Check the route with $_searchTool first. Returns the HTTP '
              'status and JSON body.',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'method': {
                'type': 'string',
                'enum': ['POST', 'PUT', 'PATCH', 'DELETE'],
              },
              'path': {'type': 'string', 'description': 'Route path, starting with /.'},
              'query': {
                'type': 'object',
                'description': 'Query parameters.',
                'additionalProperties': true,
              },
              'body': {
                'type': 'object',
                'description': 'JSON request body.',
                'additionalProperties': true,
              },
            },
            'required': ['method', 'path'],
          },
          'annotations': {
            'readOnlyHint': false,
            'destructiveHint': true,
            'idempotentHint': false,
            'openWorldHint': false,
          },
        },
      ];

  Future<Map<String, Object?>> _callTool(
      Map<String, Object?> params, Request request) async {
    final name = params['name'];
    final args = params['arguments'] is Map
        ? Map<String, Object?>.from(params['arguments'] as Map)
        : <String, Object?>{};
    switch (name) {
      case _searchTool:
        return _text(_search('${args['query'] ?? ''}',
            (args['limit'] is int ? args['limit'] as int : 15).clamp(1, 50)));
      case _getTool:
        return _invoke(request, 'GET', args);
      case _changeTool:
        final method = '${args['method'] ?? ''}'.toUpperCase();
        if (!const {'POST', 'PUT', 'PATCH', 'DELETE'}.contains(method)) {
          return _text('method must be POST, PUT, PATCH or DELETE '
              '(use $_getTool for GET).', isError: true);
        }
        return _invoke(request, method, args);
      default:
        throw _RpcError(-32602, 'Unknown tool: $name');
    }
  }

  // ── Search ────────────────────────────────────────────────────────────────

  String _search(String query, int limit) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 1)
        .toList();
    if (words.isEmpty) {
      final byTag = <String, List<McpRoute>>{};
      for (final op in ops) {
        byTag.putIfAbsent(op.tag, () => []).add(op);
      }
      return [
        'Route groups (search with words from a group or a task):',
        for (final e in byTag.entries)
          '- ${e.key} (${e.value.length}): '
              '${e.value.take(4).map((o) => o.summary).join('; ')}'
              '${e.value.length > 4 ? '; …' : ''}',
      ].join('\n');
    }
    final scored = <(int, McpRoute)>[];
    for (final op in ops) {
      var score = 0;
      for (final w in words) {
        final stem = w.length > 4 ? w.substring(0, w.length - 1) : w;
        if (op.tag.toLowerCase().contains(stem)) score += 3;
        if (op.path.toLowerCase().contains(stem)) score += 3;
        if (op.summary.toLowerCase().contains(stem)) score += 2;
        if (op.description.toLowerCase().contains(stem)) score += 1;
      }
      if (score > 0) scored.add((score, op));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    if (scored.isEmpty) {
      return 'No routes match "$query". Call $_searchTool with no query to '
          'see the route groups.';
    }
    return [
      for (final (_, op) in scored.take(limit)) op.describe(),
      if (scored.length > limit) '(${scored.length - limit} more; narrow the query or raise limit)',
    ].join('\n\n');
  }

  List<McpRoute> _buildOps() {
    final doc = _spec.toMap();
    final schemas =
        ((doc['components'] as Map?)?['schemas'] as Map?)?.cast<String, Object?>() ?? {};
    final out = <McpRoute>[];
    final paths = (doc['paths'] as Map).cast<String, Object?>();
    for (final p in paths.entries) {
      if (_hidden.hasMatch(p.key)) continue;
      for (final m in (p.value as Map).cast<String, Object?>().entries) {
        final op = (m.value as Map).cast<String, Object?>();
        Object? body;
        final content = ((op['requestBody'] as Map?)?['content'] as Map?);
        final json = content?['application/json'] as Map?;
        if (json != null) body = _resolve(json['schema'], schemas, 0);
        out.add(McpRoute(
          method: m.key.toUpperCase(),
          path: p.key,
          tag: ((op['tags'] as List?)?.firstOrNull ?? 'Other').toString(),
          summary: '${op['summary'] ?? ''}',
          description: '${op['description'] ?? ''}',
          parameters: [
            for (final param in (op['parameters'] as List?) ?? const [])
              (param as Map).cast<String, Object?>(),
          ],
          body: body,
          multipart: content?.keys.any((k) => '$k'.startsWith('multipart/')) ?? false,
        ));
      }
    }
    return out;
  }

  /// [schema] with `$ref`s to components inlined (bounded, for cycles).
  Object? _resolve(Object? schema, Map<String, Object?> schemas, int depth) {
    if (depth > 6) return {'type': 'object'};
    if (schema is Map) {
      final ref = schema[r'$ref'];
      if (ref is String && ref.startsWith('#/components/schemas/')) {
        return _resolve(schemas[ref.substring(21)], schemas, depth + 1);
      }
      return {
        for (final e in schema.entries) '${e.key}': _resolve(e.value, schemas, depth + 1),
      };
    }
    if (schema is List) return [for (final s in schema) _resolve(s, schemas, depth + 1)];
    return schema;
  }

  // ── Calling the API ───────────────────────────────────────────────────────

  Future<Map<String, Object?>> _invoke(
      Request outer, String method, Map<String, Object?> args) async {
    final rawPath = '${args['path'] ?? ''}'.trim();
    final Uri parsed;
    try {
      parsed = Uri.parse(rawPath);
    } on FormatException {
      return _text('path is not a valid URL path.', isError: true);
    }
    final path = parsed.path;
    if (!path.startsWith('/') || path.contains('..') || parsed.hasAuthority) {
      return _text('path must be an API route starting with /, e.g. /apps/12.',
          isError: true);
    }
    final op = _match(method, path);
    if (op == null) {
      final other = ops.where((o) => o.matches(path)).map((o) => o.method).toSet();
      return _text(
          other.isEmpty
              ? 'No API route $method $path. Use $_searchTool to find it.'
              : '$path takes ${other.join(', ')}, not $method.',
          isError: true);
    }
    if (op.multipart) {
      return _text('$method ${op.path} takes a file upload, which this tool '
          'can\'t send. Use the panel UI or the HTTP API for it.', isError: true);
    }
    final query = <String, String>{
      ...parsed.queryParameters,
      if (args['query'] is Map)
        for (final e in (args['query'] as Map).entries)
          if (e.value != null) '${e.key}': '${e.value}',
    };
    final body = args['body'];
    final inner = Request(
      method,
      outer.requestedUri.replace(
        path: op.canonical(path),
        queryParameters: query.isEmpty ? null : query,
      ),
      headers: {
        for (final h in const ['authorization', 'x-api-token', 'x-forwarded-for'])
          if (outer.headers[h] != null) h: outer.headers[h]!,
        'accept': 'application/json',
        'user-agent': 'gisila-mcp (${outer.headers['user-agent'] ?? 'unknown'})',
        if (body != null) 'content-type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body),
      // Keeps the caller's address for rate limits, the audit log and the
      // firewall's lockout checks.
      context: {
        if (outer.context['shelf.io.connection_info'] != null)
          'shelf.io.connection_info': outer.context['shelf.io.connection_info']!,
      },
    );
    final Response res;
    try {
      res = await _api(inner);
    } catch (e) {
      return _text('The panel failed to handle $method $path: $e', isError: true);
    }
    final type = res.headers['content-type'] ?? '';
    String text;
    if (type.contains('json') || type.startsWith('text/')) {
      text = await res.readAsString();
      if (type.contains('json')) {
        try {
          text = const JsonEncoder.withIndent(' ').convert(jsonDecode(text));
        } catch (_) {}
      }
    } else {
      await res.read().drain<void>();
      text = '(${res.contentLength ?? 'unknown'} bytes of $type)';
    }
    if (text.length > maxResultChars) {
      text = '${text.substring(0, maxResultChars)}\n… cut at $maxResultChars '
          'characters; ask for less (fewer lines, a smaller page).';
    }
    return _text('HTTP ${res.statusCode}\n$text', isError: res.statusCode >= 400);
  }

  McpRoute? _match(String method, String path) {
    for (final op in ops) {
      if (op.method == method && op.matches(path)) return op;
    }
    return null;
  }

  static Map<String, Object?> _text(String text, {bool isError = false}) => {
        'content': [
          {'type': 'text', 'text': text},
        ],
        'isError': isError,
      };

  static Map<String, Object?> _error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  static Response _json(Object? body, {int status = 200}) => Response(status,
      body: jsonEncode(body), headers: {'content-type': 'application/json'});
}

class _RpcError implements Exception {
  _RpcError(this.code, this.message);
  final int code;
  final String message;
}

/// One API route from the OpenAPI document, as the MCP tools see it.
class McpRoute {
  McpRoute({
    required this.method,
    required this.path,
    required this.tag,
    required this.summary,
    required this.description,
    required this.parameters,
    required this.body,
    required this.multipart,
  }) : _pattern = RegExp('^${_trim(path).split('/').map((s) => s.startsWith('{') ? '[^/]+' : RegExp.escape(s)).join('/')}\$');

  final String method;
  final String path;
  final String tag;
  final String summary;
  final String description;
  final List<Map<String, Object?>> parameters;
  final Object? body;
  final bool multipart;
  final RegExp _pattern;

  /// Whether [p] is this route, with or without a trailing slash.
  bool matches(String p) => _pattern.hasMatch(_trim(p));

  /// [p] spelled the way the router has this route (`/apps/` vs `/apps`).
  String canonical(String p) => path.endsWith('/') ? '${_trim(p)}/' : _trim(p);

  static String _trim(String p) =>
      p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;

  String describe() {
    final query = parameters.where((p) => p['in'] == 'query').toList();
    return [
      '$method $path — $summary [$tag]',
      if (description.isNotEmpty && description != summary) '  $description',
      if (query.isNotEmpty)
        '  query: ${query.map((p) => '${p['name']}${p['required'] == true ? '' : '?'} (${(p['schema'] as Map?)?['type'] ?? 'string'})').join(', ')}',
      if (multipart) '  body: file upload (not available through MCP)',
      if (body != null && !multipart) '  body: ${jsonEncode(body)}',
    ].join('\n');
  }
}
