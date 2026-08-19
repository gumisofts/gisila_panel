import 'dart:async';
import 'dart:convert';

import 'package:gisila_panel/config.dart';
import 'package:redis/redis.dart' show Command;

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
    _cmd = await connectRedis();
    logger.i('worker: connected to redis $redisHost:$redisPort');
    logger.i('worker: queues = ${_handlers.keys.join(', ')}');

    while (true) {
      try {
        final args = <Object>['BLPOP', ..._handlers.keys, 5];
        // Redis times the BLPOP out in 5s. If the TCP socket is already dead
        // (idle drop during a long handler, Redis restart), send_object hangs
        // forever and every later deploy sits in `queued` until something
        // else happens to reconnect us. Fail the wait slightly after Redis
        // would have replied, then open a new connection.
        final result = await _cmd
            .send_object(args)
            .timeout(const Duration(seconds: 8));
        if (result is List && result.length == 2) {
          final queue = result[0].toString();
          final raw = result[1].toString();
          await _dispatch(queue, raw);
        }
      } on TimeoutException {
        logger.w('worker: BLPOP hung — reconnecting');
        await _reconnect();
      } catch (e, st) {
        // The socket underlying `_cmd` may have died (Redis restarted, network
        // blip, …). Reconnect before retrying — otherwise every future BLPOP
        // hits the same dead connection and the worker never processes another
        // job again without a full process restart.
        logger.e('worker: redis error — reconnecting', error: e, stackTrace: st);
        await Future<void>.delayed(const Duration(seconds: 2));
        await _reconnect();
      }
    }
  }

  Future<void> _reconnect() async {
    try {
      _cmd = await connectRedis();
      logger.i('worker: reconnected to redis $redisHost:$redisPort');
    } catch (reconnectErr) {
      logger.e('worker: redis reconnect failed', error: reconnectErr);
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
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        logger.w('worker: $queue skipped (payload is not a JSON object)');
        return;
      }
      final payload = Map<String, Object?>.from(decoded);
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
