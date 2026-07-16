import 'dart:isolate';

import 'package:helix_remote/services/app_logger.dart';

/// Process-wide monotonic clock — never goes backward regardless of NTP
/// adjustments. Equivalent to Android SystemClock.elapsedRealtime().
final _monoEpoch = Stopwatch()..start();

int get _monoMs => _monoEpoch.elapsedMilliseconds;

class _Checkpoint {
  _Checkpoint(this.label)
      : monoMs = _monoMs,
        wallMs = DateTime.now().millisecondsSinceEpoch,
        worker = Isolate.current.debugName ?? 'main';

  final String label;
  final int monoMs;
  final int wallMs;
  final String worker;
}

/// Accumulates lifecycle checkpoints for one message on one device (sender
/// or receiver) and flushes a structured latency report to [AppLogger].
class MessageLatencyTrace {
  MessageLatencyTrace._({
    required this.messageId,
    required this.correlationId,
    required this.role,
  });

  final String messageId;
  final String correlationId;
  final String role; // 'sender' | 'receiver'

  final List<_Checkpoint> _pts = [];

  int retryCount = 0;
  String connectionState = 'unknown';
  String networkType = 'unknown';
  bool isForeground = true;
  int wsReconnects = 0;
  int pollingCycles = 0;

  // Cross-device gap: estimated from server's embedded wall-clock vs. local
  // wall-clock at receiver_callback time. Subject to NTP skew; useful for
  // identifying gaps of seconds, not sub-100ms precision.
  int? _serverBroadcastGapMs;

  void mark(String stage) => _pts.add(_Checkpoint(stage));

  void noteServerBroadcastTimestamp(int serverEpochMs) {
    final gapMs = DateTime.now().millisecondsSinceEpoch - serverEpochMs;
    _serverBroadcastGapMs = gapMs;
  }

  Future<void> finish() async {
    if (_pts.isEmpty) return;

    final buf = StringBuffer()
      ..writeln('=== Message Latency Trace ===')
      ..writeln(
        'ID:$messageId  corr:$correlationId  role:$role  '
        'conn:$connectionState  net:$networkType  fg:$isForeground  '
        'wsReconn:$wsReconnects  polls:$pollingCycles  retries:$retryCount',
      );

    if (_serverBroadcastGapMs != null) {
      final gapMs = _serverBroadcastGapMs!;
      final flag = gapMs > 500 ? '  ← ROOT-CAUSE AREA' : '';
      buf.writeln(
        '  [cross-device] server_broadcast → receiver_callback: '
        '~${gapMs}ms (wall-clock diff, NTP skew not corrected)$flag',
      );
    }

    buf.writeln('  --- checkpoints ---');
    for (var i = 0; i < _pts.length; i++) {
      final p = _pts[i];
      final delta = i == 0 ? 0 : p.monoMs - _pts[i - 1].monoMs;
      final flag = (i > 0 && delta > 500) ? '  *** >500 ms FLAGGED ***' : '';
      buf.writeln(
        '  [t+${p.monoMs}ms] ${_fmtWall(p.wallMs)} [${p.worker}] '
        '${p.label}${i > 0 ? "  (Δ${delta}ms)" : ""}$flag',
      );
    }

    buf.writeln('  --- adjacent stage durations ---');
    for (var i = 1; i < _pts.length; i++) {
      final delta = _pts[i].monoMs - _pts[i - 1].monoMs;
      final flag = delta > 500 ? '  ← ROOT-CAUSE AREA' : '';
      buf.writeln(
        '  ${_pts[i - 1].label} → ${_pts[i].label}: ${delta}ms$flag',
      );
    }

    await AppLogger.instance.info('MsgLatency', buf.toString());
  }

  static String _fmtWall(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$h:$mi:$s.$ms';
  }
}

/// Global registry of active traces keyed by message ID.
/// Sender traces are keyed by [messageId]; receiver traces by 'recv_[messageId]'.
class MessageLatencyRegistry {
  MessageLatencyRegistry._();

  static final instance = MessageLatencyRegistry._();

  final _traces = <String, MessageLatencyTrace>{};

  /// Start a sender-side trace for [messageId]. Call at [sendText] entry.
  MessageLatencyTrace beginSend(String messageId) {
    final t = MessageLatencyTrace._(
      messageId: messageId,
      correlationId:
          'c${(_monoMs % 1000000).toString().padLeft(6, '0')}',
      role: 'sender',
    );
    _traces[messageId] = t;
    return t;
  }

  /// Get or create a receiver-side trace for [messageId].
  MessageLatencyTrace receiverTrace(String messageId) {
    return _traces.putIfAbsent(
      'recv_$messageId',
      () => MessageLatencyTrace._(
        messageId: messageId,
        correlationId: 'r${(_monoMs % 1000000).toString().padLeft(6, '0')}',
        role: 'receiver',
      ),
    );
  }

  /// Look up an existing sender trace (returns null if not found).
  MessageLatencyTrace? findSend(String messageId) => _traces[messageId];

  /// Complete and flush the sender-side trace for [messageId].
  Future<void> completeSend(String messageId) async {
    final t = _traces.remove(messageId);
    await t?.finish();
  }

  /// Complete and flush the receiver-side trace for [messageId].
  Future<void> completeReceiver(String messageId) async {
    final t = _traces.remove('recv_$messageId');
    await t?.finish();
  }
}
