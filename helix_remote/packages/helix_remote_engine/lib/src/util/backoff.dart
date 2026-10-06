import 'dart:math' as math;

/// Exponential retry delays: [initial], doubling up to [max], spread by
/// ±[jitter] so a recovering server is not hit by every client at once.
final class Backoff {
  const Backoff({
    this.initial = const Duration(seconds: 2),
    this.max = const Duration(minutes: 5),
    this.jitter = 0.2,
  });

  final Duration initial;
  final Duration max;
  final double jitter;

  /// The wait after [failures] failed attempts in a row (1 = the first
  /// failure). [unit] is a random number in [0, 1) (injected for tests).
  Duration delay(int failures, double unit) {
    final exponent = math.min(_maxExponent, math.max(0, failures - 1));
    final base = initial * math.pow(2, exponent).toInt();
    final capped = base > max ? max : base;
    return capped * (1 + jitter * (2 * unit - 1));
  }

  // 2^20 times the initial delay is far past any sensible cap; the limit
  // only keeps the multiplication from overflowing.
  static const _maxExponent = 20;
}
