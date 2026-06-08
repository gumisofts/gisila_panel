// GENERATED CODE - DO NOT MODIFY BY HAND
// Source: gisila build_runner schema generator.

// ignore_for_file: type=lint, unused_import

import 'package:gisila_orm/gisila.dart';

class User with Preloadable {
  final int? id;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? password;
  final bool? isActive;
  final bool? isStaff;
  final bool? isSuperuser;
  final bool? isEmailVerified;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;

  User({
    this.id,
    this.firstName,
    this.lastName,
    this.email,
    this.password,
    this.isActive,
    this.isStaff,
    this.isSuperuser,
    this.isEmailVerified,
    this.avatarUrl,
    required this.createdAt,
    this.updatedAt,
  });

  factory User.fromRow(Map<String, dynamic> row) => User(
    id: row['id'] as int?,
    firstName: row['first_name'] as String?,
    lastName: row['last_name'] as String?,
    email: row['email'] as String?,
    password: row['password'] as String?,
    isActive: row['is_active'] as bool?,
    isStaff: row['is_staff'] as bool?,
    isSuperuser: row['is_superuser'] as bool?,
    isEmailVerified: row['is_email_verified'] as bool?,
    avatarUrl: row['avatar_url'] as String?,
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
    updatedAt: row['updated_at'] == null
        ? null
        : (row['updated_at'] is DateTime
              ? row['updated_at'] as DateTime
              : DateTime.parse(row['updated_at'].toString())),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'first_name': firstName,
    'last_name': lastName,
    'email': email,
    'password': password,
    'is_active': isActive,
    'is_staff': isStaff,
    'is_superuser': isSuperuser,
    'is_email_verified': isEmailVerified,
    'avatar_url': avatarUrl,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory User.fromJson(Map<String, dynamic> json) => User.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  User copyWith({
    int? id,
    String? firstName,
    String? lastName,
    String? email,
    String? password,
    bool? isActive,
    bool? isStaff,
    bool? isSuperuser,
    bool? isEmailVerified,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => User(
    id: id ?? this.id,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    email: email ?? this.email,
    password: password ?? this.password,
    isActive: isActive ?? this.isActive,
    isStaff: isStaff ?? this.isStaff,
    isSuperuser: isSuperuser ?? this.isSuperuser,
    isEmailVerified: isEmailVerified ?? this.isEmailVerified,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static final Relation<User, Team> ownedTeams = HasManyRelation<User, Team>(
    parentTable: 'users',
    childTable: 'teams',
    name: 'ownedTeams',
    childForeignKey: 'owner_id',
    childMeta: TeamTable.metadata,
  );

  static final Relation<User, TeamMember> teamMemberships =
      HasManyRelation<User, TeamMember>(
        parentTable: 'users',
        childTable: 'team_members',
        name: 'teamMemberships',
        childForeignKey: 'user_id',
        childMeta: TeamMemberTable.metadata,
      );

  static final Relation<User, ApiToken> apiTokens =
      HasManyRelation<User, ApiToken>(
        parentTable: 'users',
        childTable: 'api_tokens',
        name: 'apiTokens',
        childForeignKey: 'user_id',
        childMeta: ApiTokenTable.metadata,
      );

  static final Relation<User, SshKey> sshKeys = HasManyRelation<User, SshKey>(
    parentTable: 'users',
    childTable: 'ssh_keys',
    name: 'sshKeys',
    childForeignKey: 'user_id',
    childMeta: SshKeyTable.metadata,
  );

  static final Relation<User, Deployment> triggeredDeployments =
      HasManyRelation<User, Deployment>(
        parentTable: 'users',
        childTable: 'deployments',
        name: 'triggeredDeployments',
        childForeignKey: 'triggered_by_id',
        childMeta: DeploymentTable.metadata,
      );

  static final Relation<User, AppEvent> appEvents =
      HasManyRelation<User, AppEvent>(
        parentTable: 'users',
        childTable: 'app_events',
        name: 'appEvents',
        childForeignKey: 'actor_id',
        childMeta: AppEventTable.metadata,
      );

  static final Relation<User, AuditLog> auditEntries =
      HasManyRelation<User, AuditLog>(
        parentTable: 'users',
        childTable: 'audit_logs',
        name: 'auditEntries',
        childForeignKey: 'actor_id',
        childMeta: AuditLogTable.metadata,
      );

  /// Preloaded ownedTeams; empty list when not preloaded.
  List<Team> get ownedTeamsList =>
      preloaded<List<Team>>('ownedTeams') ?? const [];

  /// Preloaded teamMemberships; empty list when not preloaded.
  List<TeamMember> get teamMembershipsList =>
      preloaded<List<TeamMember>>('teamMemberships') ?? const [];

  /// Preloaded apiTokens; empty list when not preloaded.
  List<ApiToken> get apiTokensList =>
      preloaded<List<ApiToken>>('apiTokens') ?? const [];

  /// Preloaded sshKeys; empty list when not preloaded.
  List<SshKey> get sshKeysList =>
      preloaded<List<SshKey>>('sshKeys') ?? const [];

  /// Preloaded triggeredDeployments; empty list when not preloaded.
  List<Deployment> get triggeredDeploymentsList =>
      preloaded<List<Deployment>>('triggeredDeployments') ?? const [];

  /// Preloaded appEvents; empty list when not preloaded.
  List<AppEvent> get appEventsList =>
      preloaded<List<AppEvent>>('appEvents') ?? const [];

  /// Preloaded auditEntries; empty list when not preloaded.
  List<AuditLog> get auditEntriesList =>
      preloaded<List<AuditLog>>('auditEntries') ?? const [];
}

class UserTable {
  UserTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'users',
    column: 'id',
  );
  static const ColumnRef<String?> firstName = ColumnRef<String?>(
    table: 'users',
    column: 'first_name',
  );
  static const ColumnRef<String?> lastName = ColumnRef<String?>(
    table: 'users',
    column: 'last_name',
  );
  static const ColumnRef<String?> email = ColumnRef<String?>(
    table: 'users',
    column: 'email',
  );
  static const ColumnRef<String?> password = ColumnRef<String?>(
    table: 'users',
    column: 'password',
  );
  static const ColumnRef<bool?> isActive = ColumnRef<bool?>(
    table: 'users',
    column: 'is_active',
  );
  static const ColumnRef<bool?> isStaff = ColumnRef<bool?>(
    table: 'users',
    column: 'is_staff',
  );
  static const ColumnRef<bool?> isSuperuser = ColumnRef<bool?>(
    table: 'users',
    column: 'is_superuser',
  );
  static const ColumnRef<bool?> isEmailVerified = ColumnRef<bool?>(
    table: 'users',
    column: 'is_email_verified',
  );
  static const ColumnRef<String?> avatarUrl = ColumnRef<String?>(
    table: 'users',
    column: 'avatar_url',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'users',
    column: 'created_at',
  );
  static const ColumnRef<DateTime?> updatedAt = ColumnRef<DateTime?>(
    table: 'users',
    column: 'updated_at',
  );

  static const TableMeta<User> metadata = TableMeta<User>(
    tableName: 'users',
    primaryKey: 'id',
    columnNames: [
      'id',
      'first_name',
      'last_name',
      'email',
      'password',
      'is_active',
      'is_staff',
      'is_superuser',
      'is_email_verified',
      'avatar_url',
      'created_at',
      'updated_at',
    ],
    fromRow: User.fromRow,
  );
}

Query<User> users() => Query<User>(UserTable.metadata);

class Team with Preloadable {
  final int? id;
  final String name;
  final String? slug;
  final int ownerId;
  final String? plan;
  final DateTime createdAt;

  Team({
    this.id,
    required this.name,
    this.slug,
    required this.ownerId,
    this.plan,
    required this.createdAt,
  });

  factory Team.fromRow(Map<String, dynamic> row) => Team(
    id: row['id'] as int?,
    name: row['name'] as String,
    slug: row['slug'] as String?,
    ownerId: row['owner_id'] as int,
    plan: row['plan'] as String?,
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'name': name,
    'slug': slug,
    'owner_id': ownerId,
    'plan': plan,
    'created_at': createdAt,
  };

  factory Team.fromJson(Map<String, dynamic> json) => Team.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  Team copyWith({
    int? id,
    String? name,
    String? slug,
    int? ownerId,
    String? plan,
    DateTime? createdAt,
  }) => Team(
    id: id ?? this.id,
    name: name ?? this.name,
    slug: slug ?? this.slug,
    ownerId: ownerId ?? this.ownerId,
    plan: plan ?? this.plan,
    createdAt: createdAt ?? this.createdAt,
  );

  static final Relation<Team, User> owner = BelongsToRelation<Team, User>(
    parentTable: 'teams',
    childTable: 'users',
    name: 'owner',
    parentForeignKey: 'owner_id',
    childMeta: UserTable.metadata,
  );

  static final Relation<Team, TeamMember> members =
      HasManyRelation<Team, TeamMember>(
        parentTable: 'teams',
        childTable: 'team_members',
        name: 'members',
        childForeignKey: 'team_id',
        childMeta: TeamMemberTable.metadata,
      );

  static final Relation<Team, Project> projects =
      HasManyRelation<Team, Project>(
        parentTable: 'teams',
        childTable: 'projects',
        name: 'projects',
        childForeignKey: 'team_id',
        childMeta: ProjectTable.metadata,
      );

  static final Relation<Team, AuditLog> auditEntries =
      HasManyRelation<Team, AuditLog>(
        parentTable: 'teams',
        childTable: 'audit_logs',
        name: 'auditEntries',
        childForeignKey: 'team_id',
        childMeta: AuditLogTable.metadata,
      );

  /// Preloaded owner; null when not preloaded or absent.
  User? get ownerLoaded => preloaded<User>('owner');

  /// Preloaded members; empty list when not preloaded.
  List<TeamMember> get membersList =>
      preloaded<List<TeamMember>>('members') ?? const [];

  /// Preloaded projects; empty list when not preloaded.
  List<Project> get projectsList =>
      preloaded<List<Project>>('projects') ?? const [];

  /// Preloaded auditEntries; empty list when not preloaded.
  List<AuditLog> get auditEntriesList =>
      preloaded<List<AuditLog>>('auditEntries') ?? const [];
}

class TeamTable {
  TeamTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'teams',
    column: 'id',
  );
  static const ColumnRef<String> name = ColumnRef<String>(
    table: 'teams',
    column: 'name',
  );
  static const ColumnRef<String?> slug = ColumnRef<String?>(
    table: 'teams',
    column: 'slug',
  );
  static const ColumnRef<int> ownerId = ColumnRef<int>(
    table: 'teams',
    column: 'owner_id',
  );
  static const ColumnRef<String?> plan = ColumnRef<String?>(
    table: 'teams',
    column: 'plan',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'teams',
    column: 'created_at',
  );

  static const TableMeta<Team> metadata = TableMeta<Team>(
    tableName: 'teams',
    primaryKey: 'id',
    columnNames: ['id', 'name', 'slug', 'owner_id', 'plan', 'created_at'],
    fromRow: Team.fromRow,
  );
}

Query<Team> teams() => Query<Team>(TeamTable.metadata);

class TeamMember with Preloadable {
  final int? id;
  final int teamId;
  final int userId;
  final String? role;
  final DateTime invitedAt;
  final DateTime? acceptedAt;

  TeamMember({
    this.id,
    required this.teamId,
    required this.userId,
    this.role,
    required this.invitedAt,
    this.acceptedAt,
  });

  factory TeamMember.fromRow(Map<String, dynamic> row) => TeamMember(
    id: row['id'] as int?,
    teamId: row['team_id'] as int,
    userId: row['user_id'] as int,
    role: row['role'] as String?,
    invitedAt: row['invited_at'] is DateTime
        ? row['invited_at'] as DateTime
        : DateTime.parse(row['invited_at'].toString()),
    acceptedAt: row['accepted_at'] == null
        ? null
        : (row['accepted_at'] is DateTime
              ? row['accepted_at'] as DateTime
              : DateTime.parse(row['accepted_at'].toString())),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'team_id': teamId,
    'user_id': userId,
    'role': role,
    'invited_at': invitedAt,
    'accepted_at': acceptedAt,
  };

  factory TeamMember.fromJson(Map<String, dynamic> json) =>
      TeamMember.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  TeamMember copyWith({
    int? id,
    int? teamId,
    int? userId,
    String? role,
    DateTime? invitedAt,
    DateTime? acceptedAt,
  }) => TeamMember(
    id: id ?? this.id,
    teamId: teamId ?? this.teamId,
    userId: userId ?? this.userId,
    role: role ?? this.role,
    invitedAt: invitedAt ?? this.invitedAt,
    acceptedAt: acceptedAt ?? this.acceptedAt,
  );

  static final Relation<TeamMember, Team> team =
      BelongsToRelation<TeamMember, Team>(
        parentTable: 'team_members',
        childTable: 'teams',
        name: 'team',
        parentForeignKey: 'team_id',
        childMeta: TeamTable.metadata,
      );

  static final Relation<TeamMember, User> user =
      BelongsToRelation<TeamMember, User>(
        parentTable: 'team_members',
        childTable: 'users',
        name: 'user',
        parentForeignKey: 'user_id',
        childMeta: UserTable.metadata,
      );

  /// Preloaded team; null when not preloaded or absent.
  Team? get teamLoaded => preloaded<Team>('team');

  /// Preloaded user; null when not preloaded or absent.
  User? get userLoaded => preloaded<User>('user');
}

class TeamMemberTable {
  TeamMemberTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'team_members',
    column: 'id',
  );
  static const ColumnRef<int> teamId = ColumnRef<int>(
    table: 'team_members',
    column: 'team_id',
  );
  static const ColumnRef<int> userId = ColumnRef<int>(
    table: 'team_members',
    column: 'user_id',
  );
  static const ColumnRef<String?> role = ColumnRef<String?>(
    table: 'team_members',
    column: 'role',
  );
  static const ColumnRef<DateTime> invitedAt = ColumnRef<DateTime>(
    table: 'team_members',
    column: 'invited_at',
  );
  static const ColumnRef<DateTime?> acceptedAt = ColumnRef<DateTime?>(
    table: 'team_members',
    column: 'accepted_at',
  );

  static const TableMeta<TeamMember> metadata = TableMeta<TeamMember>(
    tableName: 'team_members',
    primaryKey: 'id',
    columnNames: [
      'id',
      'team_id',
      'user_id',
      'role',
      'invited_at',
      'accepted_at',
    ],
    fromRow: TeamMember.fromRow,
  );
}

Query<TeamMember> teamMembers() => Query<TeamMember>(TeamMemberTable.metadata);

class ApiToken with Preloadable {
  final int? id;
  final int userId;
  final String name;
  final String? tokenHash;
  final String? prefix;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final DateTime createdAt;

