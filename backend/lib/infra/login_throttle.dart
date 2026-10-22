import 'package:gisila/gisila.dart' show TooManyRequests;
import 'package:gisila_panel/config.dart';
import 'package:gisila_panel/infra/redis_client.dart';

/// Failed-login counters in Redis, so every API isolate (one per CPU) shares
/// them — the framework's per-route rate limit is counted per isolate.
///
/// A failure is counted against the account from this address, the account
/// from anywhere, and the address across accounts. Each counter blocks once it
/// reaches its limit, for the rest of its window. The per-account limit is
/// deliberately looser than the per-address one, so someone hammering an
/// account from one place locks out only that place long before the real
/// owner is affected.
class LoginThrottle {
  LoginThrottle({RedisClient? redis}) : _redis = redis ?? RedisClient.instance;

  final RedisClient _redis;

  static const window = Duration(minutes: 15);
  static const _prefix = 'gisila:auth:fail';

  /// Limits per window for each counter kind.
  static const _limits = {'acct-ip': 10, 'acct': 50, 'ip': 100};

  List<(String key, int limit)> _keys(String account, String? ip) {
    final acct = account.trim().toLowerCase();
    return [
      if (ip != null) ('$_prefix:acct-ip:$acct|$ip', _limits['acct-ip']!),
      ('$_prefix:acct:$acct', _limits['acct']!),
      if (ip != null) ('$_prefix:ip:$ip', _limits['ip']!),
    ];
  }

  /// Throw [TooManyRequests] if any counter for [account] / [ip] is at its
  /// limit. Call before checking the credential, so a blocked caller can't
  /// keep guessing (or keep the CPU busy hashing).
  Future<void> check(String account, String? ip) async {
    for (final (key, limit) in _keys(account, ip)) {
      final raw = await _safe<String?>(() => _redis.get(key));
      final count = int.tryParse(raw ?? '') ?? 0;
      if (count >= limit) {
        throw TooManyRequests(
            'Too many failed attempts. Try again in ${window.inMinutes} minutes.');
      }
    }
  }

  Future<void> recordFailure(String account, String? ip) async {
    for (final (key, _) in _keys(account, ip)) {
      await _safe(() async {
        final count = await _redis.incr(key);
        if (count == 1) await _redis.expire(key, window.inSeconds);
      });
    }
  }

  /// Forget failures for [account] from [ip] after it signs in. The wider
  /// counters keep running: a success from one place says nothing about
  /// guessing from another.
  Future<void> recordSuccess(String account, String? ip) async {
    final keys = _keys(account, ip);
    if (ip != null) await _safe(() => _redis.del(keys.first.$1));
  }

  // Redis is part of every install, but if it is briefly unreachable, signing
  // in should still work: fail open and say so in the log.
  Future<T?> _safe<T>(Future<T> Function() op) async {
    try {
      return await op();
    } catch (e) {
      logger.w('Login throttle unavailable (Redis): $e');
      return null;
    }
  }
}
