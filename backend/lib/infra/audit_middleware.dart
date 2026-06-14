import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/api_tokens.dart';
import 'package:gisila_panel/utils/jwt.dart';
import 'package:shelf/shelf.dart';

/// Records every successful state-changing request to the [AuditLog] so the
/// panel's Activity view can show exactly what each user did, when.
///
/// This is a single global middleware rather than per-service instrumentation
/// so that *every* mutating endpoint is captured automatically — nothing has to
/// remember to log. It runs around the whole pipeline: it lets the request
/// complete, then (only when the response is a success and the method mutates
/// state) resolves the acting user from the request's credentials and writes an
/// audit row in the background, so request latency is unaffected.
Middleware auditMiddleware(Database database) {
  return (Handler inner) {
    return (Request request) async {
      final response = await inner(request);
      if (_isMutating(request.method) && response.statusCode < 400) {
        // Fire-and-forget: auditing must never slow down or break a request.
        unawaited(_record(database, request, response));
      }
      return response;
    };
  };
}

bool _isMutating(String method) {
  final m = method.toUpperCase();
  return m == 'POST' || m == 'PUT' || m == 'PATCH' || m == 'DELETE';
}

// Resources whose mutations aren't meaningful "user actions" to surface.
const _skippedResources = {'auth', 'ws', 'admin', 'docs', 'audit'};

Future<void> _record(
  Database database,
  Request request,
  Response response,
) async {
  try {
    final segments =
        request.url.pathSegments.where((s) => s.isNotEmpty).toList();
    final resource = segments.isEmpty ? '' : segments.first;
    if (_skippedResources.contains(resource)) return;

    final actorId = await _resolveActorId(database, request);
    if (actorId == null) return; // anonymous / unauthenticated — nothing to attribute

    final described = _describe(request.method.toUpperCase(), segments);

    await Query<AuditLog>(AuditLogTable.metadata).insert(<String, Object?>{
      'actorId': actorId,
      'action': described.action,
      'targetType': described.targetType,
      'targetId': described.targetId,
      'ipAddress': _clientIp(request),
      'userAgent': request.headers['user-agent'],
      'data': jsonEncode(<String, Object?>{
        'method': request.method.toUpperCase(),
        'path': '/${request.url.path}',
        'status': response.statusCode,
      }),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).run(database.context());
  } catch (e) {
    logger.w('audit: failed to record action: $e');
  }
}

/// Resolve the acting user's id from the same credentials the authenticator
/// accepts (JWT bearer token or `gsl_` API token), without a full principal.
Future<int?> _resolveActorId(Database database, Request request) async {
  final token = _extractToken(request);
  if (token == null) return null;

  if (token.startsWith('gsl_')) {
    final apiToken = await Query<ApiToken>(ApiTokenTable.metadata)
        .where(ApiTokenTable.tokenHash.eq(ApiTokenCodec.hash(token)))
        .first(database.context());
    return apiToken?.userId;
  }

  final payload = JWTAuth.decodeAndVerify(token);
  return payload?['id'] as int?;
}

String? _extractToken(Request request) {
  final auth = request.headers['authorization'];
  if (auth != null) {
    final parts = auth.split(RegExp(r'\s+'));
    if (parts.length == 2 && parts.first.toLowerCase() == 'bearer') {
      return parts.last;
    }
  }
  final apiHeader = request.headers['x-api-token'];
  if (apiHeader != null && apiHeader.isNotEmpty) return apiHeader;
  return null;
}

String? _clientIp(Request request) {
  final fwd = request.headers['x-forwarded-for'];
  if (fwd != null && fwd.isNotEmpty) return fwd.split(',').first.trim();
  final info =
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
  return info?.remoteAddress.address;
}

/// Turn a request method + path into a stable, human-readable action plus the
/// target it acted on. Examples:
///   POST   /apps                     → app.create
///   PATCH  /apps/12                  → app.update      (app, 12)
///   DELETE /apps/12                  → app.delete      (app, 12)
///   POST   /apps/12/start            → app.start       (app, 12)
///   POST   /apps/12/deployments      → app.deploy      (app, 12)
///   POST   /apps/12/envs             → app.env.set     (app, 12)
///   DELETE /apps/12/envs/3           → app.env.unset   (app, 12)
///   POST   /teams/4/invitations      → team.invite     (team, 4)
({String action, String? targetType, String? targetId}) _describe(
  String method,
  List<String> seg,
) {
  if (seg.isEmpty) {
    return (action: method.toLowerCase(), targetType: null, targetId: null);
  }
  final targetType = _singular(seg.first);

  // The acted-on id is the first numeric segment after the resource.
  String? targetId;
  for (var i = 1; i < seg.length; i++) {
    if (int.tryParse(seg[i]) != null) {
      targetId = seg[i];
      break;
    }
  }

  // A trailing non-numeric segment (start, stop, deployments, envs, …) names a
  // sub-action; absent that, the verb follows from the HTTP method.
  final tail = seg.skip(1).where((s) => int.tryParse(s) == null).toList();
  final sub = tail.isEmpty ? null : tail.last;

  final fallback = switch (method) {
    'POST' => 'create',
    'PUT' || 'PATCH' => 'update',
    'DELETE' => 'delete',
    _ => method.toLowerCase(),
  };

  final verb = switch (sub) {
    null => fallback,
    'start' || 'stop' || 'restart' || 'exec' || 'rollback' => sub,
    'deployments' => 'deploy',
    'envs' || 'bulk' => method == 'DELETE' ? 'env.unset' : 'env.set',
    'invitations' => 'invite',
    _ => fallback,
  };

  return (action: '$targetType.$verb', targetType: targetType, targetId: targetId);
}

String _singular(String resource) {
  const map = {
    'apps': 'app',
    'projects': 'project',
    'teams': 'team',
    'domains': 'domain',
    'databases': 'database',
    'services': 'service',
    'deployments': 'deployment',
    'metrics': 'metric',
    'security': 'security',
    'mail': 'mail',
  };
  if (map.containsKey(resource)) return map[resource]!;
  if (resource.endsWith('s')) return resource.substring(0, resource.length - 1);
  return resource;
}
