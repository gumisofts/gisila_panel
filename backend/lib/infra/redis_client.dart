import 'dart:async';

import 'package:gisila_panel/config.dart';
import 'package:redis/redis.dart';

/// A tiny lazy singleton wrapper around the `redis` package. The connection is
/// established on first use and reconnected automatically on failure.
class RedisClient {
  RedisClient._();

  static final RedisClient instance = RedisClient._();

  Command? _command;
  Completer<Command>? _pending;

  Future<Command> connection() {
    if (_command != null) return Future.value(_command);
    if (_pending != null) return _pending!.future;

    _pending = Completer<Command>();
    final host = env.getOrElse('REDIS_HOST', () => 'localhost');
    final port = int.parse(env.getOrElse('REDIS_PORT', () => '6380'));

    RedisConnection().connect(host, port).then((cmd) {
      _command = cmd;
      _pending!.complete(cmd);
      _pending = null;
    }).catchError((Object err, StackTrace stack) {
      final p = _pending;
      _pending = null;
      p?.completeError(err, stack);
    });

    return _pending!.future;
  }

  /// Enqueue a JSON payload onto a Redis list (the work queue). Workers pop
  /// from the head with `BLPOP`.
  Future<void> rpush(String queue, String payload) async {
    final cmd = await connection();
    await cmd.send_object(['RPUSH', queue, payload]);
  }

  /// Publish a payload on a Redis pubsub channel (e.g. build log lines).
  Future<void> publish(String channel, String payload) async {
    final cmd = await connection();
    await cmd.send_object(['PUBLISH', channel, payload]);
  }

  Future<int> incr(String key) async {
    final cmd = await connection();
    final result = await cmd.send_object(['INCR', key]);
    return result is int ? result : int.parse(result.toString());
  }

  /// Trim a list to the inclusive range [start, stop] (capped log buffers).
  Future<void> ltrim(String key, int start, int stop) async {
    final cmd = await connection();
    await cmd.send_object(['LTRIM', key, '$start', '$stop']);
  }

  /// Delete a key (used to clear a stale log history buffer).
  Future<void> del(String key) async {
    final cmd = await connection();
    await cmd.send_object(['DEL', key]);
  }

  /// Set an expiry (seconds) on a key so log buffers don't linger forever.
  Future<void> expire(String key, int seconds) async {
    final cmd = await connection();
    await cmd.send_object(['EXPIRE', key, '$seconds']);
  }

  /// Set [key] to [value] with a [seconds] TTL (used for short-lived metrics
  /// snapshots written by the worker and read by the API).
  Future<void> setEx(String key, int seconds, String value) async {
    final cmd = await connection();
    await cmd.send_object(['SET', key, value, 'EX', '$seconds']);
  }

  /// Get the string value of [key], or null when it does not exist.
  Future<String?> get(String key) async {
    final cmd = await connection();
    final result = await cmd.send_object(['GET', key]);
    return result?.toString();
  }
}
