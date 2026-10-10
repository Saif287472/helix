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
  /// Takes [cost] tokens (default one) for [key] under [policy]. A cost
  /// above the policy's capacity is charged as the full capacity, so a
  /// large request is slow, never impossible.
  Future<RateDecision> hit(RateLimitPolicy policy, String key, {int cost = 1});

  /// Drops buckets that are full again (one policy window after their last
  /// hit): a missing bucket starts full, so dropping one earlier would reset
  /// it.
  Future<int> sweep();
}

final class InMemoryRateLimiter implements RateLimiter {
  InMemoryRateLimiter({this._clock = const SystemClock()});

  final Clock _clock;
  final Map<String, (double, DateTime)> _buckets = {};
  final Map<String, DateTime> _fullAt = {};

  @override
  Future<RateDecision> hit(
    RateLimitPolicy policy,
    String key, {
    int cost = 1,
  }) async {
    final take = _charge(policy, cost);
    final id = '${policy.name}:$key';
    final now = _clock.now();
    final (tokens, at) = _buckets[id] ?? (policy.capacity.toDouble(), now);
    final elapsed = now.difference(at).inMicroseconds / 1e6;
    final refilled = math.min(
      policy.capacity.toDouble(),
      tokens + elapsed * policy.perSecond,
    );
    _fullAt[id] = now.add(_window(policy));
    if (refilled >= take) {
      _buckets[id] = (refilled - take, now);
      return const RateDecision.allowed();
    }
    _buckets[id] = (refilled, now);
    return RateDecision.denied(_wait(refilled, policy, take));
  }

  @override
  Future<int> sweep() async {
    final now = _clock.now();
    final full = [
      for (final MapEntry(:key, :value) in _fullAt.entries)
        if (!value.isAfter(now)) key,
    ];
    for (final id in full) {
      _buckets.remove(id);
      _fullAt.remove(id);
    }
    return full.length;
  }
}

/// How long an empty bucket of [policy] takes to fill: after this long
/// without a hit, any bucket of it is full.
Duration _window(RateLimitPolicy policy) =>
    Duration(milliseconds: (policy.capacity / policy.perSecond * 1000).ceil());

/// The tokens a hit of [cost] takes: at least one, at most the capacity.
int _charge(RateLimitPolicy policy, int cost) =>
    cost.clamp(1, math.max(1, policy.capacity));

Duration _wait(double tokens, RateLimitPolicy policy, int take) => Duration(
  milliseconds: (((take - tokens) / policy.perSecond) * 1000).ceil().clamp(
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
  Future<RateDecision> hit(
    RateLimitPolicy policy,
    String key, {
    int cost = 1,
  }) async {
    final take = _charge(policy, cost);
    // Every expression reads the bucket row that ON CONFLICT has locked,
    // so concurrent hits from any node serialize on it. A new bucket starts
    // full, and [take] never exceeds the capacity.
    const refilled =
        'LEAST(@cap:float8, b.tokens + EXTRACT(EPOCH FROM (now() - b.updated_at)) * @rate:float8)';
    // `full_at`: one window from now, by when even an empty bucket is full
    // again; the sweep drops a bucket only then.
    final row = await _db.queryOne(
      '''
      INSERT INTO $_table AS b (key, tokens, updated_at, allowed, full_at)
      VALUES (@k:text, @cap:float8 - @take:float8, now(), true,
              now() + make_interval(secs => @window:float8))
      ON CONFLICT (key) DO UPDATE SET
        tokens = CASE WHEN $refilled >= @take:float8 THEN $refilled - @take:float8 ELSE $refilled END,
        allowed = $refilled >= @take:float8,
        updated_at = now(),
        full_at = now() + make_interval(secs => @window:float8)
      RETURNING tokens, allowed
      ''',
      {
        'k': '${policy.name}:$key',
        'cap': policy.capacity.toDouble(),
        'rate': policy.perSecond,
        'take': take.toDouble(),
        'window': _window(policy).inMilliseconds / 1000,
      },
    );
    if (row!.boolean('allowed')) return const RateDecision.allowed();
    return RateDecision.denied(_wait(row.float('tokens'), policy, take));
  }

  @override
  Future<int> sweep() =>
      _db.execute('DELETE FROM $_table WHERE full_at <= now()');
}
