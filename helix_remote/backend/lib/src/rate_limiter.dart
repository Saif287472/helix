import 'dart:async';
import 'package:sqlite3/sqlite3.dart';

class TokenBucket {
  final double maxTokens;
  final double refillRatePerMs;
  double tokens;
  int lastRefill;

  TokenBucket({required this.maxTokens, required double refillRatePerSecond})
    : refillRatePerMs = refillRatePerSecond / 1000.0,
      tokens = maxTokens,
      lastRefill = DateTime.now().millisecondsSinceEpoch;

  bool consume(double amount) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - lastRefill;
    if (elapsed > 0) {
      tokens = (tokens + elapsed * refillRatePerMs).clamp(0.0, maxTokens);
      lastRefill = now;
    }
    if (tokens >= amount) {
      tokens -= amount;
      return true;
    }
    return false;
  }

  /// Whether this bucket would already be fully refilled if [nowMs] elapsed
  /// since [lastRefill] were applied, without mutating any state. `tokens`
  /// itself is only updated lazily inside [consume], so a bucket idle since
  /// before it last emptied can sit well below `maxTokens` in memory even
  /// though it has long since earned a full refill — this computes the
  /// projected value instead of comparing the (possibly stale) field.
  bool isFullyRefilledAt(int nowMs) {
    final elapsed = nowMs - lastRefill;
    final projected = elapsed > 0 ? tokens + elapsed * refillRatePerMs : tokens;
    return projected >= maxTokens;
  }
}

abstract interface class RateLimitStore {
  TokenBucket bucketFor(
    String key, {
    required double maxTokens,
    required double refillRatePerSecond,
  });

  void reset(String key);
  int get trackedKeys;

  /// Atomically spends a token. Implementations backed by a shared database
  /// must make the read/refill/write one transaction, otherwise two server
  /// processes can both admit the same request.
  bool consume(
    String key, {
    required double maxTokens,
    required double refillRatePerSecond,
  });

  /// Releases any background resources (e.g. a cleanup timer). Safe to call
  /// more than once.
  void dispose();
}

class InMemoryRateLimitStore implements RateLimitStore {
  // Unbounded growth guard: a client (or spoofed IP) hitting a
  // rate-limited endpoint once creates a bucket that otherwise lives
  // forever. Periodically evicting buckets that have sat idle long enough
  // to be fully refilled keeps the map bounded to actually-active keys.
  InMemoryRateLimitStore({
    Duration cleanupInterval = const Duration(minutes: 5),
  }) {
    if (cleanupInterval > Duration.zero) {
      _cleanupTimer = Timer.periodic(
        cleanupInterval,
        (_) => _evictIdleBuckets(),
      );
    }
  }

  final Map<String, TokenBucket> _buckets = {};
  Timer? _cleanupTimer;

  void _evictIdleBuckets() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _buckets.removeWhere((_, bucket) => bucket.isFullyRefilledAt(now));
  }

  @override
  TokenBucket bucketFor(
    String key, {
    required double maxTokens,
    required double refillRatePerSecond,
  }) {
    return _buckets.putIfAbsent(
      key,
      () => TokenBucket(
        maxTokens: maxTokens,
        refillRatePerSecond: refillRatePerSecond,
      ),
    );
  }

  @override
  void reset(String key) {
    _buckets.remove(key);
  }

  @override
  bool consume(
    String key, {
    required double maxTokens,
    required double refillRatePerSecond,
  }) => bucketFor(
    key,
    maxTokens: maxTokens,
    refillRatePerSecond: refillRatePerSecond,
  ).consume(1.0);

  @override
  int get trackedKeys => _buckets.length;

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }
}

/// SQLite-backed buckets survive process restarts and are shared by every
/// Helix backend process pointed at the same database. SQLite is deliberately
/// used as the production baseline until the documented Postgres migration;
/// `BEGIN IMMEDIATE` serializes a bucket update across processes.
class SqliteRateLimitStore implements RateLimitStore {
  SqliteRateLimitStore(this._db) {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS rate_limit_buckets (
        bucket_key TEXT PRIMARY KEY,
        tokens REAL NOT NULL,
        last_refill_ms INTEGER NOT NULL
      );
    ''');
  }

  final Database _db;

  @override
  TokenBucket bucketFor(
    String key, {
    required double maxTokens,
    required double refillRatePerSecond,
  }) {
    // Kept for source compatibility with the original store API. Callers
    // should use RateLimiter.isAllowed, which invokes atomic [consume].
    final result = _db.select(
      'SELECT tokens, last_refill_ms FROM rate_limit_buckets WHERE bucket_key = ?',
      [key],
    );
    final bucket = TokenBucket(
      maxTokens: maxTokens,
      refillRatePerSecond: refillRatePerSecond,
    );
    if (result.isNotEmpty) {
      bucket.tokens = (result.first['tokens'] as num).toDouble();
      bucket.lastRefill = result.first['last_refill_ms'] as int;
    }
    return bucket;
  }

  @override
  bool consume(
    String key, {
    required double maxTokens,
    required double refillRatePerSecond,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('BEGIN IMMEDIATE');
    try {
      final rows = _db.select(
        'SELECT tokens, last_refill_ms FROM rate_limit_buckets WHERE bucket_key = ?',
        [key],
      );
      var tokens = maxTokens;
      var lastRefill = now;
      if (rows.isNotEmpty) {
        tokens = (rows.first['tokens'] as num).toDouble();
        lastRefill = rows.first['last_refill_ms'] as int;
        final elapsed = now - lastRefill;
        if (elapsed > 0) {
          tokens = (tokens + elapsed * (refillRatePerSecond / 1000)).clamp(
            0.0,
            maxTokens,
          );
          lastRefill = now;
        }
      }
      final allowed = tokens >= 1;
      if (allowed) tokens -= 1;
      _db.execute(
        '''INSERT INTO rate_limit_buckets(bucket_key, tokens, last_refill_ms)
           VALUES (?, ?, ?)
           ON CONFLICT(bucket_key) DO UPDATE SET
             tokens = excluded.tokens, last_refill_ms = excluded.last_refill_ms''',
        [key, tokens, lastRefill],
      );
      _db.execute('COMMIT');
      return allowed;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  void reset(String key) {
    _db.execute('DELETE FROM rate_limit_buckets WHERE bucket_key = ?', [key]);
  }

  @override
  int get trackedKeys =>
      (_db
                  .select('SELECT COUNT(*) AS count FROM rate_limit_buckets')
                  .first['count']
              as num)
          .toInt();

  @override
  void dispose() {}
}

class RateLimiter {
  final double maxTokens;
  final double refillRatePerSecond;
  final RateLimitStore store;

  RateLimiter({
    required this.maxTokens,
    required this.refillRatePerSecond,
    RateLimitStore? store,
  }) : store = store ?? InMemoryRateLimitStore();

  bool isAllowed(String key) {
    return store.consume(
      key,
      maxTokens: maxTokens,
      refillRatePerSecond: refillRatePerSecond,
    );
  }

  void reset(String key) {
    store.reset(key);
  }

  void dispose() {
    store.dispose();
  }

  Map<String, dynamic> stats() => {
    'tracked_keys': store.trackedKeys,
    'max_tokens': maxTokens,
    'refill_rate_per_second': refillRatePerSecond,
    'store': store.runtimeType.toString(),
  };
}
