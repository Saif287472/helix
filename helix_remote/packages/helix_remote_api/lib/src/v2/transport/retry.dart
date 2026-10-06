import 'dart:async';
import 'dart:math';

/// Cancels in-flight requests. Pass one token to several calls to cancel
/// them together (a screen closing, a transfer being stopped).
final class CancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called. Never completes with an error.
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// When the transport retries a request by itself.
///
/// Only requests that are safe to repeat are retried: `GET`, `HEAD`, `PUT`
/// and `DELETE` (idempotent by HTTP), and device-authenticated `POST`/
/// `PATCH` requests, which always carry an `Idempotency-Key` the server
/// replays (REST_V2.md). Public `POST`s (sign-in, codes, refresh) are never
/// repeated: a repeated refresh would look like token reuse and revoke the
/// device.
///
/// They are retried on no response (connection or timeout) and on
/// retryable error codes (`rate_limited`, `unavailable`, `maintenance`,
/// `internal`, `federation_unavailable`), waiting `Retry-After` when the
/// server sends it, else exponential backoff with jitter.
final class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 8),
    this.maxRetryAfter = const Duration(seconds: 30),
    this.jitter = 0.2,
  });

  /// No retries at all.
  static const none = RetryPolicy(maxAttempts: 1);

  /// Attempts including the first one.
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;

  /// A `Retry-After` longer than this is not waited out: the error is
  /// thrown with its `retryAfter`, for the caller to schedule.
  final Duration maxRetryAfter;

  /// Fraction of the delay added or removed at random.
  final double jitter;

  /// The backoff before attempt `failures + 1`.
  Duration backoff(int failures, Random random) {
    final base = initialDelay * pow(2, max(0, failures - 1)).toInt();
    final capped = base > maxDelay ? maxDelay : base;
    final factor = 1 + jitter * (2 * random.nextDouble() - 1);
    return capped * factor;
  }
}
