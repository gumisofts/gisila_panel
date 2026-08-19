import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:gisila/gisila.dart' hide Query;
import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart'
    show
        env,
        logger,
        systemPgDatabase,
        systemPgHost,
        systemPgPassword,
        systemPgPort,
        systemPgUseSsl,
        systemPgUser;
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:postgres/postgres.dart' as pg;

/// Postgres settings the panel lets users tune via the Configuration tab.
/// Keys must match `pg_settings.name`; the agent applies them with
/// `ALTER SYSTEM SET` and restarts the cluster.
const kTunableSettings = <String>[
  'max_connections',
  'shared_buffers',
  'effective_cache_size',
  'work_mem',
  'maintenance_work_mem',
  'wal_buffers',
  'min_wal_size',
  'max_wal_size',
  'checkpoint_completion_target',
  'random_page_cost',
  'effective_io_concurrency',
  'max_worker_processes',
  'max_parallel_workers',
  'max_parallel_workers_per_gather',
  'log_min_duration_statement',
];

// Postgres major versions available from the pgdg repository.
const kSupportedVersions = [14, 15, 16, 17, 18];

/// Databases that ship with every cluster and are never worth tracking as
/// user data. `postgres` is a maintenance database that is conventionally empty;
/// the templates cannot be dumped meaningfully.
const _pgBuiltinDatabases = {'postgres', 'template0', 'template1'};

// Valid backup scopes (maps to pg_dump --schema-only / --data-only).
const kBackupScopes = {'full', 'schema', 'data'};
const kBackupFrequencies = {'hourly', 'daily', 'weekly'};

// Postgres role attributes an operator may toggle on a database user. LOGIN is
// always granted by the agent; these are the optional, escalating privileges.
// CREATEDB is what Prisma's shadow database / `prisma migrate` requires.
const kRoleAttributes = {
  'CREATEDB',
  'CREATEROLE',
  'REPLICATION',
  'SUPERUSER',
  'BYPASSRLS',
};

/// Root directory for on-disk backup artifacts. Overridable via env for dev.
/// Owned by the `gisila` user so the API can stream downloads and stage uploads
/// while the root agent writes the dumps.
String pgBackupDir() =>
    env.getOrElse('GISILA_BACKUP_DIR', () => '/var/lib/gisila/backups');

/// Compute the next UTC run time for a preset schedule, strictly after [from].
DateTime computeNextRun(
  String frequency,
  int hour,
  int minute,
  int? weekday,
  DateTime from,
) {
  final f = from.toUtc();
  switch (frequency) {
    case 'hourly':
      var next = DateTime.utc(f.year, f.month, f.day, f.hour, minute);
      while (!next.isAfter(f)) {
        next = next.add(const Duration(hours: 1));
      }
      return next;
    case 'weekly':
      // Our weekday is 0=Sunday … 6=Saturday; Dart's is Mon=1 … Sun=7.
      final target = (weekday ?? 0).clamp(0, 6);
      final currentDow = f.weekday % 7; // Sun(7)→0, Mon(1)→1 … Sat(6)→6
      var delta = (target - currentDow) % 7;
      if (delta < 0) delta += 7;
      var next = DateTime.utc(f.year, f.month, f.day, hour, minute)
          .add(Duration(days: delta));
      if (!next.isAfter(f)) next = next.add(const Duration(days: 7));
      return next;
    case 'daily':
    default:
      var next = DateTime.utc(f.year, f.month, f.day, hour, minute);
      if (!next.isAfter(f)) next = next.add(const Duration(days: 1));
      return next;
  }
}

// Default port for each version when installed side-by-side.
const _defaultPorts = {
  14: 5414,
  15: 5415,
  16: 5416,
  17: 5417,
  18: 5418,
};

// ── Where an instance lives ───────────────────────────────────────────────────
//
// Every cluster the panel installs is created by the agent on this host, so it
// always sits on loopback and always has a systemd unit, a data directory and a
// local socket the agent can drive. The system instance — the cluster behind
// database.yaml — is the exception: it can be a machine on the LAN or a managed
// provider that this host knows nothing about beyond how to connect to it.
// Anything that opens a connection to an instance, or hands work to the agent
// for one, has to know which of the two it is dealing with.

/// Whether [instance] is the always-available cluster that backs the panel
/// itself. Identified by its port, which is fixed in database.yaml. Its port is
/// never editable and it can be neither stopped nor uninstalled.
bool isSystemInstance(PostgresInstance instance) =>
    instance.port == systemPgPort;

/// Host [instance] is reachable at from the panel.
String instanceHost(PostgresInstance instance) =>
    isSystemInstance(instance) ? systemPgHost : '127.0.0.1';

/// Whether [instance] runs on this host, and can therefore be managed by the
/// agent — started, stopped, reconfigured, backed up, exposed.
///
/// Only ever false for a system database that database.yaml points at another
/// machine. An address that happens to route back to this host still counts as
/// remote: the panel can read from it either way, and it should not guess that
/// some local systemd unit and data directory belong to it.
bool isLocalInstance(PostgresInstance instance) =>
    isLoopbackHost(instanceHost(instance));

/// Whether a dump of [instance] can be loaded back into it.
///
/// False for a cluster on another host, which the panel can only read. Such a
/// cluster pre-dates the panel and is somebody else's to operate: `pg_dump` over
/// TCP is a safe, read-only export, but `psql` replaying that dump would write
/// into a database the panel has no mandate over — and for the system cluster,
/// into the panel's own storage while it is running. Export is offered, restore
/// is not, rather than offering neither.
bool canRestoreInto(PostgresInstance instance) => isLocalInstance(instance);