  ApiToken({
    this.id,
    required this.userId,
    required this.name,
    this.tokenHash,
    this.prefix,
    this.lastUsedAt,
    this.expiresAt,
    required this.createdAt,
  });

  factory ApiToken.fromRow(Map<String, dynamic> row) => ApiToken(
    id: row['id'] as int?,
    userId: row['user_id'] as int,
    name: row['name'] as String,
    tokenHash: row['token_hash'] as String?,
    prefix: row['prefix'] as String?,
    lastUsedAt: row['last_used_at'] == null
        ? null
        : (row['last_used_at'] is DateTime
              ? row['last_used_at'] as DateTime
              : DateTime.parse(row['last_used_at'].toString())),
    expiresAt: row['expires_at'] == null
        ? null
        : (row['expires_at'] is DateTime
              ? row['expires_at'] as DateTime
              : DateTime.parse(row['expires_at'].toString())),
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'token_hash': tokenHash,
    'prefix': prefix,
    'last_used_at': lastUsedAt,
    'expires_at': expiresAt,
    'created_at': createdAt,
  };

  factory ApiToken.fromJson(Map<String, dynamic> json) =>
      ApiToken.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  ApiToken copyWith({
    int? id,
    int? userId,
    String? name,
    String? tokenHash,
    String? prefix,
    DateTime? lastUsedAt,
    DateTime? expiresAt,
    DateTime? createdAt,
  }) => ApiToken(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    tokenHash: tokenHash ?? this.tokenHash,
    prefix: prefix ?? this.prefix,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    createdAt: createdAt ?? this.createdAt,
  );

  static final Relation<ApiToken, User> user =
      BelongsToRelation<ApiToken, User>(
        parentTable: 'api_tokens',
        childTable: 'users',
        name: 'user',
        parentForeignKey: 'user_id',
        childMeta: UserTable.metadata,
      );

  /// Preloaded user; null when not preloaded or absent.
  User? get userLoaded => preloaded<User>('user');
}

class ApiTokenTable {
  ApiTokenTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'api_tokens',
    column: 'id',
  );
  static const ColumnRef<int> userId = ColumnRef<int>(
    table: 'api_tokens',
    column: 'user_id',
  );
  static const ColumnRef<String> name = ColumnRef<String>(
    table: 'api_tokens',
    column: 'name',
  );
  static const ColumnRef<String?> tokenHash = ColumnRef<String?>(
    table: 'api_tokens',
    column: 'token_hash',
  );
  static const ColumnRef<String?> prefix = ColumnRef<String?>(
    table: 'api_tokens',
    column: 'prefix',
  );
  static const ColumnRef<DateTime?> lastUsedAt = ColumnRef<DateTime?>(
    table: 'api_tokens',
    column: 'last_used_at',
  );
  static const ColumnRef<DateTime?> expiresAt = ColumnRef<DateTime?>(
    table: 'api_tokens',
    column: 'expires_at',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'api_tokens',
    column: 'created_at',
  );

  static const TableMeta<ApiToken> metadata = TableMeta<ApiToken>(
    tableName: 'api_tokens',
    primaryKey: 'id',
    columnNames: [
      'id',
      'user_id',
      'name',
      'token_hash',
      'prefix',
      'last_used_at',
      'expires_at',
      'created_at',
    ],
    fromRow: ApiToken.fromRow,
  );
}

Query<ApiToken> apiTokens() => Query<ApiToken>(ApiTokenTable.metadata);

class SshKey with Preloadable {
  final int? id;
  final int userId;
  final String name;
  final String? algorithm;
  final String publicKey;
  final String? privateKey;
  final bool? isDeployKey;
  final String? fingerprint;
  final DateTime createdAt;

  SshKey({
    this.id,
    required this.userId,
    required this.name,
    this.algorithm,
    required this.publicKey,
    this.privateKey,
    this.isDeployKey,
    this.fingerprint,
    required this.createdAt,
  });

  factory SshKey.fromRow(Map<String, dynamic> row) => SshKey(
    id: row['id'] as int?,
    userId: row['user_id'] as int,
    name: row['name'] as String,
    algorithm: row['algorithm'] as String?,
    publicKey: row['public_key'] as String,
    privateKey: row['private_key'] as String?,
    isDeployKey: row['is_deploy_key'] as bool?,
    fingerprint: row['fingerprint'] as String?,
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'algorithm': algorithm,
    'public_key': publicKey,
    'private_key': privateKey,
    'is_deploy_key': isDeployKey,
    'fingerprint': fingerprint,
    'created_at': createdAt,
  };

  factory SshKey.fromJson(Map<String, dynamic> json) => SshKey.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  SshKey copyWith({
    int? id,
    int? userId,
    String? name,
    String? algorithm,
    String? publicKey,
    String? privateKey,
    bool? isDeployKey,
    String? fingerprint,
    DateTime? createdAt,
  }) => SshKey(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    algorithm: algorithm ?? this.algorithm,
    publicKey: publicKey ?? this.publicKey,
    privateKey: privateKey ?? this.privateKey,
    isDeployKey: isDeployKey ?? this.isDeployKey,
    fingerprint: fingerprint ?? this.fingerprint,
    createdAt: createdAt ?? this.createdAt,
  );

  static final Relation<SshKey, User> user = BelongsToRelation<SshKey, User>(
    parentTable: 'ssh_keys',
    childTable: 'users',
    name: 'user',
    parentForeignKey: 'user_id',
    childMeta: UserTable.metadata,
  );

  static final Relation<SshKey, App> deployedApps =
      HasManyRelation<SshKey, App>(
        parentTable: 'ssh_keys',
        childTable: 'apps',
        name: 'deployedApps',
        childForeignKey: 'deploy_key_id',
        childMeta: AppTable.metadata,
      );

  /// Preloaded user; null when not preloaded or absent.
  User? get userLoaded => preloaded<User>('user');

  /// Preloaded deployedApps; empty list when not preloaded.
  List<App> get deployedAppsList =>
      preloaded<List<App>>('deployedApps') ?? const [];
}

class SshKeyTable {
  SshKeyTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'ssh_keys',
    column: 'id',
  );
  static const ColumnRef<int> userId = ColumnRef<int>(
    table: 'ssh_keys',
    column: 'user_id',
  );
  static const ColumnRef<String> name = ColumnRef<String>(
    table: 'ssh_keys',
    column: 'name',
  );
  static const ColumnRef<String?> algorithm = ColumnRef<String?>(
    table: 'ssh_keys',
    column: 'algorithm',
  );
  static const ColumnRef<String> publicKey = ColumnRef<String>(
    table: 'ssh_keys',
    column: 'public_key',
  );
  static const ColumnRef<String?> privateKey = ColumnRef<String?>(
    table: 'ssh_keys',
    column: 'private_key',
  );
  static const ColumnRef<bool?> isDeployKey = ColumnRef<bool?>(
    table: 'ssh_keys',
    column: 'is_deploy_key',
  );
  static const ColumnRef<String?> fingerprint = ColumnRef<String?>(
    table: 'ssh_keys',
    column: 'fingerprint',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'ssh_keys',
    column: 'created_at',
  );

  static const TableMeta<SshKey> metadata = TableMeta<SshKey>(
    tableName: 'ssh_keys',
    primaryKey: 'id',
    columnNames: [
      'id',
      'user_id',
      'name',
      'algorithm',
      'public_key',
      'private_key',
      'is_deploy_key',
      'fingerprint',
      'created_at',
    ],
    fromRow: SshKey.fromRow,
  );
}

Query<SshKey> sshKeys() => Query<SshKey>(SshKeyTable.metadata);

class Project with Preloadable {
  final int? id;
  final int teamId;
  final String name;
  final String? slug;
  final String? description;
  final DateTime createdAt;

  Project({
    this.id,
    required this.teamId,
    required this.name,
    this.slug,
    this.description,
    required this.createdAt,
  });

  factory Project.fromRow(Map<String, dynamic> row) => Project(
    id: row['id'] as int?,
    teamId: row['team_id'] as int,
    name: row['name'] as String,
    slug: row['slug'] as String?,
    description: row['description'] as String?,
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'team_id': teamId,
    'name': name,
    'slug': slug,
    'description': description,
    'created_at': createdAt,
  };

