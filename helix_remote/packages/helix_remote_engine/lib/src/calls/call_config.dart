import 'package:meta/meta.dart';

/// Tunables of the call state machine (`EngineConfig.calls`). Defaults are
/// the product values; tests shorten them.
@immutable
final class CallConfig {
  const CallConfig({
    this.ringTimeout = const Duration(seconds: 60),
    this.connectTimeout = const Duration(seconds: 30),
    this.iceBatchDelay = const Duration(milliseconds: 80),
    this.maxQueuedCandidates = 64,
    this.signalTimeout = const Duration(seconds: 10),
  });

  /// How long a call rings before it counts as unanswered: the caller gives
  /// up (and the server keeps the offer for offline devices no longer than
  /// this), a callee device stops ringing and logs a missed call. At most
  /// 120 s (the server's cap).
  final Duration ringTimeout;

  /// How long media may take to connect after the answer before the call
  /// fails.
  final Duration connectTimeout;

  /// Local ICE candidates found within this delay go out as one signal.
  final Duration iceBatchDelay;

  /// Remote candidates held while the media session is not ready; more are
  /// dropped (a hostile peer cannot grow memory without bound).
  final int maxQueuedCandidates;

  /// How long hanging up, declining and the other best-effort signals wait
  /// for the network before the local side moves on without them.
  final Duration signalTimeout;

  CallConfig copyWith({
    Duration? ringTimeout,
    Duration? connectTimeout,
    Duration? iceBatchDelay,
    int? maxQueuedCandidates,
    Duration? signalTimeout,
  }) => CallConfig(
    ringTimeout: ringTimeout ?? this.ringTimeout,
    connectTimeout: connectTimeout ?? this.connectTimeout,
    iceBatchDelay: iceBatchDelay ?? this.iceBatchDelay,
    maxQueuedCandidates: maxQueuedCandidates ?? this.maxQueuedCandidates,
    signalTimeout: signalTimeout ?? this.signalTimeout,
  );
}
