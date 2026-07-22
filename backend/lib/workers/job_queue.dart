import 'dart:async';
import 'dart:convert';

import 'package:gisila_panel/config.dart';
import 'package:redis/redis.dart';

/// A minimal blocking-pop Redis job consumer.
///
/// Each [JobQueue] connects to Redis once, then sits in a `BLPOP` loop
/// across the registered queues. Handlers are async and run in series
/// per-worker (matching the simple "one task at a time" semantics of
/// `celery -c 1`, but trivial to scale by launching more worker processes).
///
/// Payloads are JSON-encoded; a malformed payload triggers a logged
/// `skipped` event and is discarded.
class JobQueue {
  JobQueue();

  final Map<String, Future<void> Function(Map<String, Object?>)> _handlers = {};
  late Command _cmd;

  void on(String queue,
      Future<void> Function(Map<String, Object?> payload) handler) {
    _handlers[queue] = handler;
  }

  Future<void> run() async {
    final host = env.getOrElse('REDIS_HOST', () => 'localhost');
    final port = int.parse(env.getOrElse('REDIS_PORT', () => '6380'));
    _cmd = await RedisConnection().connect(host, port);
    logger.i('worker: connected to redis $host:$port');
    logger.i('worker: queues = ${_handlers.keys.join(', ')}');

    while (true) {
      try {
        final args = <Object>['BLPOP', ..._handlers.keys, 5];
        final result = await _cmd.send_object(args);
        if (result is List && result.length == 2) {
          final queue = result[0].toString();
          final raw = result[1].toString();
          await _dispatch(queue, raw);
        }
      } catch (e, st) {
        // The socket underlying `_cmd` may have died (Redis restarted, network
        // blip, …). Reconnect before retrying — otherwise every future BLPOP
        // hits the same dead connection and the worker never processes another
        // job again without a full process restart.
        logger.e('worker: redis error — reconnecting', error: e, stackTrace: st);
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          _cmd = await RedisConnection().connect(host, port);
          logger.i('worker: reconnected to redis $host:$port');
        } catch (reconnectErr) {
          logger.e('worker: redis reconnect failed', error: reconnectErr);
        }
      }
    }
  }

  Future<void> _dispatch(String queue, String raw) async {
    final handler = _handlers[queue];
    if (handler == null) {
      logger.w('worker: no handler for queue $queue (skipping)');
      return;
    }
    final stopwatch = Stopwatch()..start();
    try {
      final payload = jsonDecode(raw) as Map<String, Object?>;
      logger.i('worker: ${queue.padRight(28)} ← ${_summarise(payload)}');
      await handler(payload);
      logger.i(
          'worker: ${queue.padRight(28)} ✓ ${stopwatch.elapsedMilliseconds} ms');
    } catch (e, st) {
      logger.e('worker: ${queue.padRight(28)} ✗', error: e, stackTrace: st);
    }
  }

  String _summarise(Map<String, Object?> p) {
    final keys = p.keys.take(4).map((k) => '$k=${p[k]}').join(' ');
    return keys.length > 100 ? '${keys.substring(0, 100)}…' : keys;
  }
}
