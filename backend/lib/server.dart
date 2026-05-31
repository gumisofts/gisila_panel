import 'dart:io';

import 'package:gisila_doc/gisila_doc.dart';
import 'package:gisila_orm/gisila.dart' hide PostgresErrorMapper;
import 'package:shelf_static/shelf_static.dart';
import 'package:gisila_panel/admin.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/endpoints/apps.dart';
import 'package:gisila_panel/endpoints/auth.dart';
import 'package:gisila_panel/endpoints/deployments.dart';
import 'package:gisila_panel/endpoints/domains.dart';
import 'package:gisila_panel/endpoints/logs.dart' as live_logs;
import 'package:gisila_panel/endpoints/metrics.dart';
import 'package:gisila_panel/endpoints/projects.dart';
import 'package:gisila_panel/endpoints/security.dart';
import 'package:gisila_panel/endpoints/databases.dart';
import 'package:gisila_panel/endpoints/services.dart';
import 'package:gisila_panel/endpoints/teams.dart';
import 'package:gisila_panel/infra/database_provider.dart';
import 'package:gisila_panel/infra/jwt_authenticator.dart';
import 'package:gisila_panel/infra/postgres_error_mapper.dart';
import 'package:gisila_panel/services/apps_service.dart';
import 'package:gisila_panel/services/auth_service.dart';
import 'package:gisila_panel/services/deployments_service.dart';
import 'package:gisila_panel/services/domains_service.dart';
import 'package:gisila_panel/services/envs_service.dart';
import 'package:gisila_panel/services/lifecycle_service.dart';
import 'package:gisila_panel/services/projects_service.dart';
import 'package:gisila_panel/services/managed_service_service.dart';
import 'package:gisila_panel/services/postgres_service.dart';
import 'package:gisila_panel/services/security_service.dart';
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
  app.registerService<EnvsService>(EnvsService.new);
  app.registerService<DeploymentsService>(DeploymentsService.new);
  app.registerService<DomainsService>(DomainsService.new);
  app.registerService<LifecycleService>(LifecycleService.new);
  app.registerService<SecurityService>(SecurityService.new);
  app.registerService<ManagedServiceService>(ManagedServiceService.new);
  app.registerService<PostgresService>(PostgresService.new);

  // ── Controllers + admin + docs ───────────────────────────────────────
  app.registerController(
    attacher: (app, router, {prefix = ''}) {
      AuthApi().attachToApp(app, router, spec, prefix: prefix);
      TeamsApi().attachToApp(app, router, spec, prefix: prefix);
      ProjectsApi().attachToApp(app, router, spec, prefix: prefix);
      AppsApi().attachToApp(app, router, spec, prefix: prefix);
      DeploymentsApi().attachToApp(app, router, spec, prefix: prefix);
      DomainsApi().attachToApp(app, router, spec, prefix: prefix);
      MetricsApi().attachToApp(app, router, spec, prefix: prefix);
      SecurityApi().attachToApp(app, router, spec, prefix: prefix);
      ServicesApi().attachToApp(app, router, spec, prefix: prefix);
      DatabasesApi().attachToApp(app, router, spec, prefix: prefix);

      router.mount('/ws', live_logs.logsRouter(database: database).call);
      router.mount('/admin', adminHandler());
      router.mount('/docs', docsHandler(spec));
      router.mount('/', _panelUiHandler());
    },
  );

  return app.buildHandler();
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