/// Whether a dump can be loaded back into [db] specifically.
///
/// Narrower than [canRestoreInto]: a database the panel merely discovered is
/// export-only even on a cluster the agent fully manages. Being able to reach a
/// database is not the same as being entitled to overwrite it, and the panel
/// neither created this one nor knows what else depends on it.
bool canRestoreIntoDatabase(PostgresInstance instance, PostgresDatabase db) =>
    canRestoreInto(instance) && db.isExternal != true;

/// Whether [host] names this machine as far as the panel is concerned.
bool isLoopbackHost(String host) {
  final h = host.trim().toLowerCase();
  return h.isEmpty ||
      h == 'localhost' ||
      h == '::1' ||
      h == '[::1]' ||
      h.startsWith('127.') ||
      h.startsWith('/'); // a Unix socket directory, i.e. this host
}

/// How to reach [inst] to read statistics from it.
///
/// Local clusters are read through the read-only `gisila_monitor` role the
/// agent provisions on them. A remote system database cannot have that role —
/// the agent has no way to reach the host and create it — so the panel reuses
/// its own database.yaml credentials, which are by definition already working
/// against that cluster.
({pg.Endpoint endpoint, pg.ConnectionSettings settings}) statsTarget(
  PostgresInstance inst, {
  Duration connectTimeout = const Duration(seconds: 5),
  Duration queryTimeout = const Duration(seconds: 10),
}) {
  if (isLocalInstance(inst)) {
    return (
      endpoint: pg.Endpoint(
        host: '127.0.0.1',
        port: inst.port,
        database: 'postgres',
        username: 'gisila_monitor',
        password: inst.monitorPassword,
      ),
      settings: pg.ConnectionSettings(
        sslMode: pg.SslMode.disable,
        connectTimeout: connectTimeout,
        queryTimeout: queryTimeout,
      ),
    );
  }
  return (
    endpoint: pg.Endpoint(
      host: systemPgHost,
      port: systemPgPort,
      database: systemPgDatabase,
      username: systemPgUser,
      password: systemPgPassword,
    ),
    settings: pg.ConnectionSettings(
      sslMode: systemPgUseSsl ? pg.SslMode.require : pg.SslMode.disable,
      connectTimeout: connectTimeout,
      queryTimeout: queryTimeout,
    ),
  );
}

class PostgresService extends Service {
  Database get _db => db<Database>();

  // ── Instance CRUD ───────────────────────────────────────────────────────────

  Future<List<PostgresInstance>> listInstances() =>
      Query<PostgresInstance>(PostgresInstanceTable.metadata)
          .orderBy(PostgresInstanceTable.version)
          .all(_db.context());

  Future<PostgresInstance> findInstance(int id) async {
    final row = await Query<PostgresInstance>(PostgresInstanceTable.metadata)
        .where(PostgresInstanceTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Postgres instance #$id not found.');
    return row;
  }

  Future<PostgresInstance> installInstance({
    required int version,
    required String displayName,
    int? port,
  }) async {
    if (!kSupportedVersions.contains(version)) {
      throw HttpException(
          422, 'Unsupported version $version. Supported: $kSupportedVersions');
    }

    final existing =
        await Query<PostgresInstance>(PostgresInstanceTable.metadata)
            .where(PostgresInstanceTable.version.eq(version))
            .first(_db.context());
    if (existing != null) {
      if (existing.status == 'failed') {
        // A previous install attempt failed — remove the stale record so we
        // can start fresh.
        await Query<PostgresInstance>(PostgresInstanceTable.metadata)
            .where(PostgresInstanceTable.id.eq(existing.id!))
            .delete()
            .run(_db.context());
      } else {
        throw HttpException(409, 'PostgreSQL $version is already installed.');
      }
    }

    final resolvedPort = port ?? _defaultPorts[version] ?? (5432 + version);

    // Check port not already taken.
    final portConflict =
        await Query<PostgresInstance>(PostgresInstanceTable.metadata)
            .where(PostgresInstanceTable.port.eq(resolvedPort))
            .first(_db.context());
    if (portConflict != null) {
      throw HttpException(
          409, 'Port $resolvedPort is already used by another instance.');
    }

    // Never mark default until the install succeeds — a failed first attempt
    // used to become the default and then blocked Uninstall in the UI/API.
    final instance =
        await Query<PostgresInstance>(PostgresInstanceTable.metadata)
            .insert(<String, Object?>{
      'version': version,
      'displayName': displayName,
      'port': resolvedPort,
      'status': 'pending',
      'isDefault': false,
      'dataDirectory': '/var/lib/postgresql/$version/main',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());

    await _enqueue('install_instance', {'instanceId': instance.id});
    return findInstance(instance.id!);
  }

  /// Re-queue a failed install. The host was rolled back on failure, so this
  /// runs the full install path again against the same row.
  Future<PostgresInstance> retryInstall(int id) async {
    final instance = await findInstance(id);
    if (instance.status != 'failed') {
      throw HttpException(422, 'Only failed installations can be retried.');
    }
    if (isSystemInstance(instance)) {
      throw HttpException(422, 'Cannot retry the system database.');
    }
    await _patchInstance(id, {
      'status': 'pending',
      'errorMessage': null,
    });
    await _enqueue('install_instance', {'instanceId': id});
    return findInstance(id);
  }

  Future<PostgresInstance> setDefault(int id) async {
    final target = await findInstance(id);
    if (target.status != 'running') {
      throw HttpException(422, 'Instance must be running to set as default.');
    }

    // Clear current default.
    await Query<PostgresInstance>(PostgresInstanceTable.metadata)
        .where(PostgresInstanceTable.isDefault.eq(true))
        .update({'isDefault': false}).run(_db.context());

    await _patchInstance(id, {'isDefault': true});
    return findInstance(id);
  }

  /// Make a Postgres instance publicly reachable over TLS (or revert to
  /// localhost-only). When [isPublic] the agent obtains a Let's Encrypt cert for
  /// [domain], enables ssl + an SSL-only hostssl rule, opens the firewall, and
  /// the cluster becomes reachable at domain:port with sslmode=verify-full.
  Future<PostgresInstance> setPublicExposure(
    int id, {
    required bool isPublic,
    String? domain,
  }) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      throw HttpException(422, 'Instance must be running to change exposure.');
    }
    if (isSystemInstance(inst)) {
      // The panel's own cluster must never be exposed to the internet.
      throw HttpException(422, 'The system database cannot be made public.');
    }
    if (isPublic) {
      final host = (domain ?? '').trim().toLowerCase();
      if (host.isEmpty) {
        throw HttpException(422, 'A domain is required to make the database public.');
      }
      if (!RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$').hasMatch(host)) {
        throw HttpException(422, 'Enter a valid domain, e.g. db.example.com');
      }
      await _patchInstance(id, {
        'isPublic': true,
        'publicDomain': host,
        'errorMessage': null,
      });
      await _enqueue('expose_instance', {'instanceId': id});
    } else {
      await _patchInstance(id, {'isPublic': false});
      await _enqueue('unexpose_instance', {'instanceId': id});
    }
    return findInstance(id);
  }

