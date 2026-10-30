import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/models/models.dart';
import 'package:pointycastle/export.dart';

/// Encrypts secrets the panel stores in Postgres: env var values, TOTP
/// secrets, deployment env snapshots (PNL-12) and the credentials of the
/// databases, storage and SMTP it manages (PNL-25). See [sealedColumns].
///
/// AES-256-GCM with a random 96-bit nonce per value. The column's name is the
/// associated data, so a sealed value only opens in the column it was written
/// for. Stored form: `enc:v1:<base64(nonce ‖ ciphertext ‖ tag)>`.
///
/// The key is 32 random bytes, base64, in `/etc/gisila/secret.key` (0600,
/// owned by the panel user; `GISILA_SECRET_KEY_FILE` overrides the path).
/// It is separate from `JWT_SECRET`, so rotating that doesn't lose secrets.
class SecretBox {
  SecretBox(Uint8List key) : _key = KeyParameter(key) {
    if (key.length != 32) {
      throw ArgumentError('SecretBox key must be 32 bytes, got ${key.length}');
    }
  }

  static const prefix = 'enc:v1:';

  // Column labels, used as associated data.
  static const envVarValue = 'env_vars.value';
  static const totpSecret = 'user_totps.secret';
  static const deployConfig = 'deployments.deploy_config';
  static const pgMonitorPassword = 'postgres_instances.monitor_password';
  static const pgDatabasePassword = 'postgres_databases.password';
  static const mongoRootPassword = 'mongo_instances.root_password';
  static const mongoMonitorPassword = 'mongo_instances.monitor_password';
  static const mongoDatabasePassword = 'mongo_databases.password';
  static const storageProviderSecret = 'storage_providers.secret_key';
  // Always written sealed, and keyed by app_id rather than id, so they stay
  // out of [sealedColumns] (whose sweep selects by id).
  static const appWebhookSecret = 'app_webhooks.secret';
  static const appWebhookStatusToken = 'app_webhooks.status_token';
  static const storageBucketSecret = 'storage_buckets.secret_key';
  static const smtpPassword = 'smtp_configs.smtp_password';

  /// Every sealed column, as (table, column, label).
  static const sealedColumns = [
    ('env_vars', 'value', envVarValue),
    ('user_totps', 'secret', totpSecret),
    ('deployments', 'deploy_config', deployConfig),
    ('postgres_instances', 'monitor_password', pgMonitorPassword),
    ('postgres_databases', 'password', pgDatabasePassword),
    ('mongo_instances', 'root_password', mongoRootPassword),
    ('mongo_instances', 'monitor_password', mongoMonitorPassword),
    ('mongo_databases', 'password', mongoDatabasePassword),
    ('storage_providers', 'secret_key', storageProviderSecret),
    ('storage_buckets', 'secret_key', storageBucketSecret),
    ('smtp_configs', 'smtp_password', smtpPassword),
  ];

  static const _nonceLength = 12;
  static final _random = Random.secure();

  final KeyParameter _key;

  static SecretBox? _instance;

  /// The process-wide box, set by [load] (or [instance=] in tests).
  static SecretBox get instance =>
      _instance ??
      (throw StateError('SecretBox.load() has not run in this isolate.'));
  static set instance(SecretBox box) => _instance = box;

  static bool isSealed(String value) => value.startsWith(prefix);

  /// Encrypts [plaintext] for the column [column].
  String seal(String plaintext, String column) {
    final nonce = Uint8List.fromList(
        List<int>.generate(_nonceLength, (_) => _random.nextInt(256)));
    final out = _cipher(true, nonce, column)
        .process(Uint8List.fromList(utf8.encode(plaintext)));
    return '$prefix${base64.encode([...nonce, ...out])}';
  }

