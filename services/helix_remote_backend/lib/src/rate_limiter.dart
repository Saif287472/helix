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

class RateLimiter {
  final Map<String, TokenBucket> _buckets = {};
  final double maxTokens;
  final double refillRatePerSecond;

  RateLimiter({required this.maxTokens, required this.refillRatePerSecond});

  bool isAllowed(String key) {
    final bucket = _buckets.putIfAbsent(
      key,
      () => TokenBucket(
        maxTokens: maxTokens,
        refillRatePerSecond: refillRatePerSecond,
      ),
    );
    return bucket.consume(1.0);
  }

  void reset(String key) {
    _buckets.remove(key);
  }
}
