import 'dart:async';

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

  /// Releases any background resources (e.g. a cleanup timer). Safe to call
  /// more than once.
  void dispose();
}

class InMemoryRateLimitStore implements RateLimitStore {
  // Unbounded growth guard: a client (or spoofed IP) hitting a
  // rate-limited endpoint once creates a bucket that otherwise lives
  // forever. Periodically evicting buckets that have sat idle long enough
  // to be fully refilled keeps the map bounded to actually-active keys.
  InMemoryRateLimitStore({Duration cleanupInterval = const Duration(minutes: 5)}) {
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
  int get trackedKeys => _buckets.length;

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }
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
    final bucket = store.bucketFor(
      key,
      maxTokens: maxTokens,
      refillRatePerSecond: refillRatePerSecond,
    );
    return bucket.consume(1.0);
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