  /// Decrypts a value written by [seal] for [column]. A value without the
  /// prefix is a row from before encryption and comes back unchanged.
  /// Throws [StateError] if the value was tampered with, sealed for another
  /// column, or sealed with another key.
  String open(String stored, String column) {
    if (!isSealed(stored)) return stored;
    try {
      final raw = base64.decode(stored.substring(prefix.length));
      final nonce = Uint8List.sublistView(raw, 0, _nonceLength);
      final body = Uint8List.sublistView(raw, _nonceLength);
      return utf8.decode(_cipher(false, nonce, column).process(body));
    } catch (_) {
      // Bad base64, too short, or the GCM tag doesn't match.
      throw StateError('Could not decrypt a $column value: wrong key or '
          'corrupted data.');
    }
  }

  String? sealOrNull(String? plaintext, String column) =>
      plaintext == null ? null : seal(plaintext, column);

  String? openOrNull(String? stored, String column) =>
      stored == null ? null : open(stored, column);

  /// Like [sealOrNull], but an empty string stays empty, so `isEmpty` checks
  /// on the stored value ("no password yet") keep meaning the same thing.
  String? sealOrEmpty(String? plaintext, String column) =>
      plaintext == null || plaintext.isEmpty ? plaintext : seal(plaintext, column);

  GCMBlockCipher _cipher(bool encrypt, Uint8List nonce, String column) =>
      GCMBlockCipher(AESEngine())
        ..init(
          encrypt,
          AEADParameters(
              _key, 128, nonce, Uint8List.fromList(utf8.encode(column))),
        );

  // ── Key file ───────────────────────────────────────────────────────────────

  /// Where the key lives. Dev mode (`AGENT_MODE=dev`) defaults to
  /// `.secret.key` in the working directory, which git ignores.
  static String get keyPath {
    final configured = env['GISILA_SECRET_KEY_FILE']?.trim() ?? '';
    if (configured.isNotEmpty) return configured;
    return hostConfig.agentMode == 'dev'
        ? '.secret.key'
        : '/etc/gisila/secret.key';
  }

