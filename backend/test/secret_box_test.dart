import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gisila_orm/gisila.dart';
import 'package:gisila_panel/infra/secret_box.dart';
import 'package:test/test.dart';

/// The database tests need a throwaway Postgres; they create their own
/// tables. e.g. `GISILA_TEST_PG=localhost:5455:sb:postgres:pw`.
final _pg = Platform.environment['GISILA_TEST_PG'];

Uint8List _key(int fill) => Uint8List(32)..fillRange(0, 32, fill);

void main() {
  final box = SecretBox(_key(1));

  group('seal/open', () {
    test('sealOrEmpty keeps null and empty as they are', () {
      expect(box.sealOrEmpty(null, SecretBox.smtpPassword), isNull);
      expect(box.sealOrEmpty('', SecretBox.smtpPassword), '');
      expect(box.sealOrEmpty('x', SecretBox.smtpPassword),
          startsWith(SecretBox.prefix));
    });

    test('round-trips, with a fresh nonce each time', () {
      final a = box.seal('postgres://u:p@h/db', SecretBox.envVarValue);
      final b = box.seal('postgres://u:p@h/db', SecretBox.envVarValue);
      expect(a, startsWith(SecretBox.prefix));
      expect(a, isNot(b));
      expect(a, isNot(contains('postgres')));
      expect(box.open(a, SecretBox.envVarValue), 'postgres://u:p@h/db');
      expect(box.open(box.seal('', SecretBox.envVarValue),
          SecretBox.envVarValue), '');
    });

    test('plaintext from before encryption passes through', () {
      expect(box.open('legacy', SecretBox.totpSecret), 'legacy');
      expect(box.openOrNull(null, SecretBox.totpSecret), isNull);
    });

    test('refuses another column, another key, or tampering', () {
      final sealed = box.seal('JBSWY3DPEHPK3PXP', SecretBox.totpSecret);
      expect(() => box.open(sealed, SecretBox.envVarValue), throwsStateError);
      expect(() => SecretBox(_key(2)).open(sealed, SecretBox.totpSecret),
          throwsStateError);
      final raw = base64.decode(sealed.substring(SecretBox.prefix.length));
      raw[raw.length - 1] ^= 1;
      final tampered = '${SecretBox.prefix}${base64.encode(raw)}';
      expect(() => box.open(tampered, SecretBox.totpSecret), throwsStateError);
      expect(() => box.open('${SecretBox.prefix}AAAA', SecretBox.totpSecret),
          throwsStateError);
    });

    test('key must be 32 bytes', () {
      expect(() => SecretBox(Uint8List(16)), throwsArgumentError);
    });
  });

  group('key file', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('secretbox_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('loads an existing key', () async {
      final f = File('${tmp.path}/secret.key')
        ..writeAsStringSync('${base64.encode(_key(3))}\n');
      final loaded = await SecretBox.load(path: f.path);
      expect(SecretBox(_key(3)).open(
          loaded.seal('x', SecretBox.envVarValue), SecretBox.envVarValue), 'x');
      expect(identical(SecretBox.instance, loaded), isTrue);
    });

    test('rejects a malformed key', () async {
      final f = File('${tmp.path}/secret.key')..writeAsStringSync('not b64!');
      await expectLater(SecretBox.load(path: f.path), throwsStateError);
      f.writeAsStringSync(base64.encode(Uint8List(16)));
      await expectLater(SecretBox.load(path: f.path), throwsStateError);
    });

    test('without a database a missing key is never created', () async {
      final path = '${tmp.path}/secret.key';
      await expectLater(
          SecretBox.load(path: path, wait: const Duration(milliseconds: 300)),
          throwsStateError);
      expect(File(path).existsSync(), isFalse);
    });

    test('waits for the server to write the key', () async {
      final f = File('${tmp.path}/secret.key');
      final loading = SecretBox.load(path: f.path);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      f.writeAsStringSync(base64.encode(_key(4)));
      await loading;
    });
  });

  group('database', () {
    late Database db;
    late Directory tmp;

    setUp(() async {
      final [host, port, name, user, pass] = _pg!.split(':');
      db = await Database.connect(DatabaseConfig.fromMap({
        'default': 'default',
        'connections': {
          'default': {
            'type': 'postgresql',
            'host': host,
            'port': int.parse(port),
            'database': name,
            'username': user,
            'password': pass,
            'ssl': false,
          },
        },
      }));
      // One table per sealed table, with just its sealed column(s).
      final tables = <String, Set<String>>{};
      for (final (table, column, _) in SecretBox.sealedColumns) {
        (tables[table] ??= {}).add(column);
      }
      for (final MapEntry(key: table, value: columns) in tables.entries) {
        await db.context().execute('DROP TABLE IF EXISTS $table');
        await db.context().execute('CREATE TABLE $table '
            '(id serial PRIMARY KEY, ${columns.map((c) => '$c text').join(', ')})');
      }
      tmp = Directory.systemTemp.createTempSync('secretbox_db_');
    });

    tearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    Future<List<Object?>> column(String table, String col) async => [
          for (final r in await db
              .context()
              .execute('SELECT $col FROM $table ORDER BY id'))
            r[0],
        ];

    test('first start creates a private key and seals plaintext rows',
        () async {
      await db.context().execute("INSERT INTO env_vars (value) "
          "VALUES ('DATABASE_URL-secret'), (NULL), ('')");
      await db.context().execute(
          "INSERT INTO user_totps (secret) VALUES ('JBSWY3DPEHPK3PXP')");
      await db.context().execute(
          'INSERT INTO deployments (deploy_config) VALUES (\$1)',
          parameters: ['{"applyUnit":["--env","K=v"]}']);

      await db.context().execute("INSERT INTO postgres_databases (password) "
          "VALUES ('db-pass'), ('')");
      await db.context().execute('INSERT INTO mongo_instances '
          "(root_password, monitor_password) VALUES ('root-pass', NULL)");
      await db.context().execute(
          "INSERT INTO smtp_configs (smtp_password) VALUES ('smtp-pass')");

      final path = '${tmp.path}/secret.key';
      final box = await SecretBox.load(database: db, path: path);
      expect(File(path).statSync().modeString(), 'rw-------');

      // Empty strings stay empty: '' rows in env_vars and postgres_databases.
      expect(await box.sealPlaintextRows(db), 6);
      expect(await box.sealPlaintextRows(db), 0, reason: 'idempotent');

      final envs = await column('env_vars', 'value');
      expect(envs[1], isNull);
      expect(envs[2], '');
      expect(box.open(envs[0]! as String, SecretBox.envVarValue),
          'DATABASE_URL-secret');
      final dbs = await column('postgres_databases', 'password');
      expect(box.open(dbs[0]! as String, SecretBox.pgDatabasePassword),
          'db-pass');
      expect(dbs[1], '');
      expect(
          box.open((await column('mongo_instances', 'root_password')).single!
              as String, SecretBox.mongoRootPassword),
          'root-pass');
      expect(
          box.open((await column('smtp_configs', 'smtp_password')).single!
              as String, SecretBox.smtpPassword),
          'smtp-pass');
      expect(
          box.open((await column('user_totps', 'secret')).single! as String,
              SecretBox.totpSecret),
          'JBSWY3DPEHPK3PXP');
      expect(
          box.open(
              (await column('deployments', 'deploy_config')).single! as String,
              SecretBox.deployConfig),
          '{"applyUnit":["--env","K=v"]}');

      // A restart reuses the same key.
      final again = await SecretBox.load(database: db, path: path);
      expect(again.open(envs[0]! as String, SecretBox.envVarValue),
          'DATABASE_URL-secret');
    });

    test('a lost key is not silently replaced', () async {
      // Sealed values in any table count, here the last one checked.
      await db.context().execute(
          'INSERT INTO smtp_configs (smtp_password) VALUES (\$1)',
          parameters: [box.seal('v', SecretBox.smtpPassword)]);
      final path = '${tmp.path}/secret.key';
      await expectLater(SecretBox.load(database: db, path: path),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('Restore the key'))));
      expect(File(path).existsSync(), isFalse);
    });
  }, skip: _pg == null ? 'set GISILA_TEST_PG=host:port:db:user:pass' : false);
}
