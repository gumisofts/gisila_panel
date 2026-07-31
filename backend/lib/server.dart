import 'dart:io';

import 'package:gisila_doc/gisila_doc.dart' hide Query;
import 'package:gisila_orm/gisila.dart' hide PostgresErrorMapper;
import 'package:shelf_static/shelf_static.dart';
import 'package:gisila_panel/admin.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_panel/utils/passwords.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/endpoints/apps.dart';
import 'package:gisila_panel/endpoints/applications.dart';
import 'package:gisila_panel/endpoints/audit.dart';
import 'package:gisila_panel/endpoints/auth.dart';
import 'package:gisila_panel/endpoints/deployments.dart';
import 'package:gisila_panel/endpoints/domains.dart';
import 'package:gisila_panel/endpoints/logs.dart' as live_logs;
import 'package:gisila_panel/endpoints/mail.dart';
import 'package:gisila_panel/endpoints/metrics.dart';
import 'package:gisila_panel/endpoints/projects.dart';
import 'package:gisila_panel/endpoints/security.dart';
import 'package:gisila_panel/endpoints/databases.dart';
import 'package:gisila_panel/endpoints/db_engines.dart';
import 'package:gisila_panel/endpoints/mongo.dart';
import 'package:gisila_panel/endpoints/services.dart';
import 'package:gisila_panel/endpoints/storage.dart';
import 'package:gisila_panel/endpoints/teams.dart';
import 'package:gisila_panel/infra/audit_middleware.dart';
import 'package:gisila_panel/infra/database_provider.dart';
import 'package:gisila_panel/infra/jwt_authenticator.dart';
import 'package:gisila_panel/infra/postgres_error_mapper.dart';
import 'package:gisila_panel/services/application_service.dart';
import 'package:gisila_panel/services/apps_service.dart';
import 'package:gisila_panel/services/audit_service.dart';
import 'package:gisila_panel/services/auth_service.dart';
import 'package:gisila_panel/services/deployments_service.dart';
import 'package:gisila_panel/services/domains_service.dart';
import 'package:gisila_panel/services/envs_service.dart';
import 'package:gisila_panel/services/lifecycle_service.dart';
import 'package:gisila_panel/services/projects_service.dart';
import 'package:gisila_panel/services/mail_service.dart';
import 'package:gisila_panel/services/managed_service_service.dart';
import 'package:gisila_panel/services/mongo_service.dart';
import 'package:gisila_panel/services/postgres_service.dart';
import 'package:gisila_panel/services/security_service.dart';
import 'package:gisila_panel/services/storage_service.dart';
import 'package:gisila_panel/services/teams_service.dart';