  Future<PostgresInstance> startInstance(int id) async {
    final instance = await findInstance(id);
    if (instance.status == 'running') return instance;
    _requireLocal(instance, 'start this instance');
    await _patchInstance(id, {'status': 'pending'});
    await _enqueue('start_instance', {'instanceId': id});
    return findInstance(id);
  }

  Future<PostgresInstance> stopInstance(int id) async {
    final instance = await findInstance(id);
    if (isSystemInstance(instance)) {
      // Stopping this cluster would take the panel itself offline.
      throw HttpException(422, 'Cannot stop the system database.');
    }
    if (instance.status == 'stopped') return instance;
    await _enqueue('stop_instance', {'instanceId': id});
    return findInstance(id);
  }

  Future<void> uninstallInstance(int id) async {
    final instance = await findInstance(id);
    if (isSystemInstance(instance)) {
      throw HttpException(422, 'Cannot uninstall the system database.');
    }
    final failed = instance.status == 'failed';
    // Failed installs already rolled back on the host — allow removal even when
    // they were incorrectly marked as default (legacy rows).
    if (instance.isDefault == true && !failed) {
      throw HttpException(422,
          'Cannot uninstall the default instance. Set another as default first.');
    }
    await _patchInstance(id, {
      'status': 'uninstalling',
      if (failed) 'isDefault': false,
      if (failed) 'errorMessage': null,
    });
    await _enqueue('uninstall_instance', {'instanceId': id});
  }

  /// Reject an operation that only the agent can carry out when [instance]
  /// lives on another host.
  ///
  /// Everything in the Postgres lifecycle — creating databases and roles,
  /// applying settings, dumping and restoring — runs as `psql`/`pg_dump` on the
  /// cluster's own machine over a local socket. For a remote system database
  /// there is nothing there to talk to, and without this guard the job would be
  /// queued, fail somewhere inside the agent, and leave the row stuck in
  /// `pending` with no explanation.
  void _requireLocal(PostgresInstance instance, String action) {
    if (isLocalInstance(instance)) return;
    throw HttpException(
      422,
      'Cannot $action: the system database runs on ${instanceHost(instance)}, '
      'not on this host. The panel is only a client of that cluster — manage '
      'it where it lives, or on its provider.',
    );
  }

  /// Reject a restore into something the panel may read but not overwrite.
  ///
  /// Separate from [_requireLocal] because backups in both cases *are*
  /// supported — only the write-back is refused, so the message has to say that
  /// rather than implying backups are unavailable.
  void _requireRestorable(PostgresInstance instance, PostgresDatabase db) {
    if (canRestoreIntoDatabase(instance, db)) return;
    if (db.isExternal == true) {
      throw HttpException(
        422,
        '"${db.dbName}" was created outside the panel, so its backups are '
        'export-only. Download the dump and load it with psql — the panel will '
        'not overwrite a database it did not create.',
      );
    }
    throw HttpException(
      422,
      'This database runs on ${instanceHost(instance)}, not on this host, so '
      'the panel offers export-only backups for it. Download the dump and '
      'restore it where the cluster lives — replaying it from here would write '
      'into a cluster the panel does not manage.',
    );
  }

  /// Reject a write the panel has no standing to make against a database it only
  /// discovered. It holds no credentials for the owning role, and dropping or
  /// re-permissioning something it did not create is not its call.
  void _requireNotExternal(PostgresDatabase db, String action) {
    if (db.isExternal != true) return;
    throw HttpException(
      422,
      'Cannot $action: "${db.dbName}" was created outside the panel. The panel '
      'tracks it so it can be backed up, but does not manage it — do this with '
      'psql instead.',
    );
  }

  // ── Database CRUD ───────────────────────────────────────────────────────────

