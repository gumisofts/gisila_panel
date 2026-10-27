/// Signed jobs and reliable delivery for the worker's queue (PNL-14,
/// PNL-11). The Redis cases need a throwaway Redis: run with
/// `GISILA_TEST_PANEL_REDIS=1 REDIS_HOST=127.0.0.1 REDIS_PORT=<port>
/// REDIS_PASSWORD=<pw> JWT_SECRET=<32+ chars> dart test test/job_queue_test.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';
import 'package:gisila_panel/workers/job_queue.dart';
import 'package:gisila_panel/workers/job_signing.dart';
import 'package:test/test.dart';

void main() {
  group('JobSigner', () {
    test('a signed payload unwraps to itself', () {
      final raw = JobSigner.wrap('{"appId":7}');
      expect(JobSigner.unwrap(raw), '{"appId":7}');
    });

    test('a tampered, forged or unsigned job is refused', () {
      final env = jsonDecode(JobSigner.wrap('{"appId":7}')) as Map;
      expect(JobSigner.unwrap(jsonEncode({'p': '{"appId":8}', 's': env['s']})),
          isNull);
      expect(JobSigner.unwrap(jsonEncode({'p': '{"appId":7}', 's': 'ab'})),
          isNull);
      expect(JobSigner.unwrap('{"appId":7}'), isNull);
      expect(JobSigner.unwrap('not json'), isNull);
    });
  });

  group('JobQueue on Redis',
      skip: Platform.environment['GISILA_TEST_PANEL_REDIS'] == '1'
          ? false
          : 'set GISILA_TEST_PANEL_REDIS=1 and REDIS_* (see top of file)', () {
    final tag = DateTime.now().microsecondsSinceEpoch;
    final normal = 'gisila:queue:test_normal_$tag';
    final once = 'gisila:queue:test_once_$tag';

    tearDownAll(() async {
      final c = await connectRedis();
      for (final k in [
        normal,
        once,
        JobQueue.processingKey(normal),
        JobQueue.processingKey(once)
      ]) {
        await c.send_object(['DEL', k]);
      }
    });

    test('runs signed jobs, drops forged ones, recovers unfinished ones',
        () async {
      final c = await connectRedis();
      // Left behind by a "crashed" worker:
      await c.send_object([
        'LPUSH',
        JobQueue.processingKey(normal),
        JobSigner.wrap('{"n":"recovered"}')
      ]);
      await c.send_object([
        'LPUSH',
        JobQueue.processingKey(once),
        JobSigner.wrap('{"n":"must not rerun"}')
      ]);

      final seen = <String>[];
      final queue = JobQueue()
        ..on(normal, (p) async => seen.add(p['n'] as String))
        ..on(once, (p) async => seen.add(p['n'] as String), atMostOnce: true);
      unawaited(queue.run());

      await RedisClient.instance.enqueueJob(normal, '{"n":"first"}');
      await RedisClient.instance.enqueueJob(normal, '{"n":"second"}');
      await c.send_object([
        'LPUSH',
        normal,
        jsonEncode({'p': '{"n":"forged"}', 's': '00' * 32})
      ]);
      await RedisClient.instance.enqueueJob(normal, '{"n":"third"}');

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (seen.length < 4 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      queue.stop();

      expect(seen, ['recovered', 'first', 'second', 'third']);
      for (final k in [
        normal,
        JobQueue.processingKey(normal),
        JobQueue.processingKey(once)
      ]) {
        expect(await c.send_object(['LLEN', k]), 0, reason: k);
      }
    });
  });
}