/// Build the top-level Shelf handler for the gisila-panel control plane.
Future<Handler> application() async {
  final spec = OpenApiSpec(
    info: const ApiInfo(
      title: 'Gisila Panel API',
      version: '0.1.0',
      description: 'Open-source lightweight PaaS control plane. Manage teams, '
          'projects, apps, deployments, domains, env vars, logs and metrics.',
    ),
  );

  final database = await Database.connect(databaseConfig);
  await _seedSuperuser(database);
  await _seedSystemInstance(database);

  final app = GisilaApp(
    config: AppConfig(
      cors: const CorsConfig(),
      requestTimeout: const Duration(seconds: 30),
      maxRequestBodyBytes: 50 * 1024 * 1024, // 50 MB (artifact uploads)
      serverHeader: 'gisila-panel/0.1.0',
      poweredByHeader: false,
      authenticator: JwtAuthenticator(database: database),
      database: GisilaOrmDatabaseProvider(database),
      dbErrorMapper: const PostgresDbErrorMapper(),
      defaultRouteConfig: const RouteConfig(
        rateLimit: RateLimitConfig(requestsPerMinute: 300),
      ),
    ),
  );

  // ── Services ─────────────────────────────────────────────────────────
  app.registerService<AuthService>(AuthService.new);
  app.registerService<TeamsService>(TeamsService.new);
  app.registerService<ProjectsService>(ProjectsService.new);
  app.registerService<AppsService>(AppsService.new);
  app.registerService<ApplicationService>(ApplicationService.new);
  app.registerService<EnvsService>(EnvsService.new);
  app.registerService<DeploymentsService>(DeploymentsService.new);
  app.registerService<DomainsService>(DomainsService.new);
  app.registerService<LifecycleService>(LifecycleService.new);
  app.registerService<SecurityService>(SecurityService.new);
  app.registerService<ManagedServiceService>(ManagedServiceService.new);
  app.registerService<PostgresService>(PostgresService.new);
  app.registerService<MongoService>(MongoService.new);
  app.registerService<StorageService>(StorageService.new);
  app.registerService<MailService>(MailService.new);
  app.registerService<AuditService>(AuditService.new);

  // Record every successful state-changing request to the AuditLog so the
  // Activity view reflects exactly what each user did.
  app.use(auditMiddleware(database));

  // ── Controllers + admin + docs ───────────────────────────────────────
  app.registerController(
    attacher: (app, router, {prefix = ''}) {
      AuthApi().attachToApp(app, router, spec, prefix: prefix);
      AuditApi().attachToApp(app, router, spec, prefix: prefix);
      TeamsApi().attachToApp(app, router, spec, prefix: prefix);
      ProjectsApi().attachToApp(app, router, spec, prefix: prefix);
      AppsApi().attachToApp(app, router, spec, prefix: prefix);
      ApplicationsApi().attachToApp(app, router, spec, prefix: prefix);
      DeploymentsApi().attachToApp(app, router, spec, prefix: prefix);
      DomainsApi().attachToApp(app, router, spec, prefix: prefix);
      MetricsApi().attachToApp(app, router, spec, prefix: prefix);
      SecurityApi().attachToApp(app, router, spec, prefix: prefix);
      ServicesApi().attachToApp(app, router, spec, prefix: prefix);
      DatabasesApi().attachToApp(app, router, spec, prefix: prefix);
      DbEnginesApi().attachToApp(app, router, spec, prefix: prefix);
      MongoApi().attachToApp(app, router, spec, prefix: prefix);
      StorageApi().attachToApp(app, router, spec, prefix: prefix);
      MailApi().attachToApp(app, router, spec, prefix: prefix);

      router.mount('/ws', live_logs.logsRouter(database: database).call);
      router.mount('/admin', adminHandler());
      router.mount('/docs', docsHandler(spec));
      router.mount('/', _panelUiHandler());
    },
  );

  // The panel is a client-routed SPA whose routes (`/apps/123`, `/projects`, …)
  // share the URL namespace with the API controllers above. Without this, a
  // hard browser refresh of a deep route is matched by the auth-protected API
  // route — the navigation carries no Bearer token, so the server answers with
  // a 401 JSON body instead of the app. Intercept top-level HTML navigations
  // and serve index.html so React Router can take over; real `fetch`/XHR API
  // calls (which send `Accept: */*` and the Bearer token) fall straight
  // through to the controllers untouched.
  return _spaNavigationFallback(app.buildHandler());
}

