import 'dart:math' as math;

import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// A token bucket: [capacity] requests at once, refilled at [perSecond].
final class RateLimitPolicy {
  const RateLimitPolicy(
    this.name, {
    required this.capacity,
    required this.perSecond,
  });

  /// `capacity` requests per `window`, refilled evenly.
  RateLimitPolicy.per(this.name, this.capacity, Duration window)
    : perSecond = capacity / (window.inMilliseconds / 1000);

  final String name;
  final int capacity;
  final double perSecond;
}

final class RateDecision {
  const RateDecision.allowed() : allowed = true, retryAfter = Duration.zero;

  const RateDecision.denied(this.retryAfter) : allowed = false;

  final bool allowed;
  final Duration retryAfter;
}

/// Shared rate limiting (ADR-025): every node sees the same buckets.
abstract interface class RateLimiter {
  /// Takes one token for [key] under [policy].
  Future<RateDecision> hit(RateLimitPolicy policy, String key);

  /// Drops buckets that have been full long enough to be meaningless.
  Future<int> sweep();
}

final class InMemoryRateLimiter implements RateLimiter {
  InMemoryRateLimiter({this._clock = const SystemClock()});

  final Clock _clock;
  final Map<String, (double, DateTime)> _buckets = {};

  @override
  Future<RateDecision> hit(RateLimitPolicy policy, String key) async {
    final id = '${policy.name}:$key';
    final now = _clock.now();
    final (tokens, at) = _buckets[id] ?? (policy.capacity.toDouble(), now);
    final elapsed = now.difference(at).inMicroseconds / 1e6;
    final refilled = math.min(
      policy.capacity.toDouble(),
      tokens + elapsed * policy.perSecond,
    );
    if (refilled >= 1) {
      _buckets[id] = (refilled - 1, now);
      return const RateDecision.allowed();
    }
    _buckets[id] = (refilled, now);
    return RateDecision.denied(_wait(refilled, policy));
  }

  @override
  Future<int> sweep() async {
    final before = _buckets.length;
    _buckets.removeWhere(
      (_, v) => _clock.now().difference(v.$2) > const Duration(hours: 1),
    );
    return before - _buckets.length;
  }
}

Duration _wait(double tokens, RateLimitPolicy policy) => Duration(
  milliseconds: (((1 - tokens) / policy.perSecond) * 1000).ceil().clamp(
    1,
    86400000,
  ),
);

/// Token buckets in an UNLOGGED Postgres table, updated in one statement so
/// concurrent requests on different nodes cannot both take the last token.
final class PostgresRateLimiter implements RateLimiter {
  PostgresRateLimiter(this._db, String platformSchema)
    : _table = '$platformSchema.rate_buckets';

  final Db _db;
  final String _table;

  @override
  Future<RateDecision> hit(RateLimitPolicy policy, String key) async {
    // Every expression reads the bucket row that ON CONFLICT has locked,
    // so concurrent hits from any node serialize on it.
    const refilled =
        'LEAST(@cap:float8, b.tokens + EXTRACT(EPOCH FROM (now() - b.updated_at)) * @rate:float8)';
    final row = await _db.queryOne(
      '''
      INSERT INTO $_table AS b (key, tokens, updated_at, allowed)
      VALUES (@k:text, @cap:float8 - 1, now(), true)
      ON CONFLICT (key) DO UPDATE SET
        tokens = CASE WHEN $refilled >= 1 THEN $refilled - 1 ELSE $refilled END,
        allowed = $refilled >= 1,
        updated_at = now()
      RETURNING tokens, allowed
      ''',
      {
        'k': '${policy.name}:$key',
        'cap': policy.capacity.toDouble(),
        'rate': policy.perSecond,
      },
    );
    if (row!.boolean('allowed')) return const RateDecision.allowed();
    return RateDecision.denied(_wait(row.float('tokens'), policy));
  }

  @override
  Future<int> sweep() => _db.execute(
    "DELETE FROM $_table WHERE updated_at < now() - interval '1 hour'",
  );
}
