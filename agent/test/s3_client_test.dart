import 'dart:convert';
import 'dart:io';

import 'package:gisila_agent/storage/s3_client.dart';
import 'package:test/test.dart';

/// Needs an S3 endpoint and a key allowed to create buckets:
/// `GISILA_TEST_S3=http://127.0.0.1:8793|GK…|secret|garage`.
final _cfg = Platform.environment['GISILA_TEST_S3']?.split('|');

void main() {
  group('live', () {
    late S3Client c;
    setUp(() => c = S3Client(
        endpoint: _cfg![0],
        accessKey: _cfg![1],
        secretKey: _cfg![2],
        region: _cfg![3]));
    tearDown(() => c.close());

    test('create, fill, empty and delete a bucket', () async {
      const bucket = 'gisila-s3client-test';
      await c.createBucket(bucket);
      await c.createBucket(bucket); // idempotent
      for (final key in ['a.txt', 'dir/b c.txt', 'x&y<z>.txt']) {
        final r = await c.send('PUT', '/$bucket/$key',
            body: utf8.encode('hello $key'));
        r.check('put $key');
      }
      final got = await c.send('GET', '/$bucket/dir/b c.txt');
      expect(got.body, 'hello dir/b c.txt');
      expect(await c.emptyBucket(bucket), 3);
      await c.deleteBucket(bucket);
      final gone = await c.send('GET', '/$bucket', query: {'list-type': '2'});
      expect(gone.status, 404);
      await c.deleteBucket(bucket); // missing is fine
    });

    test('a bad secret is reported, not ignored', () async {
      final bad = S3Client(
          endpoint: _cfg![0],
          accessKey: _cfg![1],
          secretKey: 'wrong',
          region: _cfg![3]);
      addTearDown(bad.close);
      await expectLater(bad.createBucket('gisila-s3client-bad'),
          throwsA(isA<S3Exception>()));
    });
  }, skip: _cfg == null ? 'set GISILA_TEST_S3' : false);
}
