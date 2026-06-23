/// Registry of the database engines the panel can manage.
///
/// This is the *seam* that keeps the Databases feature modular: the frontend
/// fetches [kDatabaseEngines] (via `GET /db-engines`) to discover which engines
/// exist and how to render their controls generically — versions, capabilities,
/// the user-permission options, backup scopes and the per-engine vocabulary.
///
/// Adding a new engine means: append a [DatabaseEngineDescriptor] here, add a
/// `<Engine>Service` (mirroring [PostgresService]/[MongoService]), a worker, a
/// controller, and the agent-side handler. Nothing in the UI is hardcoded per
/// engine beyond what this descriptor declares.
library gisila_panel.services.database_engine;

class DatabaseEngineDescriptor {
  const DatabaseEngineDescriptor({
    required this.key,
    required this.label,
    required this.kind,
    required this.apiBase,
    required this.versions,
    required this.defaultVersion,
    required this.capabilities,
    required this.userRoleOptions,
    required this.backupScopes,
    required this.terms,
    this.docsUrl,
  });

  /// Stable machine identifier: 'postgres' | 'mongodb'.
  final String key;
  final String label;

  /// 'sql' | 'nosql' — lets the UI group/badge engines.
  final String kind;

  /// REST base path of the engine's controller, e.g. '/databases', '/mongo'.
  final String apiBase;

  /// Installable versions, newest first.
  final List<String> versions;
  final String defaultVersion;

  /// Feature flags the UI uses to show/hide controls. Known keys:
  /// supportsExtensions, supportsUserRoles, supportsConfigTuning,
  /// supportsPublicExpose, supportsBackups.
  final Map<String, bool> capabilities;

  /// The set of per-user privileges/roles the UI offers when creating or
  /// editing a database user (pg role attributes vs Mongo built-in roles).
  final List<String> userRoleOptions;

  /// Backup scopes the engine supports (pg: full/schema/data, mongo: full).
  final List<String> backupScopes;

  /// Per-engine vocabulary so labels read naturally across engines. Known keys:
  /// instance, database, user, role, version.
  final Map<String, String> terms;

  final String? docsUrl;

  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'label': label,
        'kind': kind,
        'apiBase': apiBase,
        'versions': versions,
        'defaultVersion': defaultVersion,
        'capabilities': capabilities,
        'userRoleOptions': userRoleOptions,
        'backupScopes': backupScopes,
        'terms': terms,
        if (docsUrl != null) 'docsUrl': docsUrl,
      };
}

/// PostgreSQL role attributes an operator may toggle on a database user. Kept in
/// sync with `kRoleAttributes` in postgres_service.dart.
const _kPgRoleOptions = [
  'CREATEDB',
  'CREATEROLE',
  'REPLICATION',
  'SUPERUSER',
  'BYPASSRLS',
];

/// MongoDB built-in roles an operator may grant a database user. Kept in sync
/// with `kMongoRoles` in mongo_service.dart.
const _kMongoRoleOptions = [
  'read',
  'readWrite',
  'dbAdmin',
  'dbOwner',
  'readAnyDatabase',
  'readWriteAnyDatabase',
  'dbAdminAnyDatabase',
  'clusterMonitor',
];

const List<DatabaseEngineDescriptor> kDatabaseEngines = [
  DatabaseEngineDescriptor(
    key: 'postgres',
    label: 'PostgreSQL',
    kind: 'sql',
    apiBase: '/databases',
    versions: ['18', '17', '16', '15', '14'],
    defaultVersion: '17',
    docsUrl: 'https://www.postgresql.org/docs/',
    capabilities: {
      'supportsExtensions': true,
      'supportsUserRoles': true,
      'supportsConfigTuning': true,
      'supportsPublicExpose': true,
      'supportsBackups': true,
    },
    userRoleOptions: _kPgRoleOptions,
    backupScopes: ['full', 'schema', 'data'],
    terms: {
      'instance': 'Instance',
      'database': 'Database',
      'user': 'Role',
      'role': 'Role attribute',
      'version': 'Version',
    },
  ),
  DatabaseEngineDescriptor(
    key: 'mongodb',
    label: 'MongoDB',
    kind: 'nosql',
    apiBase: '/mongo',
    versions: ['8.0', '7.0', '6.0'],
    defaultVersion: '7.0',
    docsUrl: 'https://www.mongodb.com/docs/manual/',
    capabilities: {
      'supportsExtensions': false,
      'supportsUserRoles': true,
      'supportsConfigTuning': true,
      'supportsPublicExpose': true,
      'supportsBackups': true,
    },
    userRoleOptions: _kMongoRoleOptions,
    backupScopes: ['full'],
    terms: {
      'instance': 'Server',
      'database': 'Database',
      'user': 'User',
      'role': 'Role',
      'version': 'Version',
    },
  ),
];

DatabaseEngineDescriptor? findDatabaseEngine(String key) {
  for (final e in kDatabaseEngines) {
    if (e.key == key) return e;
  }
  return null;
}
