import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:gisila_studio/gisila_studio.dart';
import 'package:shelf/shelf.dart';

/// Mounts GisilaStudio at `/admin`. The DB pool is created lazily on the
/// first request so the studio shares the lifecycle of the rest of the app.
Handler adminHandler() {
  Handler? handler;
  return (Request req) async {
    handler ??= (await _buildStudio()).handler(prefix: '/admin');
    return handler!(req);
  };
}

Future<GisilaStudio> _buildStudio() async {
  final db = await Database.connect(databaseConfig);
  final studio = GisilaStudio(
    db: db,
    title: 'Gisila Panel',
    auth: JwtStudioAuth(
      username: env.getOrElse('STUDIO_USERNAME', () => 'admin'),
      password: env.getOrElse('STUDIO_PASSWORD', () => 'admin'),
      secret: env.getOrElse('JWT_SECRET', () => 'secret'),
    ),
  );

  // ── Identity & access ─────────────────────────────────────────────

  studio.register<User>(
    UserTable.metadata,
    displayName: 'User',
    listDisplay: [
      'id',
      'email',
      'firstName',
      'lastName',
      'isActive',
      'isStaff',
      'createdAt',
    ],
    searchFields: ['email', 'firstName', 'lastName'],
    readonlyFields: ['id', 'createdAt'],
    excludeFields: ['password'],
    ordering: ['-createdAt'],
    group: 'Identity',
  );

  studio.register<Team>(
    TeamTable.metadata,
    displayName: 'Team',
    listDisplay: ['id', 'name', 'slug', 'owner_id', 'plan', 'createdAt'],
    searchFields: ['name', 'slug'],
    readonlyFields: ['id', 'createdAt'],
    ordering: ['-createdAt'],
    group: 'Identity',
  );

  studio.register<TeamMember>(
    TeamMemberTable.metadata,
    displayName: 'Team Member',
    listDisplay: ['id', 'team_id', 'user_id', 'role', 'acceptedAt'],
    readonlyFields: ['id'],
    ordering: ['-id'],
    group: 'Identity',
  );

  studio.register<ApiToken>(
    ApiTokenTable.metadata,
    displayName: 'API Token',
    listDisplay: ['id', 'user_id', 'name', 'prefix', 'lastUsedAt', 'expiresAt'],
    readonlyFields: ['id', 'tokenHash', 'prefix', 'createdAt'],
    excludeFields: ['tokenHash'],
    ordering: ['-createdAt'],
    group: 'Identity',
  );

  studio.register<SshKey>(
    SshKeyTable.metadata,
    displayName: 'SSH Key',
    listDisplay: ['id', 'user_id', 'name', 'fingerprint', 'createdAt'],
    readonlyFields: ['id', 'fingerprint', 'createdAt'],
    ordering: ['-createdAt'],
    group: 'Identity',
  );

  // ── Projects & apps ───────────────────────────────────────────────

  studio.register<Project>(
    ProjectTable.metadata,
    displayName: 'Project',
    listDisplay: ['id', 'team_id', 'name', 'slug', 'createdAt'],
    searchFields: ['name', 'slug'],
    readonlyFields: ['id', 'createdAt'],
    ordering: ['-createdAt'],
    group: 'Projects',
  );

  studio.register<App>(
    AppTable.metadata,
    displayName: 'App',
    listDisplay: [
      'id',
      'project_id',
      'name',
      'linuxUser',
      'internalPort',
      'runtime',
      'status',
      'lastDeployedAt',
    ],
    searchFields: ['name', 'linuxUser'],
    readonlyFields: ['id', 'linuxUser', 'workDir', 'internalPort', 'createdAt'],
    ordering: ['-createdAt'],
    group: 'Projects',
  );

  studio.register<EnvVar>(
    EnvVarTable.metadata,
    displayName: 'Env Var',
    listDisplay: ['id', 'app_id', 'name', 'isSecret', 'updatedAt'],
    searchFields: ['name'],
    readonlyFields: ['id'],
    ordering: ['app_id', 'name'],
    group: 'Projects',
  );

  // ── Deployments ───────────────────────────────────────────────────

  studio.register<Deployment>(
    DeploymentTable.metadata,
    displayName: 'Deployment',
    listDisplay: [
      'id',
      'app_id',
      'sourceType',
      'gitCommitSha',
      'status',
      'isActive',
      'startedAt',
      'finishedAt',
    ],
    readonlyFields: ['id', 'createdAt'],
    ordering: ['-createdAt'],
    group: 'Deployments',
  );

  studio.register<BuildLog>(
    BuildLogTable.metadata,
    displayName: 'Build Log',
    listDisplay: ['id', 'deployment_id', 'stream', 'createdAt'],
    readonlyFields: ['id', 'createdAt'],
    ordering: ['-createdAt'],
    group: 'Deployments',
  );

  // ── Domains ───────────────────────────────────────────────────────

  studio.register<Domain>(
    DomainTable.metadata,
    displayName: 'Domain',
    listDisplay: [
      'id',
      'app_id',
      'hostname',
      'isPrimary',
      'isVerified',
      'sslStatus',
      'sslExpiresAt',
    ],
    searchFields: ['hostname'],
    readonlyFields: ['id', 'verificationToken', 'createdAt'],
    ordering: ['-createdAt'],
    group: 'Domains',
  );

  // ── Observability ─────────────────────────────────────────────────

  studio.register<MetricSample>(
    MetricSampleTable.metadata,
    displayName: 'Metric',
    displayNamePlural: 'Metrics',
    listDisplay: ['id', 'app_id', 'cpuPercent', 'memBytes', 'sampledAt'],
    readonlyFields: ['id', 'sampledAt'],
    ordering: ['-sampledAt'],
    group: 'Observability',
  );

  studio.register<AppEvent>(
    AppEventTable.metadata,
    displayName: 'App Event',
    listDisplay: ['id', 'app_id', 'actor_id', 'kind', 'createdAt'],
    readonlyFields: ['id', 'createdAt'],
    ordering: ['-createdAt'],
    group: 'Observability',
  );

  studio.register<AuditLog>(
    AuditLogTable.metadata,
    displayName: 'Audit Entry',
    listDisplay: ['id', 'actor_id', 'team_id', 'action', 'createdAt'],
    readonlyFields: ['id', 'createdAt'],
    ordering: ['-createdAt'],
    group: 'Observability',
  );

  return studio;
}
