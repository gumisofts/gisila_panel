import 'dart:async';
import 'dart:convert';

import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/workers/job_signing.dart';
import 'package:redis/redis.dart' show Command;

/// The worker's Redis job consumer.
///
/// Producers sign each job and push it onto the head of its list
/// (`RedisClient.enqueueJob`). The worker moves a job from the tail into
/// `<queue>:processing` (`RPOPLPUSH`, available in every Redis version)
/// before running it and removes it from there once the handler returns, so
/// a crash or a dead connection no longer loses it: on startup, jobs left in
/// a processing list go back onto their queue. Queues registered with
/// `atMostOnce` (commands a user ran, which must not run twice) are dropped
/// instead. Jobs whose signature doesn't verify are logged and dropped.
///
/// Handlers run one at a time, in registration order of the queues.
class JobQueue {
  JobQueue();

  final Map<String, Future<void> Function(Map<String, Object?>)> _handlers = {};
  final Set<String> _atMostOnce = {};
  late Command _cmd;
  bool _running = false;

  /// How long the loop sleeps when every queue is empty.
  static const idlePoll = Duration(milliseconds: 250);

  void on(
      String queue, Future<void> Function(Map<String, Object?> payload) handler,
      {bool atMostOnce = false}) {
    _handlers[queue] = handler;
    if (atMostOnce) _atMostOnce.add(queue);
  }

  static String processingKey(String queue) => '$queue:processing';

  /// Ends [run] after the job in hand, if any.
  void stop() => _running = false;

  Future<void> run() async {
    _cmd = await connectRedis();
    logger.i('worker: connected to redis $redisHost:$redisPort');
    logger.i('worker: queues = ${_handlers.keys.join(', ')}');
    await _recoverInFlight();

    _running = true;
    while (_running) {
      try {
        final job = await _take().timeout(const Duration(seconds: 8));
        if (job == null) {
          await Future<void>.delayed(idlePoll);
          continue;
        }
        await _dispatch(job.queue, job.raw);
        await _cmd
            .send_object(['LREM', processingKey(job.queue), '-1', job.raw]);
      } on TimeoutException {
        // A dead socket makes send_object hang forever; reconnect.
        logger.w('worker: redis hung — reconnecting');
        await _reconnect();
      } catch (e, st) {
        // The socket underlying `_cmd` may have died (Redis restarted, network
        // blip, …). Reconnect before retrying — otherwise every later command
        // hits the same dead connection.
        logger.e('worker: redis error — reconnecting',
            error: e, stackTrace: st);
        await Future<void>.delayed(const Duration(seconds: 2));
        await _reconnect();
      }
    }
  }

  /// The oldest job of the first non-empty queue, moved to its processing
  /// list; null when every queue is empty.
  Future<({String queue, String raw})?> _take() async {
    for (final queue in _handlers.keys) {
      final raw =
          await _cmd.send_object(['RPOPLPUSH', queue, processingKey(queue)]);
      if (raw != null) return (queue: queue, raw: raw.toString());
    }
    return null;
  }

  /// Puts back jobs a previous run took but never finished.
  Future<void> _recoverInFlight() async {
    for (final queue in _handlers.keys) {
      final processing = processingKey(queue);
      if (_atMostOnce.contains(queue)) {
        final dropped = await _cmd.send_object(['LLEN', processing]);
        await _cmd.send_object(['DEL', processing]);
        if ('$dropped' != '0') {
          logger.w('worker: dropped $dropped unfinished $queue job(s) '
              '(not re-run after a restart)');
        }
        continue;
      }
      var n = 0;
      while (await _cmd.send_object(['RPOPLPUSH', processing, queue]) != null) {
        n++;
      }
      if (n > 0) logger.i('worker: re-queued $n unfinished $queue job(s)');
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
    final payloadJson = JobSigner.unwrap(raw);
    if (payloadJson == null) {
      logger.e('worker: $queue dropped a job without a valid signature');
      return;
    }
    final stopwatch = Stopwatch()..start();
    try {
      final decoded = jsonDecode(payloadJson);
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
