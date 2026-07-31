import 'dart:async';

import 'package:gisila_panel/config.dart';
import 'package:redis/redis.dart' show Command;

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

    connectRedis().then((cmd) {
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

  /// Run [op] against the current connection. If the underlying socket has
  /// died (e.g. Redis was restarted or dropped the TCP connection), the
  /// cached [Command] keeps failing forever since `connection()` happily
  /// hands it back out — so on any error here we drop it and retry once
  /// against a freshly established connection instead of surfacing a 500 for
  /// every request until the process is restarted.
  Future<T> _run<T>(Future<T> Function(Command cmd) op) async {
    final cmd = await connection();
    try {
      return await op(cmd);
    } catch (_) {
      if (identical(_command, cmd)) _command = null;
      final fresh = await connection();
      return op(fresh);
    }
  }

  /// Enqueue a JSON payload onto a Redis list (the work queue). Workers pop
  /// from the head with `BLPOP`.
  Future<void> rpush(String queue, String payload) =>
      _run((cmd) => cmd.send_object(['RPUSH', queue, payload]));

  /// Publish a payload on a Redis pubsub channel (e.g. build log lines).
  Future<void> publish(String channel, String payload) =>
      _run((cmd) => cmd.send_object(['PUBLISH', channel, payload]));

  Future<int> incr(String key) => _run((cmd) async {
        final result = await cmd.send_object(['INCR', key]);
        return result is int ? result : int.parse(result.toString());
      });

  /// Trim a list to the inclusive range [start, stop] (capped log buffers).
  Future<void> ltrim(String key, int start, int stop) =>
      _run((cmd) => cmd.send_object(['LTRIM', key, '$start', '$stop']));

  /// Delete a key (used to clear a stale log history buffer).
  Future<void> del(String key) => _run((cmd) => cmd.send_object(['DEL', key]));

  /// Set an expiry (seconds) on a key so log buffers don't linger forever.
  Future<void> expire(String key, int seconds) =>
      _run((cmd) => cmd.send_object(['EXPIRE', key, '$seconds']));

  /// Set [key] to [value] with a [seconds] TTL (used for short-lived metrics
  /// snapshots written by the worker and read by the API).
  Future<void> setEx(String key, int seconds, String value) =>
      _run((cmd) => cmd.send_object(['SET', key, value, 'EX', '$seconds']));

  /// Get the string value of [key], or null when it does not exist.
  Future<String?> get(String key) => _run((cmd) async {
        final result = await cmd.send_object(['GET', key]);
        return result?.toString();
      });
}