  factory Project.fromJson(Map<String, dynamic> json) => Project.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  Project copyWith({
    int? id,
    int? teamId,
    String? name,
    String? slug,
    String? description,
    DateTime? createdAt,
  }) => Project(
    id: id ?? this.id,
    teamId: teamId ?? this.teamId,
    name: name ?? this.name,
    slug: slug ?? this.slug,
    description: description ?? this.description,
    createdAt: createdAt ?? this.createdAt,
  );

  static final Relation<Project, Team> team = BelongsToRelation<Project, Team>(
    parentTable: 'projects',
    childTable: 'teams',
    name: 'team',
    parentForeignKey: 'team_id',
    childMeta: TeamTable.metadata,
  );

  static final Relation<Project, App> apps = HasManyRelation<Project, App>(
    parentTable: 'projects',
    childTable: 'apps',
    name: 'apps',
    childForeignKey: 'project_id',
    childMeta: AppTable.metadata,
  );

  /// Preloaded team; null when not preloaded or absent.
  Team? get teamLoaded => preloaded<Team>('team');

  /// Preloaded apps; empty list when not preloaded.
  List<App> get appsList => preloaded<List<App>>('apps') ?? const [];
}

class ProjectTable {
  ProjectTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'projects',
    column: 'id',
  );
  static const ColumnRef<int> teamId = ColumnRef<int>(
    table: 'projects',
    column: 'team_id',
  );
  static const ColumnRef<String> name = ColumnRef<String>(
    table: 'projects',
    column: 'name',
  );
  static const ColumnRef<String?> slug = ColumnRef<String?>(
    table: 'projects',
    column: 'slug',
  );
  static const ColumnRef<String?> description = ColumnRef<String?>(
    table: 'projects',
    column: 'description',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'projects',
    column: 'created_at',
  );

  static const TableMeta<Project> metadata = TableMeta<Project>(
    tableName: 'projects',
    primaryKey: 'id',
    columnNames: ['id', 'team_id', 'name', 'slug', 'description', 'created_at'],
    fromRow: Project.fromRow,
  );
}

Query<Project> projects() => Query<Project>(ProjectTable.metadata);

