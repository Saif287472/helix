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
}

abstract interface class RateLimitStore {
  TokenBucket bucketFor(
    String key, {
    required double maxTokens,
    required double refillRatePerSecond,
  });

  void reset(String key);
  int get trackedKeys;
}

class InMemoryRateLimitStore implements RateLimitStore {
  final Map<String, TokenBucket> _buckets = {};

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

  Map<String, dynamic> stats() => {
    'tracked_keys': store.trackedKeys,
    'max_tokens': maxTokens,
    'refill_rate_per_second': refillRatePerSecond,
    'store': store.runtimeType.toString(),
  };
}