/// Wrap [inner] so browser navigations (GET requests that ask for `text/html`)
/// to non-API, non-asset paths are served the SPA shell instead of hitting the
/// API router. Everything else — API calls, WebSocket upgrades, the admin and
/// docs UIs, and static assets — is delegated to [inner] unchanged.
Handler _spaNavigationFallback(Handler inner) {
  final index = File('web/index.html');
  return (Request req) async {
    if (req.method == 'GET' &&
        _isSpaNavigation(req) &&
        index.existsSync()) {
      return Response.ok(
        index.readAsBytesSync(),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }
    return inner(req);
  };
}

bool _isSpaNavigation(Request req) {
  // Only genuine top-level navigations declare they want an HTML document;
  // `fetch`/XHR from the loaded app send `Accept: */*`, and sub-resource
  // requests (scripts, styles, images) advertise their own MIME types.
  final accept = req.headers['accept'] ?? '';
  if (!accept.contains('text/html')) return false;

  final segments = req.url.pathSegments;
  final first = segments.isEmpty ? '' : segments.first;
  // Tooling / API namespaces that own their own HTML or protocol handlers.
  const reserved = {'ws', 'admin', 'docs', 'openapi.json', 'assets', 'favicon.ico'};
  if (reserved.contains(first)) return false;

  // A static asset request (the last segment has a file extension) must reach
  // the static file handler, not the SPA shell.
  final last = segments.isEmpty ? '' : segments.last;
  if (last.contains('.')) return false;

  return true;
}

/// Public entry point called by `gisila-panel --seed-superuser` during
/// installation, and used as a safety net on every normal server startup.
Future<void> seedSuperuser() async {
  final database = await Database.connect(databaseConfig);
  try {
    await _seedSuperuser(database);
  } finally {
    await database.close();
  }
}

/// Seeds the initial superuser from env vars if no superuser exists yet.
///
/// Environment variables:
///   SUPERUSER_EMAIL    — e-mail for the initial superuser
///   SUPERUSER_PASSWORD — password for the initial superuser
///
/// If either variable is missing the seed is skipped.
Future<void> _seedSuperuser(Database database) async {
  final email = env['SUPERUSER_EMAIL'];
  final password = env['SUPERUSER_PASSWORD'];
  if (email == null || email.isEmpty || password == null || password.isEmpty) {
    return;
  }

  final existing = await Query<User>(UserTable.metadata)
      .where(UserTable.isSuperuser.eq(true))
      .first(database.context());

  if (existing != null) return; // superuser already exists

  logger.i('Seeding initial superuser: $email');
  final now = DateTime.now().toUtc();
  final user = await Query<User>(UserTable.metadata).insert(<String, Object?>{
    'email': email,
    'password': PasswordHasher.hash(password),
    'isActive': true,
    'isStaff': true,
    'isSuperuser': true,
    'isEmailVerified': true,
    'createdAt': now.toIso8601String(),
  }).one(database.context());

  final teamSlug = 'admin-${user.id}-team';
  final team = await Query<Team>(TeamTable.metadata).insert(<String, Object?>{
    'name': 'Administrators',
    'slug': teamSlug,
    'ownerId': user.id,
    'plan': 'free',
    'createdAt': now.toIso8601String(),
  }).one(database.context());

  await Query<TeamMember>(TeamMemberTable.metadata).insert(<String, Object?>{
    'teamId': team.id,
    'userId': user.id,
    'role': 'owner',
    'invitedAt': now.toIso8601String(),
    'acceptedAt': now.toIso8601String(),
  }).run(database.context());

  logger.i('Superuser seeded successfully (id=${user.id})');
}

/// Surfaces the always-available "system" Postgres instance — the cluster that
/// backs the panel itself ([systemPgPort] / [systemPgVersion]).
///
/// gisila_panel depends on this cluster, so rather than asking the operator to
/// install it or enter its details, we register it once as a read-only instance
/// the Databases panel can display automatically. It is matched by port (which
/// is unique), making this idempotent and safe to call on every startup. Its
/// port is never editable and its version is read from config, never requested.
///
/// Skipped when `server_version` is not configured in database.yaml.
Future<void> _seedSystemInstance(Database database) async {
  final version = systemPgVersion;
  if (version == null) return; // not configured — nothing to surface

  final port = systemPgPort;
  final existing = await Query<PostgresInstance>(PostgresInstanceTable.metadata)
      .where(PostgresInstanceTable.port.eq(port))
      .first(database.context());
  if (existing != null) return; // already seeded

  // Become the default instance only when no instance exists yet, mirroring
  // PostgresService.installInstance.
  final isFirst =
      await Query<PostgresInstance>(PostgresInstanceTable.metadata)
              .first(database.context()) ==
          null;

  logger.i('Seeding system Postgres instance: v$version on port $port');
  final now = DateTime.now().toUtc().toIso8601String();
  try {
    await Query<PostgresInstance>(PostgresInstanceTable.metadata)
        .insert(<String, Object?>{
      'version': version,
      'displayName': 'System database',
      'port': port,
      'status': 'running',
      'isDefault': isFirst,
      'dataDirectory': '/var/lib/postgresql/$version/main',
      'installedAt': now,
      'createdAt': now,
    }).run(database.context());
  } catch (e) {
    // The port column is unique — a concurrent isolate may have won the race.
    // That is the expected outcome here, not an error.
    logger.d('System instance seed skipped (already present?): $e');
  }
}

/// Serves the compiled panel UI from the `web/` directory.
/// Falls back to `index.html` for any path not matching a static asset so
/// that client-side React Router navigation works correctly.
Handler _panelUiHandler() {
  final webDir = Directory('web');
  if (!webDir.existsSync()) {
    return (Request req) => Response.ok(
          '<html><body>'
          '<h2>Panel UI not built</h2>'
          '<p>Run <code>pnpm build</code> inside <code>frontend/</code> first, '
          'or start the <code>frontend-build</code> service.</p>'
          '</body></html>',
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
  }

  final fileHandler = createStaticHandler(
    webDir.path,
    defaultDocument: 'index.html',
  );

  return (Request req) async {
    final response = await fileHandler(req);
    if (response.statusCode == 404) {
      final index = File('${webDir.path}/index.html');
      if (index.existsSync()) {
        return Response.ok(
          index.readAsBytesSync(),
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
    }
    return response;
  };
}