  /// Loads the key into [instance].
  ///
  /// With [database] (the panel server, once, before serving) a missing key
  /// file is created, unless sealed values already exist: then the key was
  /// lost and a new one would silently orphan them, so this throws. Without
  /// it (the worker, extra isolates) the file must exist; a server that
  /// starts at the same time gets [wait] to create it.
  static Future<SecretBox> load({
    Database? database,
    String? path,
    Duration wait = const Duration(seconds: 30),
  }) async {
    final file = File(path ?? keyPath);
    final deadline = DateTime.now().add(wait);
    while (true) {
      final key = _readKey(file);
      if (key != null) return _instance = SecretBox(key);
      if (database != null && !file.existsSync()) {
        if (await _hasSealedRows(database)) {
          throw StateError('${file.path} is missing but the database holds '
              'values encrypted with it. Restore the key file from a backup; '
              'a new key cannot decrypt them.');
        }
        _createKey(file);
        continue;
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('No secret key at ${file.path}. The panel server '
            'creates it on first start (or install.sh does); set '
            'GISILA_SECRET_KEY_FILE if it lives elsewhere.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Panel server start-up, once, before any isolate serves: load or create
  /// the key, then encrypt values still stored in plaintext.
  static Future<void> prepare() async {
    final database = await Database.connect(databaseConfig);
    try {
      final box = await load(database: database);
      await box.sealPlaintextRows(database);
    } finally {
      await database.close();
    }
  }

  /// The key in [file], or null while it is missing or still being written.
  static Uint8List? _readKey(File file) {
    if (!file.existsSync()) return null;
    final text = file.readAsStringSync().trim();
    if (text.isEmpty) return null;
    final Uint8List key;
    try {
      key = base64.decode(text);
    } on FormatException {
      throw StateError('${file.path} is not base64 (expected 32 random '
          'bytes: `head -c 32 /dev/urandom | base64`).');
    }
    if (key.length != 32) {
      throw StateError('${file.path} holds ${key.length} bytes; the key must '
          'be 32.');
    }
    return key;
  }

  static void _createKey(File file) {
    final key = List<int>.generate(32, (_) => _random.nextInt(256));
    final tmp = File('${file.path}.tmp-$pid');
    tmp.writeAsStringSync('');
    // Private before the key goes in.
    if (!Platform.isWindows) Process.runSync('chmod', ['600', tmp.path]);
    tmp.writeAsStringSync('${base64.encode(key)}\n', flush: true);
    if (file.existsSync()) {
      // Another process won the race; keep its key.
      tmp.deleteSync();
      return;
    }
    tmp.renameSync(file.path);
    logger.i('secret_box: created ${file.path}. Back it up with the '
        'database: encrypted values cannot be read without it.');
  }

  static Future<bool> _hasSealedRows(Database database) async {
    final result = await database.context().execute('SELECT ${[
      for (final (table, column, _) in sealedColumns)
        "EXISTS (SELECT 1 FROM $table WHERE $column LIKE 'enc:v1:%')",
    ].join(' OR ')}');
    return result.first.first == true;
  }

  // ── Migrating plaintext rows ──────────────────────────────────────────────

  /// Encrypts every value still stored in plaintext. Idempotent; the panel
  /// server runs it on start so upgraded installs get there without a step.
  /// Returns how many values it sealed.
  Future<int> sealPlaintextRows(Database database) async {
    var sealed = 0;
    for (final (table, column, label) in sealedColumns) {
      // Empty values stay empty (see [sealOrEmpty]).
      final rows = await database.context().execute(
            'SELECT id, $column FROM $table '
            "WHERE $column IS NOT NULL AND $column <> '' "
            "AND $column NOT LIKE 'enc:v1:%'",
          );
      for (final row in rows) {
        // Compare-and-set, so a value changed meanwhile is left to its writer.
        final updated = await database.context().execute(
              'UPDATE $table SET $column = \$1 WHERE id = \$2 AND $column = \$3',
              parameters: [seal(row[1]! as String, label), row[0], row[1]],
            );
        sealed += updated.affectedRows;
      }
    }
    if (sealed > 0) {
      logger.i('secret_box: encrypted $sealed stored secret value(s).');
    }
    return sealed;
  }
}

/// Plaintext views of the sealed columns.
extension EnvVarSecret on EnvVar {
  /// This row with its value decrypted.
  EnvVar opened() => EnvVar(
        id: id,
        appId: appId,
        name: name,
        value: SecretBox.instance.openOrNull(value, SecretBox.envVarValue),
        isSecret: isSecret,
        updatedAt: updatedAt,
      );
}

extension UserTotpSecret on UserTotp {
  String get plainSecret =>
      SecretBox.instance.open(secret, SecretBox.totpSecret);
}

extension DeploymentSecret on Deployment {
  String? get plainDeployConfig =>
      SecretBox.instance.openOrNull(deployConfig, SecretBox.deployConfig);
}

extension PostgresInstanceSecret on PostgresInstance {
  String? get plainMonitorPassword => SecretBox.instance
      .openOrNull(monitorPassword, SecretBox.pgMonitorPassword);
}

extension PostgresDatabaseSecret on PostgresDatabase {
  String get plainPassword =>
      SecretBox.instance.open(password, SecretBox.pgDatabasePassword);
}

extension MongoInstanceSecret on MongoInstance {
  String? get plainRootPassword => SecretBox.instance
      .openOrNull(rootPassword, SecretBox.mongoRootPassword);
  String? get plainMonitorPassword => SecretBox.instance
      .openOrNull(monitorPassword, SecretBox.mongoMonitorPassword);
}

extension MongoDatabaseSecret on MongoDatabase {
  String get plainPassword =>
      SecretBox.instance.open(password, SecretBox.mongoDatabasePassword);
}

extension StorageProviderSecret on StorageProvider {
  String get plainSecretKey =>
      SecretBox.instance.open(secretKey, SecretBox.storageProviderSecret);
}

extension StorageBucketSecret on StorageBucket {
  String get plainSecretKey =>
      SecretBox.instance.open(secretKey, SecretBox.storageBucketSecret);
}

extension SmtpConfigSecret on SmtpConfig {
  String? get plainSmtpPassword =>
      SecretBox.instance.openOrNull(smtpPassword, SecretBox.smtpPassword);
}
