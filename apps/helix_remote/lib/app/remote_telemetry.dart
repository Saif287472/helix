// P4-07: Telemetry counters for Remote runtime health.
// All exported values are aggregate numbers only — no message content,
// account IDs, device IDs, or personally identifying information is stored.
class RemoteTelemetryCounters {
  int _reconnectCount = 0;
  int _decryptFailureCount = 0;
  int _syncInboundCount = 0;
  int _outboundSentCount = 0;
  final _decryptFailureClasses = <String, int>{};
  final _apiLatencyMs = <int>[];
  final _queueAgeMs = <int>[];
  final _syncLagMs = <int>[];

  int get reconnectCount => _reconnectCount;
  int get decryptFailureCount => _decryptFailureCount;
  int get syncInboundCount => _syncInboundCount;
  int get outboundSentCount => _outboundSentCount;

  void recordReconnect() => _reconnectCount++;

  /// Records a decrypt failure. [failureClass] must be a non-identifying
  /// category such as 'tampered_aad', 'unknown_key', 'malformed_header',
  /// 'expired_session'. Never pass account IDs, device IDs, or message content.
  void recordDecryptFailure(String failureClass) {
    _decryptFailureCount++;
    _decryptFailureClasses[failureClass] =
        (_decryptFailureClasses[failureClass] ?? 0) + 1;
  }

  /// Records how long an outbound operation waited in the queue before sending.
  void recordQueueAge(int ageMs) {
    _queueAgeMs.add(ageMs);
    if (_queueAgeMs.length > 1000) _queueAgeMs.removeAt(0);
  }

  /// Records the gap between an inbound event's server timestamp and when it
  /// was durably applied locally.
  void recordSyncLag(int lagMs) {
    _syncLagMs.add(lagMs);
    if (_syncLagMs.length > 1000) _syncLagMs.removeAt(0);
  }

  /// Records REST API round-trip latency in milliseconds.
  void recordApiLatency(int latencyMs) {
    _apiLatencyMs.add(latencyMs);
    if (_apiLatencyMs.length > 1000) _apiLatencyMs.removeAt(0);
  }

  void recordSyncInbound() => _syncInboundCount++;
  void recordOutboundSent() => _outboundSentCount++;

  /// Returns a snapshot safe for logging and monitoring dashboards.
  /// No content, IDs, or PII appears in the output.
  Map<String, dynamic> snapshot() {
    return {
      'reconnect_count': _reconnectCount,
      'decrypt_failure_count': _decryptFailureCount,
      'decrypt_failure_classes': Map.unmodifiable(_decryptFailureClasses),
      'sync_inbound_count': _syncInboundCount,
      'outbound_sent_count': _outboundSentCount,
      'queue_age_p50_ms': _percentile(_queueAgeMs, 0.5),
      'queue_age_p95_ms': _percentile(_queueAgeMs, 0.95),
      'sync_lag_p50_ms': _percentile(_syncLagMs, 0.5),
      'sync_lag_p95_ms': _percentile(_syncLagMs, 0.95),
      'api_latency_p50_ms': _percentile(_apiLatencyMs, 0.5),
      'api_latency_p95_ms': _percentile(_apiLatencyMs, 0.95),
    };
  }

  void reset() {
    _reconnectCount = 0;
    _decryptFailureCount = 0;
    _syncInboundCount = 0;
    _outboundSentCount = 0;
    _decryptFailureClasses.clear();
    _queueAgeMs.clear();
    _syncLagMs.clear();
    _apiLatencyMs.clear();
  }

  static int? _percentile(List<int> values, double p) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final index = ((sorted.length - 1) * p).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }
}