  Future<List<PostgresDatabase>> listDatabases(int instanceId) async {
    // Pick up anything created outside the panel before listing, so a database
    // made with psql shows up on its own and can be given a backup schedule.
    await _syncExternalDatabases(instanceId);
    return Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
        .where(PostgresDatabaseTable.instanceId.eq(instanceId))
        .orderBy(PostgresDatabaseTable.createdAt, desc: true)
        .all(_db.context());
  }

  /// Reconcile the panel's database rows with what is actually on the cluster.
  ///
  /// Databases the panel did not create — made with psql, by another tool, or by
  /// an older panel — get a row flagged `isExternal` so that backups, which key
  /// off that row, become possible at all. Nothing else about them is assumed:
  /// no password is stored and no write is ever offered.
  ///
  /// Rows for databases that have since disappeared are marked `dropped` rather
  /// than deleted, which keeps their existing dumps downloadable and stops the
  /// scheduler dumping a name that is no longer there. A database that comes
  /// back flips to `active` again.
  ///
  /// Entirely best-effort: this runs on a page load, so an unreachable or
  /// still-initialising cluster must fail quietly and leave the tracked rows
  /// alone rather than block the list.
  Future<void> _syncExternalDatabases(int instanceId) async {
    try {
      final inst = await findInstance(instanceId);
      if (inst.status != 'running') return;
      // Locally the read goes through `gisila_monitor`; if the agent has not
      // provisioned it yet there is nothing to connect with. The metrics
      // endpoint kicks that off, so just wait for a later call.
      if (isLocalInstance(inst) &&
          (inst.monitorPassword == null || inst.monitorPassword!.isEmpty)) {
        return;
      }
      // Throttle: the databases list is re-fetched on every visit, and this
      // opens a real connection. One reconcile per instance per interval is
      // plenty for picking up a hand-made database.
      final marker = 'gisila:pgdbsync:$instanceId';
      if (await RedisClient.instance.get(marker) != null) return;
      await RedisClient.instance.setEx(marker, 30, '1');

      final live = await _liveDatabaseNames(inst);
      if (live == null) return; // could not read the cluster

      final tracked = await Query<PostgresDatabase>(
        PostgresDatabaseTable.metadata,
      )
          .where(PostgresDatabaseTable.instanceId.eq(instanceId))
          .all(_db.context());
      final byName = {for (final d in tracked) d.dbName: d};
      final now = DateTime.now().toUtc().toIso8601String();

      for (final entry in live.entries) {
        final existing = byName[entry.key];
        if (existing == null) {
          await Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
              .insert(<String, Object?>{
            'instanceId': instanceId,
            'dbName': entry.key,
            // The observed owner, recorded for display only. The panel has no
            // credentials for it, hence the empty password.
            'roleName': entry.value,
            'password': '',
            'extensions': '[]',
            'roleAttributes': '[]',
            'isExternal': true,
            'status': 'active',
            'createdAt': now,
          }).run(_db.context());
        } else if (existing.isExternal == true && existing.status == 'dropped') {
          await _patchDatabase(existing.id!, {
            'status': 'active',
            'roleName': entry.value,
            'updatedAt': now,
          });
        }
      }

      // Externally-created rows whose database is gone from the cluster.
      for (final d in tracked) {
        if (d.isExternal != true || d.id == null) continue;
        if (d.status == 'dropped') continue;
        if (live.containsKey(d.dbName)) continue;
        await _patchDatabase(d.id!, {'status': 'dropped', 'updatedAt': now});
      }
    } catch (e) {
      logger.w('postgres: external database sync for #$instanceId failed: $e');
    }
  }

  /// Database names on [inst] mapped to their owning role, excluding templates
  /// and the built-in `postgres` maintenance database. Null when unreadable.
  Future<Map<String, String>?> _liveDatabaseNames(PostgresInstance inst) async {
    final target = statsTarget(inst, connectTimeout: const Duration(seconds: 3));
    pg.Connection? conn;
    try {
      conn = await pg.Connection.open(target.endpoint, settings: target.settings);
      final rows = await conn.execute(
        'SELECT d.datname, pg_get_userbyid(d.datdba) AS owner FROM pg_database d '
        'WHERE NOT d.datistemplate AND d.datallowconn',
      );
      final out = <String, String>{};
      for (final r in rows) {
        final m = r.toColumnMap();
        final name = m['datname']?.toString();
        if (name == null || name.isEmpty) continue;
        if (_pgBuiltinDatabases.contains(name)) continue;
        out[name] = m['owner']?.toString() ?? '';
      }
      return out;
    } catch (_) {
      return null;
    } finally {
      await conn?.close();
    }
  }