class App with Preloadable {
  final int? id;
  final int projectId;
  final String name;
  final String? slug;
  final String? linuxUser;
  final String workDir;
  final int? internalPort;
  final String runtime;
  final String sourceType;
  final String? gitUrl;
  final String? gitBranch;
  final String? buildCommand;
  final String? startCommand;
  final String? healthCheckPath;
  final int? deployKeyId;
  final String? pythonVersion;
  final String? pythonMode;
  final String? wsgiApp;
  final int? gunicornWorkers;
  final int? gunicornThreads;
  final int? gunicornTimeout;
  final String? gunicornBind;
  final String? gunicornExtraArgs;
  final String? nodeVersion;
  final String? dartVersion;
  final String? goVersion;
  final String? rustVersion;
  final String? bunVersion;
  final String? celeryApp;
  final int? celeryWorkerCount;
  final int? celeryConcurrency;
  final String? celeryQueues;
  final bool? celeryBeatEnabled;
  final String? celeryExtraArgs;
  final String? staticRoot;
  final bool? staticSpa;
  final int? memoryMbLimit;
  final int? cpuQuotaPercent;
  final int? tasksLimit;
  final String? status;
  final DateTime? lastDeployedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  App({
    this.id,
    required this.projectId,
    required this.name,
    this.slug,
    this.linuxUser,
    required this.workDir,
    this.internalPort,
    required this.runtime,
    required this.sourceType,
    this.gitUrl,
    this.gitBranch,
    this.buildCommand,
    this.startCommand,
    this.healthCheckPath,
    this.deployKeyId,
    this.pythonVersion,
    this.pythonMode,
    this.wsgiApp,
    this.gunicornWorkers,
    this.gunicornThreads,
    this.gunicornTimeout,
    this.gunicornBind,
    this.gunicornExtraArgs,
    this.nodeVersion,
    this.dartVersion,
    this.goVersion,
    this.rustVersion,
    this.bunVersion,
    this.celeryApp,
    this.celeryWorkerCount,
    this.celeryConcurrency,
    this.celeryQueues,
    this.celeryBeatEnabled,
    this.celeryExtraArgs,
    this.staticRoot,
    this.staticSpa,
    this.memoryMbLimit,
    this.cpuQuotaPercent,
    this.tasksLimit,
    this.status,
    this.lastDeployedAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory App.fromRow(Map<String, dynamic> row) => App(
    id: row['id'] as int?,
    projectId: row['project_id'] as int,
    name: row['name'] as String,
    slug: row['slug'] as String?,
    linuxUser: row['linux_user'] as String?,
    workDir: row['work_dir'] as String,
    internalPort: row['internal_port'] as int?,
    runtime: row['runtime'] as String,
    sourceType: row['source_type'] as String,
    gitUrl: row['git_url'] as String?,
    gitBranch: row['git_branch'] as String?,
    buildCommand: row['build_command'] as String?,
    startCommand: row['start_command'] as String?,
    healthCheckPath: row['health_check_path'] as String?,
    deployKeyId: row['deploy_key_id'] as int?,
    pythonVersion: row['python_version'] as String?,
    pythonMode: row['python_mode'] as String?,
    wsgiApp: row['wsgi_app'] as String?,
    gunicornWorkers: row['gunicorn_workers'] as int?,
    gunicornThreads: row['gunicorn_threads'] as int?,
    gunicornTimeout: row['gunicorn_timeout'] as int?,
    gunicornBind: row['gunicorn_bind'] as String?,
    gunicornExtraArgs: row['gunicorn_extra_args'] as String?,
    nodeVersion: row['node_version'] as String?,
    dartVersion: row['dart_version'] as String?,
    goVersion: row['go_version'] as String?,
    rustVersion: row['rust_version'] as String?,
    bunVersion: row['bun_version'] as String?,
    celeryApp: row['celery_app'] as String?,
    celeryWorkerCount: row['celery_worker_count'] as int?,
    celeryConcurrency: row['celery_concurrency'] as int?,
    celeryQueues: row['celery_queues'] as String?,
    celeryBeatEnabled: row['celery_beat_enabled'] as bool?,
    celeryExtraArgs: row['celery_extra_args'] as String?,
    staticRoot: row['static_root'] as String?,
    staticSpa: row['static_spa'] as bool?,
    memoryMbLimit: row['memory_mb_limit'] as int?,
    cpuQuotaPercent: row['cpu_quota_percent'] as int?,
    tasksLimit: row['tasks_limit'] as int?,
    status: row['status'] as String?,
    lastDeployedAt: row['last_deployed_at'] == null
        ? null
        : (row['last_deployed_at'] is DateTime
              ? row['last_deployed_at'] as DateTime
              : DateTime.parse(row['last_deployed_at'].toString())),
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
    updatedAt: row['updated_at'] == null
        ? null
        : (row['updated_at'] is DateTime
              ? row['updated_at'] as DateTime
              : DateTime.parse(row['updated_at'].toString())),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'project_id': projectId,
    'name': name,
    'slug': slug,
    'linux_user': linuxUser,
    'work_dir': workDir,
    'internal_port': internalPort,
    'runtime': runtime,
    'source_type': sourceType,
    'git_url': gitUrl,
    'git_branch': gitBranch,
    'build_command': buildCommand,
    'start_command': startCommand,
    'health_check_path': healthCheckPath,
    'deploy_key_id': deployKeyId,
    'python_version': pythonVersion,
    'python_mode': pythonMode,
    'wsgi_app': wsgiApp,
    'gunicorn_workers': gunicornWorkers,
    'gunicorn_threads': gunicornThreads,
    'gunicorn_timeout': gunicornTimeout,
    'gunicorn_bind': gunicornBind,
    'gunicorn_extra_args': gunicornExtraArgs,
    'node_version': nodeVersion,
    'dart_version': dartVersion,
    'go_version': goVersion,
    'rust_version': rustVersion,
    'bun_version': bunVersion,
    'celery_app': celeryApp,
    'celery_worker_count': celeryWorkerCount,
    'celery_concurrency': celeryConcurrency,
    'celery_queues': celeryQueues,
    'celery_beat_enabled': celeryBeatEnabled,
    'celery_extra_args': celeryExtraArgs,
    'static_root': staticRoot,
    'static_spa': staticSpa,
    'memory_mb_limit': memoryMbLimit,
    'cpu_quota_percent': cpuQuotaPercent,
    'tasks_limit': tasksLimit,
    'status': status,
    'last_deployed_at': lastDeployedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory App.fromJson(Map<String, dynamic> json) => App.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  App copyWith({
    int? id,
    int? projectId,
    String? name,
    String? slug,
    String? linuxUser,
    String? workDir,
    int? internalPort,
    String? runtime,
    String? sourceType,
    String? gitUrl,
    String? gitBranch,
    String? buildCommand,
    String? startCommand,
    String? healthCheckPath,
    int? deployKeyId,
    String? pythonVersion,
    String? pythonMode,
    String? wsgiApp,
    int? gunicornWorkers,
    int? gunicornThreads,
    int? gunicornTimeout,
    String? gunicornBind,
    String? gunicornExtraArgs,
    String? nodeVersion,
    String? dartVersion,
    String? goVersion,
    String? rustVersion,
    String? bunVersion,
    String? celeryApp,
    int? celeryWorkerCount,
    int? celeryConcurrency,
    String? celeryQueues,
    bool? celeryBeatEnabled,
    String? celeryExtraArgs,
    String? staticRoot,
    bool? staticSpa,
    int? memoryMbLimit,
    int? cpuQuotaPercent,
    int? tasksLimit,
    String? status,
    DateTime? lastDeployedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => App(
    id: id ?? this.id,
    projectId: projectId ?? this.projectId,
    name: name ?? this.name,
    slug: slug ?? this.slug,
    linuxUser: linuxUser ?? this.linuxUser,
    workDir: workDir ?? this.workDir,
    internalPort: internalPort ?? this.internalPort,
    runtime: runtime ?? this.runtime,
    sourceType: sourceType ?? this.sourceType,
    gitUrl: gitUrl ?? this.gitUrl,
    gitBranch: gitBranch ?? this.gitBranch,
    buildCommand: buildCommand ?? this.buildCommand,
    startCommand: startCommand ?? this.startCommand,
    healthCheckPath: healthCheckPath ?? this.healthCheckPath,
    deployKeyId: deployKeyId ?? this.deployKeyId,
    pythonVersion: pythonVersion ?? this.pythonVersion,
    pythonMode: pythonMode ?? this.pythonMode,
    wsgiApp: wsgiApp ?? this.wsgiApp,
    gunicornWorkers: gunicornWorkers ?? this.gunicornWorkers,
    gunicornThreads: gunicornThreads ?? this.gunicornThreads,
    gunicornTimeout: gunicornTimeout ?? this.gunicornTimeout,
    gunicornBind: gunicornBind ?? this.gunicornBind,
    gunicornExtraArgs: gunicornExtraArgs ?? this.gunicornExtraArgs,
    nodeVersion: nodeVersion ?? this.nodeVersion,
    dartVersion: dartVersion ?? this.dartVersion,
    goVersion: goVersion ?? this.goVersion,
    rustVersion: rustVersion ?? this.rustVersion,
    bunVersion: bunVersion ?? this.bunVersion,
    celeryApp: celeryApp ?? this.celeryApp,
    celeryWorkerCount: celeryWorkerCount ?? this.celeryWorkerCount,
    celeryConcurrency: celeryConcurrency ?? this.celeryConcurrency,
    celeryQueues: celeryQueues ?? this.celeryQueues,
    celeryBeatEnabled: celeryBeatEnabled ?? this.celeryBeatEnabled,
    celeryExtraArgs: celeryExtraArgs ?? this.celeryExtraArgs,
    staticRoot: staticRoot ?? this.staticRoot,
    staticSpa: staticSpa ?? this.staticSpa,
    memoryMbLimit: memoryMbLimit ?? this.memoryMbLimit,
    cpuQuotaPercent: cpuQuotaPercent ?? this.cpuQuotaPercent,
    tasksLimit: tasksLimit ?? this.tasksLimit,
    status: status ?? this.status,
    lastDeployedAt: lastDeployedAt ?? this.lastDeployedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static final Relation<App, Project> project = BelongsToRelation<App, Project>(
    parentTable: 'apps',
    childTable: 'projects',
    name: 'project',
    parentForeignKey: 'project_id',
    childMeta: ProjectTable.metadata,
  );

  static final Relation<App, SshKey> deployKey = BelongsToRelation<App, SshKey>(
    parentTable: 'apps',
    childTable: 'ssh_keys',
    name: 'deployKey',
    parentForeignKey: 'deploy_key_id',
    childMeta: SshKeyTable.metadata,
  );

  static final Relation<App, EnvVar> envVars = HasManyRelation<App, EnvVar>(
    parentTable: 'apps',
    childTable: 'env_vars',
    name: 'envVars',
    childForeignKey: 'app_id',
    childMeta: EnvVarTable.metadata,
  );

  static final Relation<App, Deployment> deployments =
      HasManyRelation<App, Deployment>(
        parentTable: 'apps',
        childTable: 'deployments',
        name: 'deployments',
        childForeignKey: 'app_id',
        childMeta: DeploymentTable.metadata,
      );

  static final Relation<App, Domain> domains = HasManyRelation<App, Domain>(
    parentTable: 'apps',
    childTable: 'domains',
    name: 'domains',
    childForeignKey: 'app_id',
    childMeta: DomainTable.metadata,
  );

  static final Relation<App, MetricSample> metrics =
      HasManyRelation<App, MetricSample>(
        parentTable: 'apps',
        childTable: 'metric_samples',
        name: 'metrics',
        childForeignKey: 'app_id',
        childMeta: MetricSampleTable.metadata,
      );

  static final Relation<App, AppEvent> events = HasManyRelation<App, AppEvent>(
    parentTable: 'apps',
    childTable: 'app_events',
    name: 'events',
    childForeignKey: 'app_id',
    childMeta: AppEventTable.metadata,
  );

  /// Preloaded project; null when not preloaded or absent.
  Project? get projectLoaded => preloaded<Project>('project');

  /// Preloaded deployKey; null when not preloaded or absent.
  SshKey? get deployKeyLoaded => preloaded<SshKey>('deployKey');

  /// Preloaded envVars; empty list when not preloaded.
  List<EnvVar> get envVarsList =>
      preloaded<List<EnvVar>>('envVars') ?? const [];

  /// Preloaded deployments; empty list when not preloaded.
  List<Deployment> get deploymentsList =>
      preloaded<List<Deployment>>('deployments') ?? const [];

  /// Preloaded domains; empty list when not preloaded.
  List<Domain> get domainsList =>
      preloaded<List<Domain>>('domains') ?? const [];

  /// Preloaded metrics; empty list when not preloaded.
  List<MetricSample> get metricsList =>
      preloaded<List<MetricSample>>('metrics') ?? const [];

  /// Preloaded events; empty list when not preloaded.
  List<AppEvent> get eventsList =>
      preloaded<List<AppEvent>>('events') ?? const [];
}

class AppTable {
  AppTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'apps',
    column: 'id',
  );
  static const ColumnRef<int> projectId = ColumnRef<int>(
    table: 'apps',
    column: 'project_id',
  );
  static const ColumnRef<String> name = ColumnRef<String>(
    table: 'apps',
    column: 'name',
  );
  static const ColumnRef<String?> slug = ColumnRef<String?>(
    table: 'apps',
    column: 'slug',
  );
  static const ColumnRef<String?> linuxUser = ColumnRef<String?>(
    table: 'apps',
    column: 'linux_user',
  );
  static const ColumnRef<String> workDir = ColumnRef<String>(
    table: 'apps',
    column: 'work_dir',
  );
  static const ColumnRef<int?> internalPort = ColumnRef<int?>(
    table: 'apps',
    column: 'internal_port',
  );
  static const ColumnRef<String> runtime = ColumnRef<String>(
    table: 'apps',
    column: 'runtime',
  );
  static const ColumnRef<String> sourceType = ColumnRef<String>(
    table: 'apps',
    column: 'source_type',
  );
  static const ColumnRef<String?> gitUrl = ColumnRef<String?>(
    table: 'apps',
    column: 'git_url',
  );
  static const ColumnRef<String?> gitBranch = ColumnRef<String?>(
    table: 'apps',
    column: 'git_branch',
  );
  static const ColumnRef<String?> buildCommand = ColumnRef<String?>(
    table: 'apps',
    column: 'build_command',
  );
  static const ColumnRef<String?> startCommand = ColumnRef<String?>(
    table: 'apps',
    column: 'start_command',
  );
  static const ColumnRef<String?> healthCheckPath = ColumnRef<String?>(
    table: 'apps',
    column: 'health_check_path',
  );
  static const ColumnRef<int?> deployKeyId = ColumnRef<int?>(
    table: 'apps',
    column: 'deploy_key_id',
  );
  static const ColumnRef<String?> pythonVersion = ColumnRef<String?>(
    table: 'apps',
    column: 'python_version',
  );
  static const ColumnRef<String?> pythonMode = ColumnRef<String?>(
    table: 'apps',
    column: 'python_mode',
  );
  static const ColumnRef<String?> wsgiApp = ColumnRef<String?>(
    table: 'apps',
    column: 'wsgi_app',
  );
  static const ColumnRef<int?> gunicornWorkers = ColumnRef<int?>(
    table: 'apps',
    column: 'gunicorn_workers',
  );
  static const ColumnRef<int?> gunicornThreads = ColumnRef<int?>(
    table: 'apps',
    column: 'gunicorn_threads',
  );
  static const ColumnRef<int?> gunicornTimeout = ColumnRef<int?>(
    table: 'apps',
    column: 'gunicorn_timeout',
  );
  static const ColumnRef<String?> gunicornBind = ColumnRef<String?>(
    table: 'apps',
    column: 'gunicorn_bind',
  );
  static const ColumnRef<String?> gunicornExtraArgs = ColumnRef<String?>(
    table: 'apps',
    column: 'gunicorn_extra_args',
  );
  static const ColumnRef<String?> nodeVersion = ColumnRef<String?>(
    table: 'apps',
    column: 'node_version',
  );
  static const ColumnRef<String?> dartVersion = ColumnRef<String?>(
    table: 'apps',
    column: 'dart_version',
  );
  static const ColumnRef<String?> goVersion = ColumnRef<String?>(
    table: 'apps',
    column: 'go_version',
  );
  static const ColumnRef<String?> rustVersion = ColumnRef<String?>(
    table: 'apps',
    column: 'rust_version',
  );
  static const ColumnRef<String?> bunVersion = ColumnRef<String?>(
    table: 'apps',
    column: 'bun_version',
  );
  static const ColumnRef<String?> celeryApp = ColumnRef<String?>(
    table: 'apps',
    column: 'celery_app',
  );
  static const ColumnRef<int?> celeryWorkerCount = ColumnRef<int?>(
    table: 'apps',
    column: 'celery_worker_count',
  );
  static const ColumnRef<int?> celeryConcurrency = ColumnRef<int?>(
    table: 'apps',
    column: 'celery_concurrency',
  );
  static const ColumnRef<String?> celeryQueues = ColumnRef<String?>(
    table: 'apps',
    column: 'celery_queues',
  );
  static const ColumnRef<bool?> celeryBeatEnabled = ColumnRef<bool?>(
    table: 'apps',
    column: 'celery_beat_enabled',
  );
  static const ColumnRef<String?> celeryExtraArgs = ColumnRef<String?>(
    table: 'apps',
    column: 'celery_extra_args',
  );
  static const ColumnRef<String?> staticRoot = ColumnRef<String?>(
    table: 'apps',
    column: 'static_root',
  );
  static const ColumnRef<bool?> staticSpa = ColumnRef<bool?>(
    table: 'apps',
    column: 'static_spa',
  );
  static const ColumnRef<int?> memoryMbLimit = ColumnRef<int?>(
    table: 'apps',
    column: 'memory_mb_limit',
  );
  static const ColumnRef<int?> cpuQuotaPercent = ColumnRef<int?>(
    table: 'apps',
    column: 'cpu_quota_percent',
  );
  static const ColumnRef<int?> tasksLimit = ColumnRef<int?>(
    table: 'apps',
    column: 'tasks_limit',
  );
  static const ColumnRef<String?> status = ColumnRef<String?>(
    table: 'apps',
    column: 'status',
  );
  static const ColumnRef<DateTime?> lastDeployedAt = ColumnRef<DateTime?>(
    table: 'apps',
    column: 'last_deployed_at',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'apps',
    column: 'created_at',
  );
  static const ColumnRef<DateTime?> updatedAt = ColumnRef<DateTime?>(
    table: 'apps',
    column: 'updated_at',
  );

  static const TableMeta<App> metadata = TableMeta<App>(
    tableName: 'apps',
    primaryKey: 'id',
    columnNames: [
      'id',
      'project_id',
      'name',
      'slug',
      'linux_user',
      'work_dir',
      'internal_port',
      'runtime',
      'source_type',
      'git_url',
      'git_branch',
      'build_command',
      'start_command',
      'health_check_path',
      'deploy_key_id',
      'python_version',
      'python_mode',
      'wsgi_app',
      'gunicorn_workers',
      'gunicorn_threads',
      'gunicorn_timeout',
      'gunicorn_bind',
      'gunicorn_extra_args',
      'celery_app',
      'celery_worker_count',
      'celery_concurrency',
      'celery_queues',
      'celery_beat_enabled',
      'celery_extra_args',
      'static_root',
      'static_spa',
      'memory_mb_limit',
      'cpu_quota_percent',
      'tasks_limit',
      'status',
      'last_deployed_at',
      'created_at',
      'updated_at',
    ],
    fromRow: App.fromRow,
  );
}

Query<App> apps() => Query<App>(AppTable.metadata);

class EnvVar with Preloadable {
  final int? id;
  final int appId;
  final String name;
  final String? value;
  final bool? isSecret;
  final DateTime updatedAt;

  EnvVar({
    this.id,
    required this.appId,
    required this.name,
    this.value,
    this.isSecret,
    required this.updatedAt,
  });

  factory EnvVar.fromRow(Map<String, dynamic> row) => EnvVar(
    id: row['id'] as int?,
    appId: row['app_id'] as int,
    name: row['name'] as String,
    value: row['value'] as String?,
    isSecret: row['is_secret'] as bool?,
    updatedAt: row['updated_at'] is DateTime
        ? row['updated_at'] as DateTime
        : DateTime.parse(row['updated_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'app_id': appId,
    'name': name,
    'value': value,
    'is_secret': isSecret,
    'updated_at': updatedAt,
  };

  factory EnvVar.fromJson(Map<String, dynamic> json) => EnvVar.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  EnvVar copyWith({
    int? id,
    int? appId,
    String? name,
    String? value,
    bool? isSecret,
    DateTime? updatedAt,
  }) => EnvVar(
    id: id ?? this.id,
    appId: appId ?? this.appId,
    name: name ?? this.name,
    value: value ?? this.value,
    isSecret: isSecret ?? this.isSecret,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static final Relation<EnvVar, App> app = BelongsToRelation<EnvVar, App>(
    parentTable: 'env_vars',
    childTable: 'apps',
    name: 'app',
    parentForeignKey: 'app_id',
    childMeta: AppTable.metadata,
  );

  /// Preloaded app; null when not preloaded or absent.
  App? get appLoaded => preloaded<App>('app');
}

class EnvVarTable {
  EnvVarTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'env_vars',
    column: 'id',
  );
  static const ColumnRef<int> appId = ColumnRef<int>(
    table: 'env_vars',
    column: 'app_id',
  );
  static const ColumnRef<String> name = ColumnRef<String>(
    table: 'env_vars',
    column: 'name',
  );
  static const ColumnRef<String?> value = ColumnRef<String?>(
    table: 'env_vars',
    column: 'value',
  );
  static const ColumnRef<bool?> isSecret = ColumnRef<bool?>(
    table: 'env_vars',
    column: 'is_secret',
  );
  static const ColumnRef<DateTime> updatedAt = ColumnRef<DateTime>(
    table: 'env_vars',
    column: 'updated_at',
  );

  static const TableMeta<EnvVar> metadata = TableMeta<EnvVar>(
    tableName: 'env_vars',
    primaryKey: 'id',
    columnNames: ['id', 'app_id', 'name', 'value', 'is_secret', 'updated_at'],
    fromRow: EnvVar.fromRow,
  );
}

Query<EnvVar> envVars() => Query<EnvVar>(EnvVarTable.metadata);

class Deployment with Preloadable {
  final int? id;
  final int appId;
  final int? triggeredById;
  final String sourceType;
  final String? gitCommitSha;
  final String? artifactPath;
  final String? status;
  final String? failureReason;
  final bool? isActive;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime createdAt;

  Deployment({
    this.id,
    required this.appId,
    this.triggeredById,
    required this.sourceType,
    this.gitCommitSha,
    this.artifactPath,
    this.status,
    this.failureReason,
    this.isActive,
    this.startedAt,
    this.finishedAt,
    required this.createdAt,
  });

  factory Deployment.fromRow(Map<String, dynamic> row) => Deployment(
    id: row['id'] as int?,
    appId: row['app_id'] as int,
    triggeredById: row['triggered_by_id'] as int?,
    sourceType: row['source_type'] as String,
    gitCommitSha: row['git_commit_sha'] as String?,
    artifactPath: row['artifact_path'] as String?,
    status: row['status'] as String?,
    failureReason: row['failure_reason'] as String?,
    isActive: row['is_active'] as bool?,
    startedAt: row['started_at'] == null
        ? null
        : (row['started_at'] is DateTime
              ? row['started_at'] as DateTime
              : DateTime.parse(row['started_at'].toString())),
    finishedAt: row['finished_at'] == null
        ? null
        : (row['finished_at'] is DateTime
              ? row['finished_at'] as DateTime
              : DateTime.parse(row['finished_at'].toString())),
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'app_id': appId,
    'triggered_by_id': triggeredById,
    'source_type': sourceType,
    'git_commit_sha': gitCommitSha,
    'artifact_path': artifactPath,
    'status': status,
    'failure_reason': failureReason,
    'is_active': isActive,
    'started_at': startedAt,
    'finished_at': finishedAt,
    'created_at': createdAt,
  };

  factory Deployment.fromJson(Map<String, dynamic> json) =>
      Deployment.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  Deployment copyWith({
    int? id,
    int? appId,
    int? triggeredById,
    String? sourceType,
    String? gitCommitSha,
    String? artifactPath,
    String? status,
    String? failureReason,
    bool? isActive,
    DateTime? startedAt,
    DateTime? finishedAt,
    DateTime? createdAt,
  }) => Deployment(
    id: id ?? this.id,
    appId: appId ?? this.appId,
    triggeredById: triggeredById ?? this.triggeredById,
    sourceType: sourceType ?? this.sourceType,
    gitCommitSha: gitCommitSha ?? this.gitCommitSha,
    artifactPath: artifactPath ?? this.artifactPath,
    status: status ?? this.status,
    failureReason: failureReason ?? this.failureReason,
    isActive: isActive ?? this.isActive,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    createdAt: createdAt ?? this.createdAt,
  );

  static final Relation<Deployment, App> app =
      BelongsToRelation<Deployment, App>(
        parentTable: 'deployments',
        childTable: 'apps',
        name: 'app',
        parentForeignKey: 'app_id',
        childMeta: AppTable.metadata,
      );

  static final Relation<Deployment, User> triggeredBy =
      BelongsToRelation<Deployment, User>(
        parentTable: 'deployments',
        childTable: 'users',
        name: 'triggeredBy',
        parentForeignKey: 'triggered_by_id',
        childMeta: UserTable.metadata,
      );

  static final Relation<Deployment, BuildLog> buildLogs =
      HasManyRelation<Deployment, BuildLog>(
        parentTable: 'deployments',
        childTable: 'build_logs',
        name: 'buildLogs',
        childForeignKey: 'deployment_id',
        childMeta: BuildLogTable.metadata,
      );

  /// Preloaded app; null when not preloaded or absent.
  App? get appLoaded => preloaded<App>('app');

  /// Preloaded triggeredBy; null when not preloaded or absent.
  User? get triggeredByLoaded => preloaded<User>('triggeredBy');

  /// Preloaded buildLogs; empty list when not preloaded.
  List<BuildLog> get buildLogsList =>
      preloaded<List<BuildLog>>('buildLogs') ?? const [];
}

class DeploymentTable {
  DeploymentTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'deployments',
    column: 'id',
  );
  static const ColumnRef<int> appId = ColumnRef<int>(
    table: 'deployments',
    column: 'app_id',
  );
  static const ColumnRef<int?> triggeredById = ColumnRef<int?>(
    table: 'deployments',
    column: 'triggered_by_id',
  );
  static const ColumnRef<String> sourceType = ColumnRef<String>(
    table: 'deployments',
    column: 'source_type',
  );
  static const ColumnRef<String?> gitCommitSha = ColumnRef<String?>(
    table: 'deployments',
    column: 'git_commit_sha',
  );
  static const ColumnRef<String?> artifactPath = ColumnRef<String?>(
    table: 'deployments',
    column: 'artifact_path',
  );
  static const ColumnRef<String?> status = ColumnRef<String?>(
    table: 'deployments',
    column: 'status',
  );
  static const ColumnRef<String?> failureReason = ColumnRef<String?>(
    table: 'deployments',
    column: 'failure_reason',
  );
  static const ColumnRef<bool?> isActive = ColumnRef<bool?>(
    table: 'deployments',
    column: 'is_active',
  );
  static const ColumnRef<DateTime?> startedAt = ColumnRef<DateTime?>(
    table: 'deployments',
    column: 'started_at',
  );
  static const ColumnRef<DateTime?> finishedAt = ColumnRef<DateTime?>(
    table: 'deployments',
    column: 'finished_at',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'deployments',
    column: 'created_at',
  );

  static const TableMeta<Deployment> metadata = TableMeta<Deployment>(
    tableName: 'deployments',
    primaryKey: 'id',
    columnNames: [
      'id',
      'app_id',
      'triggered_by_id',
      'source_type',
      'git_commit_sha',
      'artifact_path',
      'status',
      'failure_reason',
      'is_active',
      'started_at',
      'finished_at',
      'created_at',
    ],
    fromRow: Deployment.fromRow,
  );
}

Query<Deployment> deployments() => Query<Deployment>(DeploymentTable.metadata);

class BuildLog with Preloadable {
  final int? id;
  final int deploymentId;
  final String line;
  final String? stream;
  final DateTime createdAt;

  BuildLog({
    this.id,
    required this.deploymentId,
    required this.line,
    this.stream,
    required this.createdAt,
  });

  factory BuildLog.fromRow(Map<String, dynamic> row) => BuildLog(
    id: row['id'] as int?,
    deploymentId: row['deployment_id'] as int,
    line: row['line'] as String,
    stream: row['stream'] as String?,
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'deployment_id': deploymentId,
    'line': line,
    'stream': stream,
    'created_at': createdAt,
  };

  factory BuildLog.fromJson(Map<String, dynamic> json) =>
      BuildLog.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  BuildLog copyWith({
    int? id,
    int? deploymentId,
    String? line,
    String? stream,
    DateTime? createdAt,
  }) => BuildLog(
    id: id ?? this.id,
    deploymentId: deploymentId ?? this.deploymentId,
    line: line ?? this.line,
    stream: stream ?? this.stream,
    createdAt: createdAt ?? this.createdAt,
  );

  static final Relation<BuildLog, Deployment> deployment =
      BelongsToRelation<BuildLog, Deployment>(
        parentTable: 'build_logs',
        childTable: 'deployments',
        name: 'deployment',
        parentForeignKey: 'deployment_id',
        childMeta: DeploymentTable.metadata,
      );

  /// Preloaded deployment; null when not preloaded or absent.
  Deployment? get deploymentLoaded => preloaded<Deployment>('deployment');
}

class BuildLogTable {
  BuildLogTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'build_logs',
    column: 'id',
  );
  static const ColumnRef<int> deploymentId = ColumnRef<int>(
    table: 'build_logs',
    column: 'deployment_id',
  );
  static const ColumnRef<String> line = ColumnRef<String>(
    table: 'build_logs',
    column: 'line',
  );
  static const ColumnRef<String?> stream = ColumnRef<String?>(
    table: 'build_logs',
    column: 'stream',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'build_logs',
    column: 'created_at',
  );

  static const TableMeta<BuildLog> metadata = TableMeta<BuildLog>(
    tableName: 'build_logs',
    primaryKey: 'id',
    columnNames: ['id', 'deployment_id', 'line', 'stream', 'created_at'],
    fromRow: BuildLog.fromRow,
  );
}

Query<BuildLog> buildLogs() => Query<BuildLog>(BuildLogTable.metadata);

class Domain with Preloadable {
  final int? id;
  final int appId;
  final String? hostname;
  final bool? isPrimary;
  final bool? isVerified;
  final String? verificationToken;
  final String? sslStatus;
  final DateTime? sslExpiresAt;
  final String? sslIssuer;
  final DateTime createdAt;

  Domain({
    this.id,
    required this.appId,
    this.hostname,
    this.isPrimary,
    this.isVerified,
    this.verificationToken,
    this.sslStatus,
    this.sslExpiresAt,
    this.sslIssuer,
    required this.createdAt,
  });

  factory Domain.fromRow(Map<String, dynamic> row) => Domain(
    id: row['id'] as int?,
    appId: row['app_id'] as int,
    hostname: row['hostname'] as String?,
    isPrimary: row['is_primary'] as bool?,
    isVerified: row['is_verified'] as bool?,
    verificationToken: row['verification_token'] as String?,
    sslStatus: row['ssl_status'] as String?,
    sslExpiresAt: row['ssl_expires_at'] == null
        ? null
        : (row['ssl_expires_at'] is DateTime
              ? row['ssl_expires_at'] as DateTime
              : DateTime.parse(row['ssl_expires_at'].toString())),
    sslIssuer: row['ssl_issuer'] as String?,
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'app_id': appId,
    'hostname': hostname,
    'is_primary': isPrimary,
    'is_verified': isVerified,
    'verification_token': verificationToken,
    'ssl_status': sslStatus,
    'ssl_expires_at': sslExpiresAt,
    'ssl_issuer': sslIssuer,
    'created_at': createdAt,
  };

  factory Domain.fromJson(Map<String, dynamic> json) => Domain.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  Domain copyWith({
    int? id,
    int? appId,
    String? hostname,
    bool? isPrimary,
    bool? isVerified,
    String? verificationToken,
    String? sslStatus,
    DateTime? sslExpiresAt,
    String? sslIssuer,
    DateTime? createdAt,
  }) => Domain(
    id: id ?? this.id,
    appId: appId ?? this.appId,
    hostname: hostname ?? this.hostname,
    isPrimary: isPrimary ?? this.isPrimary,
    isVerified: isVerified ?? this.isVerified,
    verificationToken: verificationToken ?? this.verificationToken,
    sslStatus: sslStatus ?? this.sslStatus,
    sslExpiresAt: sslExpiresAt ?? this.sslExpiresAt,
    sslIssuer: sslIssuer ?? this.sslIssuer,
    createdAt: createdAt ?? this.createdAt,
  );

  static final Relation<Domain, App> app = BelongsToRelation<Domain, App>(
    parentTable: 'domains',
    childTable: 'apps',
    name: 'app',
    parentForeignKey: 'app_id',
    childMeta: AppTable.metadata,
  );

  /// Preloaded app; null when not preloaded or absent.
  App? get appLoaded => preloaded<App>('app');
}

class DomainTable {
  DomainTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'domains',
    column: 'id',
  );
  static const ColumnRef<int> appId = ColumnRef<int>(
    table: 'domains',
    column: 'app_id',
  );
  static const ColumnRef<String?> hostname = ColumnRef<String?>(
    table: 'domains',
    column: 'hostname',
  );
  static const ColumnRef<bool?> isPrimary = ColumnRef<bool?>(
    table: 'domains',
    column: 'is_primary',
  );
  static const ColumnRef<bool?> isVerified = ColumnRef<bool?>(
    table: 'domains',
    column: 'is_verified',
  );
  static const ColumnRef<String?> verificationToken = ColumnRef<String?>(
    table: 'domains',
    column: 'verification_token',
  );
  static const ColumnRef<String?> sslStatus = ColumnRef<String?>(
    table: 'domains',
    column: 'ssl_status',
  );
  static const ColumnRef<DateTime?> sslExpiresAt = ColumnRef<DateTime?>(
    table: 'domains',
    column: 'ssl_expires_at',
  );
  static const ColumnRef<String?> sslIssuer = ColumnRef<String?>(
    table: 'domains',
    column: 'ssl_issuer',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'domains',
    column: 'created_at',
  );

  static const TableMeta<Domain> metadata = TableMeta<Domain>(
    tableName: 'domains',
    primaryKey: 'id',
    columnNames: [
      'id',
      'app_id',
      'hostname',
      'is_primary',
      'is_verified',
      'verification_token',
      'ssl_status',
      'ssl_expires_at',
      'ssl_issuer',
      'created_at',
    ],
    fromRow: Domain.fromRow,
  );
}

Query<Domain> domains() => Query<Domain>(DomainTable.metadata);

class MetricSample with Preloadable {
  final int? id;
  final int appId;
  final int? cpuPercent;
  final int? memBytes;
  final int? rssBytes;
  final DateTime sampledAt;

  MetricSample({
    this.id,
    required this.appId,
    this.cpuPercent,
    this.memBytes,
    this.rssBytes,
    required this.sampledAt,
  });

  factory MetricSample.fromRow(Map<String, dynamic> row) => MetricSample(
    id: row['id'] as int?,
    appId: row['app_id'] as int,
    cpuPercent: row['cpu_percent'] as int?,
    memBytes: row['mem_bytes'] as int?,
    rssBytes: row['rss_bytes'] as int?,
    sampledAt: row['sampled_at'] is DateTime
        ? row['sampled_at'] as DateTime
        : DateTime.parse(row['sampled_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'app_id': appId,
    'cpu_percent': cpuPercent,
    'mem_bytes': memBytes,
    'rss_bytes': rssBytes,
    'sampled_at': sampledAt,
  };

  factory MetricSample.fromJson(Map<String, dynamic> json) =>
      MetricSample.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  MetricSample copyWith({
    int? id,
    int? appId,
    int? cpuPercent,
    int? memBytes,
    int? rssBytes,
    DateTime? sampledAt,
  }) => MetricSample(
    id: id ?? this.id,
    appId: appId ?? this.appId,
    cpuPercent: cpuPercent ?? this.cpuPercent,
    memBytes: memBytes ?? this.memBytes,
    rssBytes: rssBytes ?? this.rssBytes,
    sampledAt: sampledAt ?? this.sampledAt,
  );

  static final Relation<MetricSample, App> app =
      BelongsToRelation<MetricSample, App>(
        parentTable: 'metric_samples',
        childTable: 'apps',
        name: 'app',
        parentForeignKey: 'app_id',
        childMeta: AppTable.metadata,
      );

  /// Preloaded app; null when not preloaded or absent.
  App? get appLoaded => preloaded<App>('app');
}

class MetricSampleTable {
  MetricSampleTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'metric_samples',
    column: 'id',
  );
  static const ColumnRef<int> appId = ColumnRef<int>(
    table: 'metric_samples',
    column: 'app_id',
  );
  static const ColumnRef<int?> cpuPercent = ColumnRef<int?>(
    table: 'metric_samples',
    column: 'cpu_percent',
  );
  static const ColumnRef<int?> memBytes = ColumnRef<int?>(
    table: 'metric_samples',
    column: 'mem_bytes',
  );
  static const ColumnRef<int?> rssBytes = ColumnRef<int?>(
    table: 'metric_samples',
    column: 'rss_bytes',
  );
  static const ColumnRef<DateTime> sampledAt = ColumnRef<DateTime>(
    table: 'metric_samples',
    column: 'sampled_at',
  );

  static const TableMeta<MetricSample> metadata = TableMeta<MetricSample>(
    tableName: 'metric_samples',
    primaryKey: 'id',
    columnNames: [
      'id',
      'app_id',
      'cpu_percent',
      'mem_bytes',
      'rss_bytes',
      'sampled_at',
    ],
    fromRow: MetricSample.fromRow,
  );
}

Query<MetricSample> metricSamples() =>
    Query<MetricSample>(MetricSampleTable.metadata);

class AppEvent with Preloadable {
  final int? id;
  final int appId;
  final int? actorId;
  final String kind;
  final String? message;
  final String? data;
  final DateTime createdAt;

  AppEvent({
    this.id,
    required this.appId,
    this.actorId,
    required this.kind,
    this.message,
    this.data,
    required this.createdAt,
  });

  factory AppEvent.fromRow(Map<String, dynamic> row) => AppEvent(
    id: row['id'] as int?,
    appId: row['app_id'] as int,
    actorId: row['actor_id'] as int?,
    kind: row['kind'] as String,
    message: row['message'] as String?,
    data: row['data'] as String?,
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'app_id': appId,
    'actor_id': actorId,
    'kind': kind,
    'message': message,
    'data': data,
    'created_at': createdAt,
  };

  factory AppEvent.fromJson(Map<String, dynamic> json) =>
      AppEvent.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  AppEvent copyWith({
    int? id,
    int? appId,
    int? actorId,
    String? kind,
    String? message,
    String? data,
    DateTime? createdAt,
  }) => AppEvent(
    id: id ?? this.id,
    appId: appId ?? this.appId,
    actorId: actorId ?? this.actorId,
    kind: kind ?? this.kind,
    message: message ?? this.message,
    data: data ?? this.data,
    createdAt: createdAt ?? this.createdAt,
  );

  static final Relation<AppEvent, App> app = BelongsToRelation<AppEvent, App>(
    parentTable: 'app_events',
    childTable: 'apps',
    name: 'app',
    parentForeignKey: 'app_id',
    childMeta: AppTable.metadata,
  );

  static final Relation<AppEvent, User> actor =
      BelongsToRelation<AppEvent, User>(
        parentTable: 'app_events',
        childTable: 'users',
        name: 'actor',
        parentForeignKey: 'actor_id',
        childMeta: UserTable.metadata,
      );

  /// Preloaded app; null when not preloaded or absent.
  App? get appLoaded => preloaded<App>('app');

  /// Preloaded actor; null when not preloaded or absent.
  User? get actorLoaded => preloaded<User>('actor');
}

class AppEventTable {
  AppEventTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'app_events',
    column: 'id',
  );
  static const ColumnRef<int> appId = ColumnRef<int>(
    table: 'app_events',
    column: 'app_id',
  );
  static const ColumnRef<int?> actorId = ColumnRef<int?>(
    table: 'app_events',
    column: 'actor_id',
  );
  static const ColumnRef<String> kind = ColumnRef<String>(
    table: 'app_events',
    column: 'kind',
  );
  static const ColumnRef<String?> message = ColumnRef<String?>(
    table: 'app_events',
    column: 'message',
  );
  static const ColumnRef<String?> data = ColumnRef<String?>(
    table: 'app_events',
    column: 'data',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'app_events',
    column: 'created_at',
  );

  static const TableMeta<AppEvent> metadata = TableMeta<AppEvent>(
    tableName: 'app_events',
    primaryKey: 'id',
    columnNames: [
      'id',
      'app_id',
      'actor_id',
      'kind',
      'message',
      'data',
      'created_at',
    ],
    fromRow: AppEvent.fromRow,
  );
}

Query<AppEvent> appEvents() => Query<AppEvent>(AppEventTable.metadata);

class ManagedService with Preloadable {
  final int? id;
  final String serviceType;
  final String displayName;
  final String? status;
  final String? config;
  final String? errorMessage;
  final DateTime? installedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ManagedService({
    this.id,
    required this.serviceType,
    required this.displayName,
    this.status,
    this.config,
    this.errorMessage,
    this.installedAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory ManagedService.fromRow(Map<String, dynamic> row) => ManagedService(
    id: row['id'] as int?,
    serviceType: row['service_type'] as String,
    displayName: row['display_name'] as String,
    status: row['status'] as String?,
    config: row['config'] as String?,
    errorMessage: row['error_message'] as String?,
    installedAt: row['installed_at'] == null
        ? null
        : (row['installed_at'] is DateTime
              ? row['installed_at'] as DateTime
              : DateTime.parse(row['installed_at'].toString())),
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
    updatedAt: row['updated_at'] == null
        ? null
        : (row['updated_at'] is DateTime
              ? row['updated_at'] as DateTime
              : DateTime.parse(row['updated_at'].toString())),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'service_type': serviceType,
    'display_name': displayName,
    'status': status,
    'config': config,
    'error_message': errorMessage,
    'installed_at': installedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory ManagedService.fromJson(Map<String, dynamic> json) =>
      ManagedService.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  ManagedService copyWith({
    int? id,
    String? serviceType,
    String? displayName,
    String? status,
    String? config,
    String? errorMessage,
    DateTime? installedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ManagedService(
    id: id ?? this.id,
    serviceType: serviceType ?? this.serviceType,
    displayName: displayName ?? this.displayName,
    status: status ?? this.status,
    config: config ?? this.config,
    errorMessage: errorMessage ?? this.errorMessage,
    installedAt: installedAt ?? this.installedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class ManagedServiceTable {
  ManagedServiceTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'managed_services',
    column: 'id',
  );
  static const ColumnRef<String> serviceType = ColumnRef<String>(
    table: 'managed_services',
    column: 'service_type',
  );
  static const ColumnRef<String> displayName = ColumnRef<String>(
    table: 'managed_services',
    column: 'display_name',
  );
  static const ColumnRef<String?> status = ColumnRef<String?>(
    table: 'managed_services',
    column: 'status',
  );
  static const ColumnRef<String?> config = ColumnRef<String?>(
    table: 'managed_services',
    column: 'config',
  );
  static const ColumnRef<String?> errorMessage = ColumnRef<String?>(
    table: 'managed_services',
    column: 'error_message',
  );
  static const ColumnRef<DateTime?> installedAt = ColumnRef<DateTime?>(
    table: 'managed_services',
    column: 'installed_at',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'managed_services',
    column: 'created_at',
  );
  static const ColumnRef<DateTime?> updatedAt = ColumnRef<DateTime?>(
    table: 'managed_services',
    column: 'updated_at',
  );

  static const TableMeta<ManagedService> metadata = TableMeta<ManagedService>(
    tableName: 'managed_services',
    primaryKey: 'id',
    columnNames: [
      'id',
      'service_type',
      'display_name',
      'status',
      'config',
      'error_message',
      'installed_at',
      'created_at',
      'updated_at',
    ],
    fromRow: ManagedService.fromRow,
  );
}

Query<ManagedService> managedServices() =>
    Query<ManagedService>(ManagedServiceTable.metadata);

class PostgresInstance with Preloadable {
  final int? id;
  final int version;
  final String displayName;
  final int port;
  final String? status;
  final bool? isDefault;
  final String? monitorPassword;
  final String? dataDirectory;
  final String? errorMessage;
  final DateTime? installedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PostgresInstance({
    this.id,
    required this.version,
    required this.displayName,
    required this.port,
    this.status,
    this.isDefault,
    this.monitorPassword,
    this.dataDirectory,
    this.errorMessage,
    this.installedAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory PostgresInstance.fromRow(Map<String, dynamic> row) =>
      PostgresInstance(
        id: row['id'] as int?,
        version: row['version'] as int,
        displayName: row['display_name'] as String,
        port: row['port'] as int,
        status: row['status'] as String?,
        isDefault: row['is_default'] as bool?,
        monitorPassword: row['monitor_password'] as String?,
        dataDirectory: row['data_directory'] as String?,
        errorMessage: row['error_message'] as String?,
        installedAt: row['installed_at'] == null
            ? null
            : (row['installed_at'] is DateTime
                  ? row['installed_at'] as DateTime
                  : DateTime.parse(row['installed_at'].toString())),
        createdAt: row['created_at'] is DateTime
            ? row['created_at'] as DateTime
            : DateTime.parse(row['created_at'].toString()),
        updatedAt: row['updated_at'] == null
            ? null
            : (row['updated_at'] is DateTime
                  ? row['updated_at'] as DateTime
                  : DateTime.parse(row['updated_at'].toString())),
      );

  Map<String, dynamic> toRow() => {
    'id': id,
    'version': version,
    'display_name': displayName,
    'port': port,
    'status': status,
    'is_default': isDefault,
    'monitor_password': monitorPassword,
    'data_directory': dataDirectory,
    'error_message': errorMessage,
    'installed_at': installedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory PostgresInstance.fromJson(Map<String, dynamic> json) =>
      PostgresInstance.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  PostgresInstance copyWith({
    int? id,
    int? version,
    String? displayName,
    int? port,
    String? status,
    bool? isDefault,
    String? monitorPassword,
    String? dataDirectory,
    String? errorMessage,
    DateTime? installedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PostgresInstance(
    id: id ?? this.id,
    version: version ?? this.version,
    displayName: displayName ?? this.displayName,
    port: port ?? this.port,
    status: status ?? this.status,
    isDefault: isDefault ?? this.isDefault,
    monitorPassword: monitorPassword ?? this.monitorPassword,
    dataDirectory: dataDirectory ?? this.dataDirectory,
    errorMessage: errorMessage ?? this.errorMessage,
    installedAt: installedAt ?? this.installedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static final Relation<PostgresInstance, PostgresDatabase> databases =
      HasManyRelation<PostgresInstance, PostgresDatabase>(
        parentTable: 'postgres_instances',
        childTable: 'postgres_databases',
        name: 'databases',
        childForeignKey: 'instance_id',
        childMeta: PostgresDatabaseTable.metadata,
      );

  /// Preloaded databases; empty list when not preloaded.
  List<PostgresDatabase> get databasesList =>
      preloaded<List<PostgresDatabase>>('databases') ?? const [];
}

class PostgresInstanceTable {
  PostgresInstanceTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'postgres_instances',
    column: 'id',
  );
  static const ColumnRef<int> version = ColumnRef<int>(
    table: 'postgres_instances',
    column: 'version',
  );
  static const ColumnRef<String> displayName = ColumnRef<String>(
    table: 'postgres_instances',
    column: 'display_name',
  );
  static const ColumnRef<int> port = ColumnRef<int>(
    table: 'postgres_instances',
    column: 'port',
  );
  static const ColumnRef<String?> status = ColumnRef<String?>(
    table: 'postgres_instances',
    column: 'status',
  );
  static const ColumnRef<bool?> isDefault = ColumnRef<bool?>(
    table: 'postgres_instances',
    column: 'is_default',
  );
  static const ColumnRef<String?> monitorPassword = ColumnRef<String?>(
    table: 'postgres_instances',
    column: 'monitor_password',
  );
  static const ColumnRef<String?> dataDirectory = ColumnRef<String?>(
    table: 'postgres_instances',
    column: 'data_directory',
  );
  static const ColumnRef<String?> errorMessage = ColumnRef<String?>(
    table: 'postgres_instances',
    column: 'error_message',
  );
  static const ColumnRef<DateTime?> installedAt = ColumnRef<DateTime?>(
    table: 'postgres_instances',
    column: 'installed_at',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'postgres_instances',
    column: 'created_at',
  );
  static const ColumnRef<DateTime?> updatedAt = ColumnRef<DateTime?>(
    table: 'postgres_instances',
    column: 'updated_at',
  );

  static const TableMeta<PostgresInstance> metadata =
      TableMeta<PostgresInstance>(
        tableName: 'postgres_instances',
        primaryKey: 'id',
        columnNames: [
          'id',
          'version',
          'display_name',
          'port',
          'status',
          'is_default',
          'monitor_password',
          'data_directory',
          'error_message',
          'installed_at',
          'created_at',
          'updated_at',
        ],
        fromRow: PostgresInstance.fromRow,
      );
}

Query<PostgresInstance> postgresInstances() =>
    Query<PostgresInstance>(PostgresInstanceTable.metadata);

class PostgresDatabase with Preloadable {
  final int? id;
  final int instanceId;
  final String dbName;
  final String roleName;
  final String password;
  final String? extensions;
  final String? status;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PostgresDatabase({
    this.id,
    required this.instanceId,
    required this.dbName,
    required this.roleName,
    required this.password,
    this.extensions,
    this.status,
    this.errorMessage,
    required this.createdAt,
    this.updatedAt,
  });

  factory PostgresDatabase.fromRow(Map<String, dynamic> row) =>
      PostgresDatabase(
        id: row['id'] as int?,
        instanceId: row['instance_id'] as int,
        dbName: row['db_name'] as String,
        roleName: row['role_name'] as String,
        password: row['password'] as String,
        extensions: row['extensions'] as String?,
        status: row['status'] as String?,
        errorMessage: row['error_message'] as String?,
        createdAt: row['created_at'] is DateTime
            ? row['created_at'] as DateTime
            : DateTime.parse(row['created_at'].toString()),
        updatedAt: row['updated_at'] == null
            ? null
            : (row['updated_at'] is DateTime
                  ? row['updated_at'] as DateTime
                  : DateTime.parse(row['updated_at'].toString())),
      );

  Map<String, dynamic> toRow() => {
    'id': id,
    'instance_id': instanceId,
    'db_name': dbName,
    'role_name': roleName,
    'password': password,
    'extensions': extensions,
    'status': status,
    'error_message': errorMessage,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory PostgresDatabase.fromJson(Map<String, dynamic> json) =>
      PostgresDatabase.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  PostgresDatabase copyWith({
    int? id,
    int? instanceId,
    String? dbName,
    String? roleName,
    String? password,
    String? extensions,
    String? status,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PostgresDatabase(
    id: id ?? this.id,
    instanceId: instanceId ?? this.instanceId,
    dbName: dbName ?? this.dbName,
    roleName: roleName ?? this.roleName,
    password: password ?? this.password,
    extensions: extensions ?? this.extensions,
    status: status ?? this.status,
    errorMessage: errorMessage ?? this.errorMessage,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static final Relation<PostgresDatabase, PostgresInstance> instance =
      BelongsToRelation<PostgresDatabase, PostgresInstance>(
        parentTable: 'postgres_databases',
        childTable: 'postgres_instances',
        name: 'instance',
        parentForeignKey: 'instance_id',
        childMeta: PostgresInstanceTable.metadata,
      );

  /// Preloaded instance; null when not preloaded or absent.
  PostgresInstance? get instanceLoaded =>
      preloaded<PostgresInstance>('instance');
}

class PostgresDatabaseTable {
  PostgresDatabaseTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'postgres_databases',
    column: 'id',
  );
  static const ColumnRef<int> instanceId = ColumnRef<int>(
    table: 'postgres_databases',
    column: 'instance_id',
  );
  static const ColumnRef<String> dbName = ColumnRef<String>(
    table: 'postgres_databases',
    column: 'db_name',
  );
  static const ColumnRef<String> roleName = ColumnRef<String>(
    table: 'postgres_databases',
    column: 'role_name',
  );
  static const ColumnRef<String> password = ColumnRef<String>(
    table: 'postgres_databases',
    column: 'password',
  );
  static const ColumnRef<String?> extensions = ColumnRef<String?>(
    table: 'postgres_databases',
    column: 'extensions',
  );
  static const ColumnRef<String?> status = ColumnRef<String?>(
    table: 'postgres_databases',
    column: 'status',
  );
  static const ColumnRef<String?> errorMessage = ColumnRef<String?>(
    table: 'postgres_databases',
    column: 'error_message',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'postgres_databases',
    column: 'created_at',
  );
  static const ColumnRef<DateTime?> updatedAt = ColumnRef<DateTime?>(
    table: 'postgres_databases',
    column: 'updated_at',
  );

  static const TableMeta<PostgresDatabase> metadata =
      TableMeta<PostgresDatabase>(
        tableName: 'postgres_databases',
        primaryKey: 'id',
        columnNames: [
          'id',
          'instance_id',
          'db_name',
          'role_name',
          'password',
          'extensions',
          'status',
          'error_message',
          'created_at',
          'updated_at',
        ],
        fromRow: PostgresDatabase.fromRow,
      );
}

Query<PostgresDatabase> postgresDatabases() =>
    Query<PostgresDatabase>(PostgresDatabaseTable.metadata);

class MailDomain with Preloadable {
  final int? id;
  final String domain;
  final String? mailHostname;
  final String? dkimSelector;
  final String? dkimPublicKey;
  final String? dmarcPolicy;
  final String? publicIp;
  final bool? isActive;
  final DateTime createdAt;

  MailDomain({
    this.id,
    required this.domain,
    this.mailHostname,
    this.dkimSelector,
    this.dkimPublicKey,
    this.dmarcPolicy,
    this.publicIp,
    this.isActive,
    required this.createdAt,
  });

  factory MailDomain.fromRow(Map<String, dynamic> row) => MailDomain(
    id: row['id'] as int?,
    domain: row['domain'] as String,
    mailHostname: row['mail_hostname'] as String?,
    dkimSelector: row['dkim_selector'] as String?,
    dkimPublicKey: row['dkim_public_key'] as String?,
    dmarcPolicy: row['dmarc_policy'] as String?,
    publicIp: row['public_ip'] as String?,
    isActive: row['is_active'] as bool?,
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'domain': domain,
    'mail_hostname': mailHostname,
    'dkim_selector': dkimSelector,
    'dkim_public_key': dkimPublicKey,
    'dmarc_policy': dmarcPolicy,
    'public_ip': publicIp,
    'is_active': isActive,
    'created_at': createdAt,
  };

  factory MailDomain.fromJson(Map<String, dynamic> json) =>
      MailDomain.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  MailDomain copyWith({
    int? id,
    String? domain,
    String? mailHostname,
    String? dkimSelector,
    String? dkimPublicKey,
    String? dmarcPolicy,
    String? publicIp,
    bool? isActive,
    DateTime? createdAt,
  }) => MailDomain(
    id: id ?? this.id,
    domain: domain ?? this.domain,
    mailHostname: mailHostname ?? this.mailHostname,
    dkimSelector: dkimSelector ?? this.dkimSelector,
    dkimPublicKey: dkimPublicKey ?? this.dkimPublicKey,
    dmarcPolicy: dmarcPolicy ?? this.dmarcPolicy,
    publicIp: publicIp ?? this.publicIp,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
  );

  static final Relation<MailDomain, MailAccount> accounts =
      HasManyRelation<MailDomain, MailAccount>(
        parentTable: 'mail_domains',
        childTable: 'mail_accounts',
        name: 'accounts',
        childForeignKey: 'mail_domain_id',
        childMeta: MailAccountTable.metadata,
      );

  /// Preloaded accounts; empty list when not preloaded.
  List<MailAccount> get accountsList =>
      preloaded<List<MailAccount>>('accounts') ?? const [];
}

class MailDomainTable {
  MailDomainTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'mail_domains',
    column: 'id',
  );
  static const ColumnRef<String> domain = ColumnRef<String>(
    table: 'mail_domains',
    column: 'domain',
  );
  static const ColumnRef<String?> mailHostname = ColumnRef<String?>(
    table: 'mail_domains',
    column: 'mail_hostname',
  );
  static const ColumnRef<String?> dkimSelector = ColumnRef<String?>(
    table: 'mail_domains',
    column: 'dkim_selector',
  );
  static const ColumnRef<String?> dkimPublicKey = ColumnRef<String?>(
    table: 'mail_domains',
    column: 'dkim_public_key',
  );
  static const ColumnRef<String?> dmarcPolicy = ColumnRef<String?>(
    table: 'mail_domains',
    column: 'dmarc_policy',
  );
  static const ColumnRef<String?> publicIp = ColumnRef<String?>(
    table: 'mail_domains',
    column: 'public_ip',
  );
  static const ColumnRef<bool?> isActive = ColumnRef<bool?>(
    table: 'mail_domains',
    column: 'is_active',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'mail_domains',
    column: 'created_at',
  );

  static const TableMeta<MailDomain> metadata = TableMeta<MailDomain>(
    tableName: 'mail_domains',
    primaryKey: 'id',
    columnNames: [
      'id',
      'domain',
      'mail_hostname',
      'dkim_selector',
      'dkim_public_key',
      'dmarc_policy',
      'public_ip',
      'is_active',
      'created_at',
    ],
    fromRow: MailDomain.fromRow,
  );
}

Query<MailDomain> mailDomains() => Query<MailDomain>(MailDomainTable.metadata);

class MailAccount with Preloadable {
  final int? id;
  final int mailDomainId;
  final String address;
  final String passwordHash;
  final int? quotaMb;
  final bool? isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  MailAccount({
    this.id,
    required this.mailDomainId,
    required this.address,
    required this.passwordHash,
    this.quotaMb,
    this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  factory MailAccount.fromRow(Map<String, dynamic> row) => MailAccount(
    id: row['id'] as int?,
    mailDomainId: row['mail_domain_id'] as int,
    address: row['address'] as String,
    passwordHash: row['password_hash'] as String,
    quotaMb: row['quota_mb'] as int?,
    isActive: row['is_active'] as bool?,
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
    updatedAt: row['updated_at'] == null
        ? null
        : (row['updated_at'] is DateTime
              ? row['updated_at'] as DateTime
              : DateTime.parse(row['updated_at'].toString())),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'mail_domain_id': mailDomainId,
    'address': address,
    'password_hash': passwordHash,
    'quota_mb': quotaMb,
    'is_active': isActive,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory MailAccount.fromJson(Map<String, dynamic> json) =>
      MailAccount.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  MailAccount copyWith({
    int? id,
    int? mailDomainId,
    String? address,
    String? passwordHash,
    int? quotaMb,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => MailAccount(
    id: id ?? this.id,
    mailDomainId: mailDomainId ?? this.mailDomainId,
    address: address ?? this.address,
    passwordHash: passwordHash ?? this.passwordHash,
    quotaMb: quotaMb ?? this.quotaMb,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  static final Relation<MailAccount, MailDomain> mailDomain =
      BelongsToRelation<MailAccount, MailDomain>(
        parentTable: 'mail_accounts',
        childTable: 'mail_domains',
        name: 'mailDomain',
        parentForeignKey: 'mail_domain_id',
        childMeta: MailDomainTable.metadata,
      );

  /// Preloaded mailDomain; null when not preloaded or absent.
  MailDomain? get mailDomainLoaded => preloaded<MailDomain>('mailDomain');
}

class MailAccountTable {
  MailAccountTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'mail_accounts',
    column: 'id',
  );
  static const ColumnRef<int> mailDomainId = ColumnRef<int>(
    table: 'mail_accounts',
    column: 'mail_domain_id',
  );
  static const ColumnRef<String> address = ColumnRef<String>(
    table: 'mail_accounts',
    column: 'address',
  );
  static const ColumnRef<String> passwordHash = ColumnRef<String>(
    table: 'mail_accounts',
    column: 'password_hash',
  );
  static const ColumnRef<int?> quotaMb = ColumnRef<int?>(
    table: 'mail_accounts',
    column: 'quota_mb',
  );
  static const ColumnRef<bool?> isActive = ColumnRef<bool?>(
    table: 'mail_accounts',
    column: 'is_active',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'mail_accounts',
    column: 'created_at',
  );
  static const ColumnRef<DateTime?> updatedAt = ColumnRef<DateTime?>(
    table: 'mail_accounts',
    column: 'updated_at',
  );

  static const TableMeta<MailAccount> metadata = TableMeta<MailAccount>(
    tableName: 'mail_accounts',
    primaryKey: 'id',
    columnNames: [
      'id',
      'mail_domain_id',
      'address',
      'password_hash',
      'quota_mb',
      'is_active',
      'created_at',
      'updated_at',
    ],
    fromRow: MailAccount.fromRow,
  );
}

Query<MailAccount> mailAccounts() =>
    Query<MailAccount>(MailAccountTable.metadata);

class AuditLog with Preloadable {
  final int? id;
  final int? actorId;
  final int? teamId;
  final String action;
  final String? targetType;
  final String? targetId;
  final String? ipAddress;
  final String? userAgent;
  final String? data;
  final DateTime createdAt;

  AuditLog({
    this.id,
    this.actorId,
    this.teamId,
    required this.action,
    this.targetType,
    this.targetId,
    this.ipAddress,
    this.userAgent,
    this.data,
    required this.createdAt,
  });

  factory AuditLog.fromRow(Map<String, dynamic> row) => AuditLog(
    id: row['id'] as int?,
    actorId: row['actor_id'] as int?,
    teamId: row['team_id'] as int?,
    action: row['action'] as String,
    targetType: row['target_type'] as String?,
    targetId: row['target_id'] as String?,
    ipAddress: row['ip_address'] as String?,
    userAgent: row['user_agent'] as String?,
    data: row['data'] as String?,
    createdAt: row['created_at'] is DateTime
        ? row['created_at'] as DateTime
        : DateTime.parse(row['created_at'].toString()),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'actor_id': actorId,
    'team_id': teamId,
    'action': action,
    'target_type': targetType,
    'target_id': targetId,
    'ip_address': ipAddress,
    'user_agent': userAgent,
    'data': data,
    'created_at': createdAt,
  };

  factory AuditLog.fromJson(Map<String, dynamic> json) =>
      AuditLog.fromRow(json);

  Map<String, dynamic> toJson({
    List<String> exclude = const [],
    List<String> only = const [],
  }) {
    final row = toRow();
    if (only.isNotEmpty) return {for (final k in only) k: row[k]};
    if (exclude.isEmpty) return row;
    return Map.of(row)..removeWhere((k, _) => exclude.contains(k));
  }

  AuditLog copyWith({
    int? id,
    int? actorId,
    int? teamId,
    String? action,
    String? targetType,
    String? targetId,
    String? ipAddress,
    String? userAgent,
    String? data,
    DateTime? createdAt,
  }) => AuditLog(
    id: id ?? this.id,
    actorId: actorId ?? this.actorId,
    teamId: teamId ?? this.teamId,
    action: action ?? this.action,
    targetType: targetType ?? this.targetType,
    targetId: targetId ?? this.targetId,
    ipAddress: ipAddress ?? this.ipAddress,
    userAgent: userAgent ?? this.userAgent,
    data: data ?? this.data,
    createdAt: createdAt ?? this.createdAt,
  );

  static final Relation<AuditLog, User> actor =
      BelongsToRelation<AuditLog, User>(
        parentTable: 'audit_logs',
        childTable: 'users',
        name: 'actor',
        parentForeignKey: 'actor_id',
        childMeta: UserTable.metadata,
      );

  static final Relation<AuditLog, Team> team =
      BelongsToRelation<AuditLog, Team>(
        parentTable: 'audit_logs',
        childTable: 'teams',
        name: 'team',
        parentForeignKey: 'team_id',
        childMeta: TeamTable.metadata,
      );

  /// Preloaded actor; null when not preloaded or absent.
  User? get actorLoaded => preloaded<User>('actor');

  /// Preloaded team; null when not preloaded or absent.
  Team? get teamLoaded => preloaded<Team>('team');
}

class AuditLogTable {
  AuditLogTable._();
  static const ColumnRef<int?> id = ColumnRef<int?>(
    table: 'audit_logs',
    column: 'id',
  );
  static const ColumnRef<int?> actorId = ColumnRef<int?>(
    table: 'audit_logs',
    column: 'actor_id',
  );
  static const ColumnRef<int?> teamId = ColumnRef<int?>(
    table: 'audit_logs',
    column: 'team_id',
  );
  static const ColumnRef<String> action = ColumnRef<String>(
    table: 'audit_logs',
    column: 'action',
  );
  static const ColumnRef<String?> targetType = ColumnRef<String?>(
    table: 'audit_logs',
    column: 'target_type',
  );
  static const ColumnRef<String?> targetId = ColumnRef<String?>(
    table: 'audit_logs',
    column: 'target_id',
  );
  static const ColumnRef<String?> ipAddress = ColumnRef<String?>(
    table: 'audit_logs',
    column: 'ip_address',
  );
  static const ColumnRef<String?> userAgent = ColumnRef<String?>(
    table: 'audit_logs',
    column: 'user_agent',
  );
  static const ColumnRef<String?> data = ColumnRef<String?>(
    table: 'audit_logs',
    column: 'data',
  );
  static const ColumnRef<DateTime> createdAt = ColumnRef<DateTime>(
    table: 'audit_logs',
    column: 'created_at',
  );

  static const TableMeta<AuditLog> metadata = TableMeta<AuditLog>(
    tableName: 'audit_logs',
    primaryKey: 'id',
    columnNames: [
      'id',
      'actor_id',
      'team_id',
      'action',
      'target_type',
      'target_id',
      'ip_address',
      'user_agent',
      'data',
      'created_at',
    ],
    fromRow: AuditLog.fromRow,
  );
}

Query<AuditLog> auditLogs() => Query<AuditLog>(AuditLogTable.metadata);