  Future<PostgresDatabase> findDatabase(int id) async {
    final row = await Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
        .where(PostgresDatabaseTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Database #$id not found.');
    return row;
  }

  Future<PostgresDatabase> createDatabase({
    required int instanceId,
    required String dbName,
    required String roleName,
    required String password,
    List<String>? extensions,
    List<String>? roleAttributes,
  }) async {
    final instance = await findInstance(instanceId);
    if (instance.status != 'running') {
      throw HttpException(
          422, 'Instance must be running to create a database.');
    }
    _requireLocal(instance, 'create a database here');

    _validateIdentifier('database name', dbName);
    _validateIdentifier('role name', roleName);
    final attrs = _normalizeRoleAttributes(roleAttributes);

    final db = await Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
        .insert(<String, Object?>{
      'instanceId': instanceId,
      'dbName': dbName,
      'roleName': roleName,
      'password': password,
      'extensions': jsonEncode(extensions ?? []),
      'roleAttributes': jsonEncode(attrs),
      'status': 'pending',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());

    await _enqueue('create_database', {
      'instanceId': instanceId,
      'databaseId': db.id,
    });
    return findDatabase(db.id!);
  }

  /// Change the role attributes (permissions) of an existing database user.
  /// The full desired set is supplied; the agent reconciles via `ALTER ROLE`,
  /// granting newly-requested attributes and revoking dropped ones.
  Future<PostgresDatabase> updateRoleAttributes(
    int id,
    List<String>? roleAttributes,
  ) async {
    final db = await findDatabase(id);
    if (db.status != 'active') {
      throw HttpException(
          422, 'Database role must be active to change its permissions.');
    }
    final instance = await findInstance(db.instanceId);
    if (instance.status != 'running') {
      throw HttpException(
          422, 'Instance must be running to change role permissions.');
    }
    _requireLocal(instance, 'change role permissions');
    _requireNotExternal(db, 'change role permissions');
    final attrs = _normalizeRoleAttributes(roleAttributes);
    await _patchDatabase(id, {
      'roleAttributes': jsonEncode(attrs),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _enqueue('alter_role', {
      'instanceId': db.instanceId,
      'databaseId': id,
    });
    return findDatabase(id);
  }

  /// Validate, de-duplicate and upper-case a requested role-attribute list
  /// against [kRoleAttributes]. Unknown attributes are rejected (these names
  /// are interpolated into SQL on the agent, so the whitelist is the guard).
  List<String> _normalizeRoleAttributes(List<String>? requested) {
    final out = <String>[];
    for (final raw in requested ?? const <String>[]) {
      final a = raw.trim().toUpperCase();
      if (a.isEmpty) continue;
      if (!kRoleAttributes.contains(a)) {
        throw HttpException(
            422,
            'Unknown role attribute "$raw". '
            'Allowed: ${kRoleAttributes.join(', ')}.');
      }
      if (!out.contains(a)) out.add(a);
    }
    return out;
  }

  Future<void> dropDatabase(int id) async {
    final db = await findDatabase(id);
    _requireNotExternal(db, 'drop this database');

    // If the database was never successfully created, remove the record directly
    // without involving the agent — there is nothing to drop on the server.
    if (db.status == 'failed' || db.status == 'pending') {
      await Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
          .where(PostgresDatabaseTable.id.eq(id))
          .delete()
          .run(_db.context());
      return;
    }

    final instance = await findInstance(db.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to drop a database.');
    }
    _requireLocal(instance, 'drop this database');
    await _patchDatabase(id, {'status': 'dropped'});
    await _enqueue('drop_database', {
      'instanceId': db.instanceId,
      'databaseId': id,
    });
  }

  // ── Connection info ─────────────────────────────────────────────────────────

  Map<String, Object?> connectionInfo(
      PostgresInstance instance, PostgresDatabase db) {
    // For a local cluster, use 127.0.0.1 rather than 'localhost': PgBouncer
    // binds IPv4 only, but 'localhost' resolves to ::1 (IPv6) first on
    // dual-stack hosts, so a libpq client gets ECONNREFUSED on 6432 before it
    // ever tries 127.0.0.1. Pinning IPv4 keeps connection strings working
    // regardless of resolver order.
    final host = instanceHost(instance);
    final port = instance.port;
    // A discovered database has no panel-held credentials, so there is no
    // password or ready-made URL to show — only where it lives and who owns it.
    // Emitting the empty string would render a connection string that silently
    // fails to authenticate.
    if (db.isExternal == true) {
      return <String, Object?>{
        'host': host,
        'port': port,
        'database': db.dbName,
        'username': db.roleName,
        'external': true,
      };
    }
    final url =
        'postgresql://${db.roleName}:${db.password}@$host:$port/${db.dbName}';
    final info = <String, Object?>{
      'host': host,
      'port': port,
      'database': db.dbName,
      'username': db.roleName,
      'password': db.password,
      'url': url,
    };
    // When the instance is publicly exposed, also surface the external,
    // TLS-verified connection string clients should use over the internet.
    if (instance.isPublic == true &&
        (instance.publicDomain ?? '').isNotEmpty) {
      final pubHost = instance.publicDomain!;
      info['publicHost'] = pubHost;
      info['publicUrl'] =
          'postgresql://${db.roleName}:${db.password}@$pubHost:$port/${db.dbName}?sslmode=verify-full';
    }
    return info;
  }

  // ── Metrics ───────────────────────────────────────────────────────────────

  /// Live metrics for an instance: connection counts, throughput, cache hit
  /// ratio, per-database sizes, plus host CPU/RAM sampled by the worker.
  ///
  /// Connection/DB stats are read over a direct connection using the read-only
  /// `gisila_monitor` role. If that role is not provisioned yet, returns
  /// `{status: 'initializing'}` and triggers provisioning in the background;
  /// the UI polls until it flips to `ok`.
  Future<Map<String, Object?>> metrics(int id) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      return {'status': 'not_running'};
    }
    // A remote system database has no monitor role and never will — the agent
    // can't reach that host to create one — so there is nothing to wait for.
    if (isLocalInstance(inst) &&
        (inst.monitorPassword == null || inst.monitorPassword!.isEmpty)) {
      await _ensureMonitor(inst);
      return {'status': 'initializing'};
    }
    try {
      final sql = await _queryStats(inst);
      final host = await _hostStats(id);
      return {'status': 'ok', 'host': host, ...sql};
    } catch (e) {
      return await _statsFailure(inst, e);
    }
  }

  /// Turn a failed stats connection into a status the UI can act on.
  ///
  /// Locally, the usual cause is that the monitor role isn't created yet (an
  /// auth failure on a cluster the agent has only just installed), so this
  /// kicks off provisioning and asks the client to poll. Remotely there is no
  /// provisioning step that could help, and reporting `initializing` would
  /// leave the panel spinning forever on a connection that is never coming
  /// up — so say plainly that the cluster could not be read.
  Future<Map<String, Object?>> _statsFailure(
    PostgresInstance inst,
    Object error,
  ) async {
    if (isLocalInstance(inst)) {
      await _ensureMonitor(inst);
      return {'status': 'initializing', 'detail': error.toString()};
    }
    return {
      'status': 'unreachable',
      'detail': 'Could not read stats from the system database at '
          '${instanceHost(inst)}:${inst.port} — $error',
    };
  }

  Future<Map<String, Object?>> _queryStats(PostgresInstance inst) async {
    final target = statsTarget(inst);
    final conn = await pg.Connection.open(
      target.endpoint,
      settings: target.settings,
    );
    try {
      final activity = (await conn.execute(
        "SELECT count(*) AS total, "
        "count(*) FILTER (WHERE state='active') AS active, "
        "count(*) FILTER (WHERE state='idle') AS idle, "
        "count(*) FILTER (WHERE state='idle in transaction') AS idle_in_txn, "
        "count(*) FILTER (WHERE wait_event_type='Lock') AS waiting "
        "FROM pg_stat_activity WHERE backend_type='client backend'",
      ))
          .first
          .toColumnMap();

      final maxConn = _toInt((await conn.execute(
        "SELECT setting::int AS v FROM pg_settings WHERE name='max_connections'",
      ))
          .first
          .toColumnMap()['v']);

      final db = (await conn.execute(
        "SELECT coalesce(sum(xact_commit),0)::bigint AS commits, "
        "coalesce(sum(xact_rollback),0)::bigint AS rollbacks, "
        "coalesce(sum(blks_hit),0)::bigint AS hits, "
        "coalesce(sum(blks_read),0)::bigint AS reads, "
        "coalesce(sum(tup_inserted),0)::bigint AS inserted, "
        "coalesce(sum(tup_updated),0)::bigint AS updated, "
        "coalesce(sum(tup_deleted),0)::bigint AS deleted, "
        "coalesce(sum(deadlocks),0)::bigint AS deadlocks "
        "FROM pg_stat_database",
      ))
          .first
          .toColumnMap();

      // pg_database_size() raises for a database the role cannot connect to,
      // which would sink the whole metrics call. `gisila_monitor` holds
      // pg_monitor and never hits that, but the panel's own role — used for a
      // remote system cluster — is an ordinary user, so skip what it can't
      // read instead of failing.
      final sizes = (await conn.execute(
        "SELECT datname, CASE WHEN has_database_privilege(datname, 'CONNECT') "
        "THEN pg_database_size(datname)::bigint END AS size "
        "FROM pg_database WHERE datname NOT IN ('template0','template1') "
        "ORDER BY size DESC NULLS LAST",
      ))
          .map((r) {
        final m = r.toColumnMap();
        return {'name': m['datname'], 'sizeBytes': _toInt(m['size'])};
      }).toList();

      final uptime = _toInt((await conn.execute(
        "SELECT EXTRACT(EPOCH FROM (now()-pg_postmaster_start_time()))::bigint AS s",
      ))
          .first
          .toColumnMap()['s']);

      final hits = _toInt(db['hits']);
      final reads = _toInt(db['reads']);
      final total = hits + reads;
      final cacheHitRatio = total > 0 ? hits / total : 1.0;

      return {
        'connections': {
          'total': _toInt(activity['total']),
          'active': _toInt(activity['active']),
          'idle': _toInt(activity['idle']),
          'idleInTransaction': _toInt(activity['idle_in_txn']),
          'waiting': _toInt(activity['waiting']),
          'max': maxConn,
        },
        'throughput': {
          'commits': _toInt(db['commits']),
          'rollbacks': _toInt(db['rollbacks']),
          'inserted': _toInt(db['inserted']),
          'updated': _toInt(db['updated']),
          'deleted': _toInt(db['deleted']),
          'deadlocks': _toInt(db['deadlocks']),
        },
        'cacheHitRatio': cacheHitRatio,
        'uptimeSeconds': uptime,
        'databases': sizes,
      };
    } finally {
      await conn.close();
    }
  }

  /// Read the host CPU%/RAM snapshot the worker writes to Redis for this
  /// instance's systemd unit, if present.
  Future<Map<String, Object?>?> _hostStats(int id) async {
    try {
      final raw = await RedisClient.instance.get('gisila:pgstat:$id');
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Read the current value of every tunable setting from `pg_settings`.
  Future<Map<String, Object?>> getConfig(int id) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      return {'status': 'not_running', 'settings': []};
    }
    if (isLocalInstance(inst) &&
        (inst.monitorPassword == null || inst.monitorPassword!.isEmpty)) {
      await _ensureMonitor(inst);
      return {'status': 'initializing', 'settings': []};
    }
    try {
      final target = statsTarget(inst);
      final conn = await pg.Connection.open(
        target.endpoint,
        settings: target.settings,
      );
      try {
        final names = kTunableSettings.map((s) => "'$s'").join(',');
        final rows = (await conn.execute(
          "SELECT name, setting, unit, short_desc, context, vartype, "
          "min_val, max_val, enumvals, boot_val, pending_restart "
          "FROM pg_settings WHERE name IN ($names)",
        ))
            .map((r) {
          final m = r.toColumnMap();
          return {
            'name': m['name'],
            'value': m['setting']?.toString(),
            'unit': m['unit']?.toString(),
            'description': m['short_desc']?.toString(),
            'context': m['context']?.toString(),
            'type': m['vartype']?.toString(),
            'min': m['min_val']?.toString(),
            'max': m['max_val']?.toString(),
            'enumVals': m['enumvals']?.toString(),
            'bootValue': m['boot_val']?.toString(),
            'pendingRestart': m['pending_restart'] == true,
          };
        }).toList();
        // Preserve the curated order.
        rows.sort((a, b) => kTunableSettings
            .indexOf(a['name'] as String)
            .compareTo(kTunableSettings.indexOf(b['name'] as String)));
        return {'status': 'ok', 'settings': rows};
      } finally {
        await conn.close();
      }
    } catch (e) {
      return {...await _statsFailure(inst, e), 'settings': <Object?>[]};
    }
  }

  /// Apply configuration changes. Only whitelisted keys are accepted; the
  /// change is applied with `ALTER SYSTEM SET` and the cluster restarted by the
  /// worker (some settings such as `max_connections` require a restart).
  Future<PostgresInstance> updateConfig(
      int id, Map<String, String> settings) async {
    final inst = await findInstance(id);
    if (inst.status != 'running') {
      throw HttpException(422, 'Instance must be running to change settings.');
    }
    _requireLocal(inst, 'change settings');
    final clean = <String, String>{};
    settings.forEach((key, value) {
      if (!kTunableSettings.contains(key)) return;
      final v = value.trim();
      // Reject values containing quotes/backslashes to keep ALTER SYSTEM safe.
      if (v.contains("'") || v.contains(r'\')) {
        throw HttpException(422, 'Invalid value for $key.');
      }
      clean[key] = v;
    });
    if (clean.isEmpty) {
      throw HttpException(422, 'No valid settings to apply.');
    }
    await _patchInstance(id, {'status': 'pending'});
    await _enqueue('configure_instance', {
      'instanceId': id,
      'settings': clean,
    });
    return findInstance(id);
  }

  /// Generate + persist a monitor password (if missing) and enqueue creation of
  /// the `gisila_monitor` role on the instance.
  ///
  /// No-op for a remote system database: the agent provisions that role with a
  /// local `psql`, so queueing the job would only produce a failing job on a
  /// loop for every metrics poll.
  Future<void> _ensureMonitor(PostgresInstance inst) async {
    if (!isLocalInstance(inst)) return;
    if (inst.monitorPassword == null || inst.monitorPassword!.isEmpty) {
      await _patchInstance(inst.id!, {'monitorPassword': generatePassword()});
    }
    await _enqueue('ensure_monitor', {'instanceId': inst.id});
  }

  static int _toInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  // ── Backups ───────────────────────────────────────────────────────────────

  Future<List<PostgresBackup>> listBackups(int databaseId) =>
      Query<PostgresBackup>(PostgresBackupTable.metadata)
          .where(PostgresBackupTable.databaseId.eq(databaseId))
          .orderBy(PostgresBackupTable.createdAt, desc: true)
          .all(_db.context());

  Future<PostgresBackup> findBackup(int id) async {
    final row = await Query<PostgresBackup>(PostgresBackupTable.metadata)
        .where(PostgresBackupTable.id.eq(id))
        .first(_db.context());
    if (row == null) throw NotFound('Backup #$id not found.');
    return row;
  }

  /// Queue a backup of [databaseId] with the given [scope]. Returns the new
  /// pending [PostgresBackup] row; the worker fills in the file + status.
  Future<PostgresBackup> triggerBackup(
    int databaseId, {
    String scope = 'full',
    String trigger = 'manual',
  }) async {
    if (!kBackupScopes.contains(scope)) {
      throw HttpException(422, 'Invalid backup scope "$scope".');
    }
    final db = await findDatabase(databaseId);
    if (db.status != 'active') {
      throw HttpException(422, 'Database must be active to back it up.');
    }
    final instance = await findInstance(db.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to back up a database.');
    }
    // Deliberately no locality check: a dump is a read, and the agent can take
    // one over TCP from a cluster on another host. See [canRestoreInto] for why
    // the reverse direction stays blocked.
    final row = await Query<PostgresBackup>(PostgresBackupTable.metadata)
        .insert(<String, Object?>{
      'databaseId': databaseId,
      'scope': scope,
      'status': 'pending',
      'trigger': trigger,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());

    await _enqueue('backup_database', {
      'instanceId': db.instanceId,
      'databaseId': databaseId,
      'backupId': row.id,
    });
    return row;
  }

  /// Delete a backup row and its file on disk.
  Future<void> deleteBackup(int id) async {
    final b = await findBackup(id);
    final path = b.filePath;
    if (path != null && path.isNotEmpty) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // best-effort — the row is removed regardless.
      }
    }
    await Query<PostgresBackup>(PostgresBackupTable.metadata)
        .where(PostgresBackupTable.id.eq(id))
        .delete()
        .run(_db.context());
  }

  /// Restore a database from one of its completed backups.
  Future<void> restoreFromBackup(int backupId) async {
    final b = await findBackup(backupId);
    if (b.status != 'completed' || (b.filePath?.isEmpty ?? true)) {
      throw HttpException(422, 'Backup is not available to restore.');
    }
    final db = await findDatabase(b.databaseId);
    final instance = await findInstance(db.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to restore.');
    }
    _requireRestorable(instance, db);
    await _enqueue('restore_database', {
      'instanceId': db.instanceId,
      'databaseId': db.id,
      'inputPath': b.filePath,
    });
  }

  /// Stage an uploaded dump to disk and queue a restore from it.
  Future<void> saveUploadAndRestore(
    int databaseId,
    List<int> bytes,
    String filename,
  ) async {
    final db = await findDatabase(databaseId);
    final instance = await findInstance(db.instanceId);
    if (instance.status != 'running') {
      throw HttpException(422, 'Instance must be running to restore.');
    }
    _requireRestorable(instance, db);
    if (bytes.isEmpty) throw HttpException(422, 'Uploaded file is empty.');

    final lower = filename.toLowerCase();
    final String ext;
    if (lower.endsWith('.sql.gz') || lower.endsWith('.gz')) {
      ext = '.sql.gz';
    } else if (lower.endsWith('.sql')) {
      ext = '.sql';
    } else {
      throw HttpException(422, 'Upload must be a .sql or .sql.gz file.');
    }

    final dir = Directory('${pgBackupDir()}/uploads');
    await dir.create(recursive: true);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final suffix = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final path = '${dir.path}/upload-$stamp-$suffix$ext';
    await File(path).writeAsBytes(bytes, flush: true);

    await _enqueue('restore_database', {
      'instanceId': db.instanceId,
      'databaseId': db.id,
      'inputPath': path,
    });
  }

  // ── Backup schedule ─────────────────────────────────────────────────────────

  /// Get the schedule for a database, creating a disabled default if absent.
  Future<PostgresBackupSchedule> getSchedule(int databaseId) async {
    await findDatabase(databaseId); // validates existence
    final existing =
        await Query<PostgresBackupSchedule>(PostgresBackupScheduleTable.metadata)
            .where(PostgresBackupScheduleTable.databaseId.eq(databaseId))
            .first(_db.context());
    if (existing != null) return existing;
    return Query<PostgresBackupSchedule>(PostgresBackupScheduleTable.metadata)
        .insert(<String, Object?>{
      'databaseId': databaseId,
      'enabled': false,
      'frequency': 'daily',
      'hour': 2,
      'minute': 0,
      'scope': 'full',
      'keepCount': 7,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    }).one(_db.context());
  }

  Future<PostgresBackupSchedule> updateSchedule(
    int databaseId, {
    bool? enabled,
    String? frequency,
    int? hour,
    int? minute,
    int? weekday,
    String? scope,
    int? keepCount,
  }) async {
    final current = await getSchedule(databaseId);
    if (frequency != null && !kBackupFrequencies.contains(frequency)) {
      throw HttpException(422, 'Invalid frequency "$frequency".');
    }
    if (scope != null && !kBackupScopes.contains(scope)) {
      throw HttpException(422, 'Invalid scope "$scope".');
    }

    final mergedEnabled = enabled ?? current.enabled ?? false;
    final mergedFreq = frequency ?? current.frequency ?? 'daily';
    final mergedHour = (hour ?? current.hour ?? 2).clamp(0, 23);
    final mergedMinute = (minute ?? current.minute ?? 0).clamp(0, 59);
    final mergedWeekday =
        weekday != null ? weekday.clamp(0, 6) : current.weekday;

    final patch = <String, Object?>{
      'enabled': mergedEnabled,
      'frequency': mergedFreq,
      'hour': mergedHour,
      'minute': mergedMinute,
      'weekday': mergedWeekday,
      if (scope != null) 'scope': scope,
      if (keepCount != null) 'keepCount': keepCount.clamp(1, 365),
      'nextRunAt': mergedEnabled
          ? computeNextRun(mergedFreq, mergedHour, mergedMinute, mergedWeekday,
                  DateTime.now().toUtc())
              .toIso8601String()
          : null,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };

    await Query<PostgresBackupSchedule>(PostgresBackupScheduleTable.metadata)
        .where(PostgresBackupScheduleTable.databaseId.eq(databaseId))
        .update(patch)
        .run(_db.context());
    return getSchedule(databaseId);
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _validateIdentifier(String label, String value) {
    final re = RegExp(r'^[a-z][a-z0-9_]{0,62}$');
    if (!re.hasMatch(value)) {
      throw HttpException(
          422,
          'Invalid $label "$value". Must start with a letter, contain only '
          'lowercase letters, digits and underscores, max 63 chars.');
    }
  }

  Future<void> _patchInstance(int id, Map<String, Object?> data) =>
      Query<PostgresInstance>(PostgresInstanceTable.metadata)
          .where(PostgresInstanceTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _patchDatabase(int id, Map<String, Object?> data) =>
      Query<PostgresDatabase>(PostgresDatabaseTable.metadata)
          .where(PostgresDatabaseTable.id.eq(id))
          .update(data)
          .run(_db.context());

  Future<void> _enqueue(String action, Map<String, Object?> payload) =>
      RedisClient.instance.rpush(
        'gisila:queue:postgres',
        jsonEncode({'action': action, ...payload}),
      );
}

/// Generate a random password (48 URL-safe chars).
String generatePassword() {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final rng = Random.secure();
  return List.generate(32, (_) => chars[rng.nextInt(chars.length)]).join();
}
