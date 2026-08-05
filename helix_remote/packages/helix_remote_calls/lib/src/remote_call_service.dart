import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:uuid/uuid.dart';
import 'package:helix_remote_calls/src/call_engine.dart';
import 'package:helix_remote_calls/src/call_quality.dart';
import 'package:helix_remote_calls/src/call_setup_failure.dart';
import 'package:helix_remote_calls/src/ice_config.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';

const String kCallDirectionOutgoing = 'OUTGOING';
const String kCallDirectionIncoming = 'INCOMING';
const String kCallDirectionMissed = 'MISSED';

const String kSignalOffer = 'offer';
const String kSignalAnswer = 'answer';
const String kSignalIce = 'ice';
const String kSignalDecline = 'decline';
const String kSignalEnd = 'end';
const String kSignalBusy = 'busy';
const String kSignalCancel = 'cancel';
const String kSignalAnsweredElsewhere = 'answered_elsewhere';

class RemoteCallSignal {
  const RemoteCallSignal({
    required this.callId,
    required this.signalType,
    this.callerAccountId,
    this.callerDeviceId,
    this.calleeAccountId,
    this.targetDeviceId,
    this.sdp,
    this.candidate,
    this.mlineIndex,
    this.sdpMid,
    this.isVideo = false,
    this.createdAt,
    this.expiresAt,
    String? peerId,
  }) : _legacyPeerId = peerId;

  final String callId;
  final String signalType;
  final String? callerAccountId;
  final String? callerDeviceId;
  final String? calleeAccountId;
  final String? targetDeviceId;
  final String? sdp;
  final String? candidate;
  final int? mlineIndex;
  final String? sdpMid;
  final bool isVideo;
  final int? createdAt;
  final int? expiresAt;
  final String? _legacyPeerId;

  @Deprecated('Use callerAccountId/calleeAccountId/targetDeviceId.')
  String? get peerId =>
      callerAccountId ?? calleeAccountId ?? targetDeviceId ?? _legacyPeerId;

  Map<String, dynamic> toJson() => {
    'call_id': callId,
    'signal_type': signalType,
    if (callerAccountId != null) 'caller_account_id': callerAccountId,
    if (callerDeviceId != null) 'caller_device_id': callerDeviceId,
    if (calleeAccountId != null) 'callee_account_id': calleeAccountId,
    if (targetDeviceId != null) 'target_device_id': targetDeviceId,
    if (sdp != null) 'sdp': sdp,
    if (candidate != null) 'candidate': candidate,
    if (mlineIndex != null) 'mline_index': mlineIndex,
    if (sdpMid != null) 'sdp_mid': sdpMid,
    'is_video': isVideo,
    if (createdAt != null) 'created_at': createdAt,
    if (expiresAt != null) 'expires_at': expiresAt,
    if (callerAccountId == null &&
        calleeAccountId == null &&
        targetDeviceId == null &&
        _legacyPeerId != null)
      'peer_id': _legacyPeerId,
  };

  factory RemoteCallSignal.fromJson(Map<String, dynamic> json) =>
      RemoteCallSignal(
        callId: json['call_id'] as String,
        signalType: json['signal_type'] as String,
        callerAccountId:
            json['caller_account_id'] as String? ?? json['peer_id'] as String?,
        callerDeviceId: json['caller_device_id'] as String?,
        calleeAccountId: json['callee_account_id'] as String?,
        targetDeviceId: json['target_device_id'] as String?,
        sdp: json['sdp'] as String?,
        candidate: json['candidate'] as String?,
        mlineIndex: json['mline_index'] as int?,
        sdpMid: json['sdp_mid'] as String?,
        isVideo: json['is_video'] as bool? ?? false,
        createdAt: json['created_at'] as int?,
        expiresAt: json['expires_at'] as int?,
      );
}

abstract interface class RemoteCallSignalingGateway {
  Future<void> sendCallSignal({
    String? targetAccountId,
    String? targetDeviceId,
    required RemoteCallSignal signal,
  });
}

enum RemoteCallState {
  preparing,
  dialing,
  ringing,
  connecting,
  active,
  reconnecting,
  declined,
  busy,
  failed,
  ended,
}

class RemoteCallStatus {
  const RemoteCallStatus({
    required this.callId,
    String? peerId,
    String? peerAccountId,
    this.peerDeviceId,
    required this.isVideo,
    required this.direction,
    required this.state,
    this.startedAt,
    this.peerDisplayName,
    this.localRenderer,
    this.remoteRenderer,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isLocalVideoEnabled = true,
    this.isFrontCamera = true,
    this.errorMessage,
    this.quality,
  }) : peerAccountId = peerAccountId ?? peerId ?? '';

  final String callId;
  final String peerAccountId;
  final String? peerDeviceId;
  final bool isVideo;
  final String direction;
  final RemoteCallState state;
  final DateTime? startedAt;
  final String? peerDisplayName;
  final webrtc.RTCVideoRenderer? localRenderer;
  final webrtc.RTCVideoRenderer? remoteRenderer;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isLocalVideoEnabled;
  final bool isFrontCamera;
  final String? errorMessage;
  final CallQualityMetrics? quality;

  String get displayName =>
      peerDisplayName == null || peerDisplayName!.trim().isEmpty
      ? peerAccountId
      : peerDisplayName!;

  @Deprecated('Use peerAccountId.')
  String get peerId => peerAccountId;

  RemoteCallStatus copyWith({
    String? peerAccountId,
    String? peerDeviceId,
    RemoteCallState? state,
    DateTime? startedAt,
    String? peerDisplayName,
    webrtc.RTCVideoRenderer? localRenderer,
    webrtc.RTCVideoRenderer? remoteRenderer,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isLocalVideoEnabled,
    bool? isFrontCamera,
    String? errorMessage,
    bool clearErrorMessage = false,
    CallQualityMetrics? quality,
  }) {
    return RemoteCallStatus(
      callId: callId,
      peerAccountId: peerAccountId ?? this.peerAccountId,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      isVideo: isVideo,
      direction: direction,
      state: state ?? this.state,
      startedAt: startedAt ?? this.startedAt,
      peerDisplayName: peerDisplayName ?? this.peerDisplayName,
      localRenderer: localRenderer ?? this.localRenderer,
      remoteRenderer: remoteRenderer ?? this.remoteRenderer,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isLocalVideoEnabled: isLocalVideoEnabled ?? this.isLocalVideoEnabled,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      quality: quality ?? this.quality,
    );
  }
}

/// Orchestrates Remote call lifecycle: signaling, media controls, and history.
///
/// Inject a [RemoteCallEngine] stub in tests; wire the production
/// RemoteWebRtcCallEngine in the composition root.
///
/// Call [start] after construction to begin listening to engine events,
/// and [stop] on teardown.
class RemoteCallService {
  RemoteCallService({
    required this.db,
    required this.engine,
    required this.signalingGateway,
    this.iceConfig = const RemoteIceConfig(iceServers: []),
    this.diagnostics,
    this.metricsUploader,
    Duration outgoingRingTimeout = const Duration(seconds: 45),
    Duration incomingRingTimeout = const Duration(seconds: 45),
    Duration offerAnswerTimeout = const Duration(seconds: 20),
    Duration iceConnectionTimeout = const Duration(seconds: 20),
    Duration disconnectedGrace = const Duration(seconds: 10),
    Duration? terminalStateGrace,
    List<Duration>? reconnectBackoff,
  }) : _reconnectBackoff = reconnectBackoff ?? _defaultReconnectBackoff,
       _outgoingRingLimit = outgoingRingTimeout,
       _incomingRingLimit = incomingRingTimeout,
       _offerAnswerLimit = offerAnswerTimeout,
       _iceConnectionLimit = iceConnectionTimeout,
       _disconnectedGracePeriod = disconnectedGrace,
       _terminalStateGrace = terminalStateGrace ?? const Duration(seconds: 2);

  final HelixRemoteDatabase db;
  final RemoteCallEngine engine;
  final RemoteCallSignalingGateway signalingGateway;
  final RemoteIceConfig iceConfig;
  final void Function(String message)? diagnostics;
  // F7: optional hook for uploading privacy-safe call metrics at call end.
  final Future<void> Function(Map<String, dynamic> metrics)? metricsUploader;
  final Duration _outgoingRingLimit;
  final Duration _incomingRingLimit;
  final Duration _offerAnswerLimit;
  final Duration _iceConnectionLimit;
  final Duration _disconnectedGracePeriod;
  final Duration _terminalStateGrace;

  /// Injectable so a test can exercise the max-attempts path without waiting
  /// out the real table, the same reason `disconnectedGrace` is injectable.
  final List<Duration> _reconnectBackoff;

  RemoteCallStatus? _activeCall;
  RemoteCallStatus? get activeCall => _activeCall;

  final _callStatusController = StreamController<RemoteCallStatus?>.broadcast(
    sync: true,
  );

  Stream<RemoteCallStatus?> get callStatusChanges =>
      _callStatusController.stream;

  void _emitCallStatus() {
    if (!_callStatusController.isClosed) {
      _callStatusController.add(_activeCall);
    }
  }

  bool _transition(RemoteCallState next, {DateTime? startedAt}) {
    final call = _activeCall;
    if (call == null || _terminalCalls.contains(call.callId)) return false;
    if (!_isLegalTransition(call.state, next)) return false;
    _activeCall = call.copyWith(state: next, startedAt: startedAt);
    _emitCallStatus();
    return true;
  }

  bool _isLegalTransition(RemoteCallState from, RemoteCallState to) {
    if (from == to) return true;
    if (_isTerminal(from)) return false;
    if (_isTerminal(to)) return true;
    switch (from) {
      case RemoteCallState.preparing:
        return {
          RemoteCallState.dialing,
          RemoteCallState.connecting,
        }.contains(to);
      // `active` is reachable directly, without an observed `connecting`.
      // The engine reports `checking` and `connected` as separate events, but
      // it is not obliged to give us both: a fast or already-warm ICE path
      // can surface `connected` first, and the two can coalesce. Refusing the
      // edge left such a call stuck showing "dialing" while media flowed, and
      // silently disabled everything gated on `active` - adaptive media,
      // reconnect backoff, and ICE restart.
      case RemoteCallState.dialing:
        return {
          RemoteCallState.connecting,
          RemoteCallState.active,
          RemoteCallState.busy,
          RemoteCallState.declined,
        }.contains(to);
      case RemoteCallState.ringing:
        return {
          RemoteCallState.connecting,
          RemoteCallState.active,
          RemoteCallState.declined,
          RemoteCallState.busy,
        }.contains(to);
      case RemoteCallState.connecting:
        return {
          RemoteCallState.active,
          RemoteCallState.reconnecting,
        }.contains(to);
      case RemoteCallState.active:
        return RemoteCallState.reconnecting == to;
      case RemoteCallState.reconnecting:
        return {RemoteCallState.active, RemoteCallState.failed}.contains(to);
      case RemoteCallState.declined:
      case RemoteCallState.busy:
      case RemoteCallState.failed:
      case RemoteCallState.ended:
        return false;
    }
  }

  bool _isTerminal(RemoteCallState state) {
    return {
      RemoteCallState.declined,
      RemoteCallState.busy,
      RemoteCallState.failed,
      RemoteCallState.ended,
    }.contains(state);
  }

  void _cancelTimers() {
    _outgoingRingTimer?.cancel();
    _incomingRingTimer?.cancel();
    _offerAnswerTimer?.cancel();
    _iceConnectionTimer?.cancel();
    _disconnectedTimer?.cancel();
    _outgoingRingTimer = null;
    _incomingRingTimer = null;
    _offerAnswerTimer = null;
    _iceConnectionTimer = null;
    _disconnectedTimer = null;
  }

  void _diag(String message) {
    diagnostics?.call(message);
  }

  void _startOutgoingTimers(String callId) {
    _outgoingRingTimer?.cancel();
    _offerAnswerTimer?.cancel();
    _diag(
      'timer start cid=${_cid(callId)} outgoing_ring_ms=${_outgoingRingLimit.inMilliseconds} '
      'offer_answer_ms=${_offerAnswerLimit.inMilliseconds}',
    );
    _outgoingRingTimer = Timer(
      _outgoingRingLimit,
      () => _failCallIfActive(callId, RemoteCallState.failed),
    );
    _offerAnswerTimer = Timer(
      _offerAnswerLimit,
      () => _failCallIfActive(callId, RemoteCallState.failed),
    );
  }

  void _startIncomingTimer(String callId) {
    _incomingRingTimer?.cancel();
    _diag(
      'timer start cid=${_cid(callId)} incoming_ring_ms=${_incomingRingLimit.inMilliseconds}',
    );
    _incomingRingTimer = Timer(
      _incomingRingLimit,
      () => _failCallIfActive(callId, RemoteCallState.ended),
    );
  }

  void _startIceConnectionTimer(String callId) {
    _iceConnectionTimer?.cancel();
    _diag(
      'timer start cid=${_cid(callId)} ice_connect_ms=${_iceConnectionLimit.inMilliseconds}',
    );
    _iceConnectionTimer = Timer(
      _iceConnectionLimit,
      () => _failCallIfActive(callId, RemoteCallState.failed),
    );
  }

  Future<void> _failCallIfActive(
    String callId,
    RemoteCallState terminalState,
  ) async {
    final call = _activeCall;
    if (call == null || call.callId != callId) return;
    _diag(
      'timer fired cid=${_cid(callId)} terminal=${terminalState.name} state=${call.state.name}',
    );
    await _finishCall(
      call,
      terminalState: terminalState,
      notifyPeer: true,
      errorMessage: _terminalMessage(terminalState),
    );
  }

  Future<void> _finishCall(
    RemoteCallStatus call, {
    required RemoteCallState terminalState,
    required bool notifyPeer,
    String? errorMessage,
    bool showTerminalState = true,
  }) async {
    if (_terminalCalls.contains(call.callId)) return;
    _diag(
      'finish begin cid=${_cid(call.callId)} state=${call.state.name} '
      'terminal=${terminalState.name} notify=$notifyPeer',
    );
    _terminalCalls.add(call.callId);
    _cancelTimers();
    if (notifyPeer) {
      try {
        await signalingGateway.sendCallSignal(
          targetAccountId:
              call.direction == kCallDirectionOutgoing ||
                  call.peerDeviceId == null
              ? call.peerAccountId
              : null,
          targetDeviceId: call.peerDeviceId,
          signal: RemoteCallSignal(
            callId: call.callId,
            signalType: terminalState == RemoteCallState.declined
                ? kSignalDecline
                : kSignalEnd,
            targetDeviceId: call.peerDeviceId,
          ),
        );
      } catch (_) {
        // Local cleanup must still complete if the signaling path is down.
      }
    }
    await _safeEndCall(call.callId);
    final terminalCall = RemoteCallStatus(
      callId: call.callId,
      peerAccountId: call.peerAccountId,
      peerDeviceId: call.peerDeviceId,
      isVideo: call.isVideo,
      direction: _historyDirection(call, terminalState),
      state: terminalState,
      startedAt: call.startedAt,
      peerDisplayName: call.peerDisplayName,
      errorMessage: errorMessage ?? _terminalMessage(terminalState),
      quality: call.quality,
    );
    _persistCallHistory(
      terminalCall,
      ended: call.startedAt != null && terminalState == RemoteCallState.ended,
    );
    // F7: upload privacy-safe metrics fire-and-forget.
    _uploadMetrics(call, terminalState);
    db.clearActiveCallMarker();
    _pendingIce.remove(call.callId);
    _seenIce.removeWhere((key) => key.startsWith('${call.callId}|'));
    if (showTerminalState && _terminalStateGrace > Duration.zero) {
      _activeCall = terminalCall;
      _emitCallStatus();
      await Future<void>.delayed(_terminalStateGrace);
      if (_activeCall?.callId != call.callId) return;
    }
    _activeCall = null;
    _emitCallStatus();
    _diag('finish complete cid=${_cid(call.callId)}');
  }

  void _uploadMetrics(RemoteCallStatus call, RemoteCallState terminalState) {
    final uploader = metricsUploader;
    if (uploader == null) return;
    final setupMs = _lastSetupTimeMs;
    final reconnects = _metricsReconnectCount;
    final connType = _lastConnectionType;
    final loss = _lastPacketLoss;
    final rtt = _lastRttMs;
    final startedAt = call.startedAt;
    final durationSec = startedAt != null
        ? DateTime.now().difference(startedAt).inSeconds
        : 0;
    final outcome = switch (terminalState) {
      RemoteCallState.ended => 'completed',
      RemoteCallState.declined => 'declined',
      RemoteCallState.failed => 'failed',
      RemoteCallState.busy => 'busy',
      _ => 'missed',
    };
    // Reset accumulators for next call.
    _callSetupStart = null;
    _lastSetupTimeMs = null;
    _metricsReconnectCount = 0;
    _lastConnectionType = null;
    _lastPacketLoss = null;
    _lastRttMs = null;
    uploader({
      'call_id': call.callId,
      'connection_type': connType,
      'reconnect_count': reconnects,
      'call_outcome': outcome,
      'duration_seconds': durationSec,
      'setup_time_ms': ?setupMs,
      'packet_loss_percent': ?loss,
      'peer_rtt_ms': ?rtt,
    }).ignore();
  }

  String _historyDirection(RemoteCallStatus call, RemoteCallState terminal) {
    if (call.direction == kCallDirectionIncoming &&
        call.startedAt == null &&
        terminal != RemoteCallState.ended) {
      return kCallDirectionMissed;
    }
    return call.direction;
  }

  String? _terminalMessage(RemoteCallState state) {
    return switch (state) {
      RemoteCallState.busy => 'The other device is already in a call.',
      RemoteCallState.declined => 'The call was declined.',
      RemoteCallState.failed =>
        'The call could not be completed. Check your network and try again.',
      RemoteCallState.ended => null,
      _ => null,
    };
  }

  String? _pendingOfferSdp;
  final Map<String, List<RemoteCallSignal>> _pendingIce = {};
  final Set<String> _seenIce = <String>{};
  final Set<String> _terminalCalls = <String>{};
  final Map<String, int> _silencedUnknownCalls = {};
  Timer? _outgoingRingTimer;
  Timer? _incomingRingTimer;
  Timer? _offerAnswerTimer;
  Timer? _iceConnectionTimer;
  Timer? _disconnectedTimer;
  bool _restartInProgress = false;

  // F7: reconnect backoff
  int _reconnectAttempt = 0;
  static const List<Duration> _defaultReconnectBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];
  static const int _maxReconnectAttempts = 5;

  // F7: adaptive media
  bool _audioOnlyFallback = false;
  int _goodQualitySamples = 0;
  int _lastAdaptMs = 0;
  static const int _adaptCooldownMs = 15000;
  static const double _weakLossThreshold = 15.0;
  static const double _recoverLossThreshold = 5.0;
  static const double _weakRttMs = 400.0;
  static const double _recoverRttMs = 200.0;
  static const int _recoverSamplesNeeded = 2;

  // F7: privacy-safe metrics accumulators
  DateTime? _callSetupStart;
  int? _lastSetupTimeMs;
  int _metricsReconnectCount = 0;
  String? _lastConnectionType;
  double? _lastPacketLoss;
  double? _lastRttMs;

  StreamSubscription<RemoteCallEngineEvent>? _engineSub;

  // Calls older than this (ms) are treated as stale on recovery.
  static const int _callTimeoutMs = 60000;
  static const int _maxCandidateLength = 4096;

  void start() {
    if (_engineSub != null) return;
    _engineSub = engine.events.listen(_onEngineEvent);
  }

  Future<void> stop() async {
    await _engineSub?.cancel();
    _engineSub = null;
  }

  Future<void> dispose() async {
    final call = _activeCall;
    if (call != null) {
      await _finishCall(
        call,
        terminalState: RemoteCallState.ended,
        notifyPeer: false,
      );
    }
    _cancelTimers();
    await stop();
    await _callStatusController.close();
    await engine.dispose();
  }

  // ---------------------------------------------------------------------------
  // Outbound call
  // ---------------------------------------------------------------------------

  Future<void> startOutgoingCall({
    required String peerId,
    required bool isVideo,
    String? peerDisplayName,
  }) async {
    if (_activeCall != null) throw StateError('A call is already in progress');
    _terminalCalls.clear();
    _callSetupStart = DateTime.now();
    final callId = const Uuid().v4();
    _diag(
      'outgoing start cid=${_cid(callId)} peer_set=${peerId.isNotEmpty} video=$isVideo',
    );
    _activeCall = RemoteCallStatus(
      callId: callId,
      peerId: peerId,
      isVideo: isVideo,
      direction: kCallDirectionOutgoing,
      state: RemoteCallState.preparing,
      peerDisplayName: peerDisplayName,
    );
    _emitCallStatus();
    db.setActiveCallMarker(
      callId: callId,
      peerId: peerId,
      peerAccountId: peerId,
      isVideo: isVideo,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      final sdp = await engine.createOffer(callId, video: isVideo);
      _transition(RemoteCallState.dialing);
      await signalingGateway.sendCallSignal(
        targetAccountId: peerId,
        signal: RemoteCallSignal(
          callId: callId,
          signalType: kSignalOffer,
          sdp: sdp,
          isVideo: isVideo,
          calleeAccountId: peerId,
        ),
      );
      _startOutgoingTimers(callId);
    } catch (error) {
      await _safeEndCall(callId);
      _activeCall = RemoteCallStatus(
        callId: callId,
        peerAccountId: peerId,
        isVideo: isVideo,
        direction: kCallDirectionOutgoing,
        state: RemoteCallState.failed,
        peerDisplayName: peerDisplayName,
        // A setup failure that knows what went wrong says so. The generic
        // sentence remains only for genuinely unclassified errors - it used
        // to be shown even when the server had told us plainly that it has
        // no TURN relay, which sent users looking at their own connection
        // for a server-side configuration problem.
        errorMessage: error is RemoteCallSetupException
            ? error.userMessage
            : 'The call could not be started. '
                  'Check server and call connectivity.',
      );
      _emitCallStatus();
      _persistCallHistory(
        RemoteCallStatus(
          callId: callId,
          peerAccountId: peerId,
          isVideo: isVideo,
          direction: kCallDirectionOutgoing,
          state: RemoteCallState.failed,
          peerDisplayName: peerDisplayName,
        ),
        ended: false,
      );
      db.clearActiveCallMarker();
      _cancelTimers();
      if (_terminalStateGrace > Duration.zero) {
        await Future<void>.delayed(_terminalStateGrace);
      }
      _activeCall = null;
      _emitCallStatus();
      rethrow;
    }
  }

  Future<void> endActiveCall() async {
    final call = _activeCall;
    if (call == null) return;
    await _finishCall(
      call,
      terminalState: call.state == RemoteCallState.ringing
          ? RemoteCallState.declined
          : RemoteCallState.ended,
      notifyPeer: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Inbound signal processing (P15-002)
  // ---------------------------------------------------------------------------

  Future<void> processInboundSignal(RemoteCallSignal signal) async {
    _diag(
      'inbound ${signal.signalType} cid=${_cid(signal.callId)} '
      'has_sdp=${signal.sdp != null && signal.sdp!.isNotEmpty} '
      'has_candidate=${signal.candidate != null && signal.candidate!.isNotEmpty} '
      'active=${_activeCall == null ? "none" : _cid(_activeCall!.callId)}',
    );
    switch (signal.signalType) {
      case kSignalOffer:
        if (_shouldSilenceUnknownOffer(signal)) {
          _recordSilencedUnknownOffer(signal);
          return;
        }
        await _handleInboundOffer(signal);
      case kSignalAnswer:
        await _handleInboundAnswer(signal);
      case kSignalIce:
        await _handleInboundIce(signal);
      case kSignalDecline:
      case kSignalEnd:
      case kSignalBusy:
      case kSignalCancel:
      case kSignalAnsweredElsewhere:
        await _handleCallTerminated(signal);
      default:
        break;
    }
  }

  bool _shouldSilenceUnknownOffer(RemoteCallSignal signal) {
    if (!db.getSilenceUnknownCallers()) return false;
    final caller = signal.callerAccountId ?? signal.peerId ?? '';
    if (caller.isEmpty) return true;
    final contact = db.getContact(caller);
    return contact == null || contact.status != 'Accepted';
  }

  void _recordSilencedUnknownOffer(RemoteCallSignal signal) {
    final caller = signal.callerAccountId ?? signal.peerId ?? 'unknown';
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _silencedUnknownCalls[caller] ?? 0;
    if (now - last < const Duration(minutes: 5).inMilliseconds) {
      _diag(
        'unknown call silenced rate_limited caller_set=${caller != 'unknown'}',
      );
      return;
    }
    _silencedUnknownCalls[caller] = now;
    _diag('unknown call silenced cid=${_cid(signal.callId)}');
    db.saveCallHistory(
      callId: signal.callId,
      peerId: caller,
      peerAccountId: caller,
      peerDeviceId: signal.callerDeviceId,
      isVideo: signal.isVideo,
      direction: kCallDirectionMissed,
      outcome: 'silenced_unknown',
      durationSeconds: 0,
      timestamp: now,
    );
  }

  Future<void> _handleInboundOffer(RemoteCallSignal signal) async {
    final active = _activeCall;
    if (active != null &&
        active.callId == signal.callId &&
        signal.sdp != null) {
      if (active.state == RemoteCallState.ringing) {
        _diag('offer duplicate ignored cid=${_cid(signal.callId)}');
        return;
      }
      _diag('offer restart cid=${_cid(signal.callId)}');
      await _handleRestartOffer(active, signal);
      return;
    }
    if (active != null) {
      _diag(
        'offer busy cid=${_cid(signal.callId)} active=${_cid(active.callId)} state=${active.state.name}',
      );
      await signalingGateway.sendCallSignal(
        targetAccountId: signal.callerAccountId ?? signal.peerId,
        targetDeviceId: signal.callerDeviceId ?? signal.targetDeviceId,
        signal: RemoteCallSignal(
          callId: signal.callId,
          signalType: kSignalBusy,
          targetDeviceId: signal.callerDeviceId ?? signal.targetDeviceId,
        ),
      );
      return;
    }
    _terminalCalls.remove(signal.callId);
    _pendingOfferSdp = signal.sdp;
    _diag(
      'offer accepted cid=${_cid(signal.callId)} '
      'sdp_len=${signal.sdp?.length ?? 0} video=${signal.isVideo}',
    );
    _activeCall = RemoteCallStatus(
      callId: signal.callId,
      peerAccountId: signal.callerAccountId ?? signal.peerId ?? '',
      peerDeviceId: signal.callerDeviceId,
      isVideo: signal.isVideo,
      direction: kCallDirectionIncoming,
      state: RemoteCallState.ringing,
    );
    _emitCallStatus();
    _startIncomingTimer(signal.callId);
  }

  Future<void> acceptIncomingCall() async {
    final call = _activeCall;
    if (call == null || call.state != RemoteCallState.ringing) {
      _diag(
        'accept ignored active=${call == null ? "none" : _cid(call.callId)} '
        'state=${call?.state.name ?? "none"}',
      );
      return;
    }
    final offerSdp = _pendingOfferSdp ?? '';
    _pendingOfferSdp = null;
    _transition(RemoteCallState.connecting);
    _incomingRingTimer?.cancel();
    _startIceConnectionTimer(call.callId);
    try {
      final sdp = await engine.createAnswer(
        call.callId,
        offerSdp,
        video: call.isVideo,
      );
      await _flushQueuedIce(call.callId);
      db.setActiveCallMarker(
        callId: call.callId,
        peerId: call.peerAccountId,
        peerAccountId: call.peerAccountId,
        peerDeviceId: call.peerDeviceId,
        isVideo: call.isVideo,
        startedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await signalingGateway.sendCallSignal(
        targetAccountId: call.peerDeviceId == null ? call.peerAccountId : null,
        targetDeviceId: call.peerDeviceId,
        signal: RemoteCallSignal(
          callId: call.callId,
          signalType: kSignalAnswer,
          sdp: sdp,
          isVideo: call.isVideo,
          targetDeviceId: call.peerDeviceId,
        ),
      );
    } catch (_) {
      await _finishCall(
        call,
        terminalState: RemoteCallState.failed,
        notifyPeer: false,
        errorMessage: _terminalMessage(RemoteCallState.failed),
      );
      rethrow;
    }
  }

  Future<void> declineIncomingCall() async {
    final call = _activeCall;
    if (call == null) return;
    await _finishCall(
      call,
      terminalState: RemoteCallState.declined,
      notifyPeer: true,
    );
  }

  Future<void> _handleInboundAnswer(RemoteCallSignal signal) async {
    final call = _activeCall;
    if (call == null) {
      _diag('answer ignored cid=${_cid(signal.callId)} reason=no_active_call');
      return;
    }
    if (call.callId != signal.callId) {
      _diag(
        'answer ignored cid=${_cid(signal.callId)} '
        'active=${_cid(call.callId)} reason=call_id_mismatch',
      );
      return;
    }
    _diag(
      'answer accepted cid=${_cid(signal.callId)} '
      'has_sdp=${signal.sdp != null && signal.sdp!.isNotEmpty}',
    );
    if (signal.sdp != null) {
      await engine.setRemoteAnswer(call.callId, signal.sdp!);
    }
    _outgoingRingTimer?.cancel();
    _offerAnswerTimer?.cancel();
    _startIceConnectionTimer(call.callId);
    if (signal.callerDeviceId != null &&
        signal.callerDeviceId != call.peerDeviceId) {
      _activeCall = call.copyWith(peerDeviceId: signal.callerDeviceId);
    }
    _transition(RemoteCallState.connecting);
    await _flushQueuedIce(call.callId);
  }

  Future<void> _handleInboundIce(RemoteCallSignal signal) async {
    final call = _activeCall;
    if (call == null) {
      _diag('ice ignored cid=${_cid(signal.callId)} reason=no_active_call');
      return;
    }
    if (call.callId != signal.callId) {
      _diag(
        'ice ignored cid=${_cid(signal.callId)} '
        'active=${_cid(call.callId)} reason=call_id_mismatch',
      );
      return;
    }
    final candidate = signal.candidate;
    if (candidate == null || !_isValidInboundCandidate(candidate)) {
      _diag('ice ignored cid=${_cid(signal.callId)} reason=invalid_candidate');
      return;
    }
    final key =
        '${signal.callId}|$candidate|${signal.mlineIndex ?? 0}|${signal.sdpMid ?? ''}';
    final type = _candidateType(candidate);
    if (!_seenIce.add(key)) {
      _diag(
        'ice ignored cid=${_cid(signal.callId)} type=$type reason=duplicate',
      );
      return;
    }
    if (call.state == RemoteCallState.ringing ||
        call.state == RemoteCallState.preparing ||
        call.state == RemoteCallState.dialing) {
      _pendingIce.putIfAbsent(signal.callId, () => []).add(signal);
      _diag(
        'ice queued cid=${_cid(signal.callId)} '
        'type=$type state=${call.state.name}',
      );
      return;
    }
    _diag('ice adding cid=${_cid(signal.callId)} type=$type');
    await engine.addIceCandidate(
      signal.callId,
      candidate,
      signal.mlineIndex ?? 0,
      signal.sdpMid ?? '',
    );
  }

  Future<void> _handleCallTerminated(RemoteCallSignal signal) async {
    final call = _activeCall;
    if (call == null) {
      _diag(
        '${signal.signalType} ignored cid=${_cid(signal.callId)} reason=no_active_call',
      );
      return;
    }
    if (call.callId != signal.callId) {
      _diag(
        '${signal.signalType} ignored cid=${_cid(signal.callId)} '
        'active=${_cid(call.callId)} reason=call_id_mismatch',
      );
      return;
    }
    final terminal = switch (signal.signalType) {
      kSignalDecline ||
      kSignalCancel ||
      kSignalAnsweredElsewhere => RemoteCallState.declined,
      kSignalBusy => RemoteCallState.busy,
      _ => RemoteCallState.ended,
    };
    _diag(
      '${signal.signalType} accepted cid=${_cid(signal.callId)} terminal=${terminal.name}',
    );
    await _finishCall(call, terminalState: terminal, notifyPeer: false);
  }

  // ---------------------------------------------------------------------------
  // Media controls (P15-009, P15-010, P15-011)
  // ---------------------------------------------------------------------------

  Future<void> setMuted({required bool muted}) async {
    final call = _activeCall;
    if (call == null) return;
    await engine.setMuted(call.callId, muted: muted);
    _activeCall = call.copyWith(isMuted: muted);
    _emitCallStatus();
  }

  Future<void> setSpeakerOn({required bool enabled}) async {
    final call = _activeCall;
    if (call == null) return;
    await engine.setSpeakerOn(call.callId, enabled: enabled);
    _activeCall = call.copyWith(isSpeakerOn: enabled);
    _emitCallStatus();
  }

  Future<void> setVideoEnabled({required bool enabled}) async {
    final call = _activeCall;
    if (call == null) return;
    await engine.setVideoEnabled(call.callId, enabled: enabled);
    _activeCall = call.copyWith(isLocalVideoEnabled: enabled);
    _emitCallStatus();
  }

  Future<void> switchCamera() async {
    final call = _activeCall;
    if (call == null) return;
    await engine.switchCamera(call.callId);
  }

  // ---------------------------------------------------------------------------
  // Network handoff (P15-012)
  // ---------------------------------------------------------------------------

  Future<void> restartIce() async {
    final call = _activeCall;
    if (call == null || _restartInProgress) return;
    if (call.state != RemoteCallState.active &&
        call.state != RemoteCallState.reconnecting) {
      return;
    }
    // F7: give up after max attempts.
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _diag(
        'reconnect_limit cid=${_cid(call.callId)} attempts=$_reconnectAttempt',
      );
      await _finishCall(
        call,
        terminalState: RemoteCallState.failed,
        notifyPeer: true,
        errorMessage: _terminalMessage(RemoteCallState.failed),
      );
      return;
    }
    _reconnectAttempt++;
    _restartInProgress = true;
    _transition(RemoteCallState.reconnecting);
    try {
      await engine.restartIce(call.callId);
    } catch (_) {
      await _finishCall(
        call,
        terminalState: RemoteCallState.failed,
        notifyPeer: true,
      );
      rethrow;
    } finally {
      // Cleared as soon as this attempt finishes, rather than latching until
      // a later `connected` event. The flag exists to stop two restarts
      // overlapping; latching it meant a restart that succeeded but never
      // recovered blocked every future attempt, so `_reconnectAttempt` never
      // grew, the max-attempts guard never fired, and the call sat in
      // `reconnecting` indefinitely instead of failing. Retries stay paced by
      // the backoff timer in the `disconnected` branch.
      _restartInProgress = false;
    }
  }

  // ---------------------------------------------------------------------------
  // ICE candidate filtering and forwarding (P15-006, P15-015)
  // ---------------------------------------------------------------------------

  void _onEngineEvent(RemoteCallEngineEvent event) {
    if (event is RemoteIceCandidateEvent) {
      final call = _activeCall;
      if (call == null || call.callId != event.callId) return;
      final shouldForward = _shouldForwardCandidate(event.candidate);
      _diag(
        'ice gathered cid=${_cid(event.callId)} '
        'type=${_candidateType(event.candidate)} '
        'mid=${event.sdpMid.isEmpty ? "none" : event.sdpMid} '
        'mline=${event.mlineIndex} '
        'privacy=${iceConfig.ipPrivacy.name} '
        'action=${shouldForward ? "forward" : "filter"}',
      );
      if (!shouldForward) return;
      unawaited(
        signalingGateway.sendCallSignal(
          targetAccountId: call.direction == kCallDirectionOutgoing
              ? call.peerAccountId
              : null,
          targetDeviceId: call.peerDeviceId,
          signal: RemoteCallSignal(
            callId: call.callId,
            signalType: kSignalIce,
            candidate: event.candidate,
            mlineIndex: event.mlineIndex,
            sdpMid: event.sdpMid,
            targetDeviceId: call.peerDeviceId,
          ),
        ),
      );
    } else if (event is RemoteCallConnectionStateEvent) {
      unawaited(_handleEngineConnectionState(event));
    } else if (event is RemoteRenegotiationOfferEvent) {
      unawaited(_sendRenegotiationOffer(event));
    } else if (event is RemoteCallMediaEvent) {
      _handleMediaEvent(event);
    } else if (event is RemoteVideoStateEvent) {
      _handleVideoStateEvent(event);
    } else if (event is RemoteCameraFacingEvent) {
      _handleCameraFacingEvent(event);
    } else if (event is RemoteCallQualityEvent) {
      _handleQualityEvent(event);
    } else if (event is RemoteCallEngineDiagnosticEvent) {
      _diag('engine ${event.message} cid=${_cid(event.callId)}');
    }
  }

  void _handleMediaEvent(RemoteCallMediaEvent event) {
    final call = _activeCall;
    if (call == null || call.callId != event.callId) return;
    _activeCall = call.copyWith(
      localRenderer: event.localRenderer,
      remoteRenderer: event.remoteRenderer,
    );
    _emitCallStatus();
  }

  void _handleVideoStateEvent(RemoteVideoStateEvent event) {
    final call = _activeCall;
    if (call == null || call.callId != event.callId) return;
    _activeCall = call.copyWith(isLocalVideoEnabled: event.enabled);
    _emitCallStatus();
  }

  void _handleCameraFacingEvent(RemoteCameraFacingEvent event) {
    final call = _activeCall;
    if (call == null || call.callId != event.callId) return;
    _activeCall = call.copyWith(isFrontCamera: event.isFrontCamera);
    _emitCallStatus();
  }

  void _handleQualityEvent(RemoteCallQualityEvent event) {
    final call = _activeCall;
    if (call == null || call.callId != event.callId) return;
    const weakNetworkMessage =
        'Weak network detected. Call quality may be reduced.';

    // F7: accumulate metrics for end-of-call upload.
    _lastPacketLoss = event.metrics.packetLossPercent;
    _lastRttMs = event.metrics.roundTripMs;
    _lastConnectionType = event.metrics.isRelay ? 'relay' : 'direct';

    // F7: adaptive media — disable video on degraded network.
    if (call.isVideo && call.state == RemoteCallState.active) {
      _adaptMediaQuality(call, event.metrics);
    }

    _activeCall = call.copyWith(
      quality: event.metrics,
      errorMessage: event.metrics.isWeak ? weakNetworkMessage : null,
      clearErrorMessage:
          !event.metrics.isWeak && call.errorMessage == weakNetworkMessage,
    );
    _emitCallStatus();
  }

  void _adaptMediaQuality(RemoteCallStatus call, CallQualityMetrics metrics) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final lossPoor =
        metrics.packetLossPercent > _weakLossThreshold ||
        metrics.roundTripMs > _weakRttMs;
    final lossGood =
        metrics.packetLossPercent < _recoverLossThreshold &&
        metrics.roundTripMs < _recoverRttMs;

    // The cooldown guards *dropping* video - the expensive, visible action we
    // don't want flapping. It deliberately does not guard recovery, which is
    // already paced by requiring [_recoverSamplesNeeded] consecutive good
    // samples. Applying it to the whole method (as it was) also skipped the
    // good-sample counting, and since quality events arrive every second or
    // two, two good samples could never accumulate inside a 15s window - the
    // recovery branch was unreachable in production, not just under test.
    if (!_audioOnlyFallback && lossPoor) {
      if (nowMs - _lastAdaptMs < _adaptCooldownMs) return;
      _audioOnlyFallback = true;
      _goodQualitySamples = 0;
      _lastAdaptMs = nowMs;
      _diag(
        'adapt video_off cid=${_cid(call.callId)} '
        'loss=${metrics.packetLossPercent.toStringAsFixed(1)}% '
        'rtt=${metrics.roundTripMs.toStringAsFixed(0)}ms',
      );
      engine.setVideoEnabled(call.callId, enabled: false).ignore();
    } else if (_audioOnlyFallback && lossGood) {
      _goodQualitySamples++;
      if (_goodQualitySamples >= _recoverSamplesNeeded) {
        _audioOnlyFallback = false;
        _goodQualitySamples = 0;
        _lastAdaptMs = nowMs;
        _diag('adapt video_on cid=${_cid(call.callId)} recovery confirmed');
        engine.setVideoEnabled(call.callId, enabled: true).ignore();
      }
    } else if (_audioOnlyFallback && !lossGood) {
      _goodQualitySamples = 0;
    }
  }

  bool _shouldForwardCandidate(String candidate) {
    if (candidate.isEmpty) return true;
    if (iceConfig.ipPrivacy == IpPrivacyMode.relayOnly) {
      return candidate.contains('typ relay');
    }
    return true;
  }

  Future<void> _handleEngineConnectionState(
    RemoteCallConnectionStateEvent event,
  ) async {
    final call = _activeCall;
    if (call == null || call.callId != event.callId) return;
    _diag(
      'connection state cid=${_cid(event.callId)} engine=${event.state.name} call=${call.state.name}',
    );
    switch (event.state) {
      case RemoteCallEngineConnectionState.connected:
      case RemoteCallEngineConnectionState.completed:
        _iceConnectionTimer?.cancel();
        _disconnectedTimer?.cancel();
        _restartInProgress = false;
        // F7: track setup time on first active transition.
        if (call.startedAt == null && _callSetupStart != null) {
          _lastSetupTimeMs = DateTime.now()
              .difference(_callSetupStart!)
              .inMilliseconds;
        }
        // F7: reset backoff; count successful reconnects for metrics.
        if (_reconnectAttempt > 0) _metricsReconnectCount++;
        _reconnectAttempt = 0;
        _audioOnlyFallback = false;
        _goodQualitySamples = 0;
        _transition(
          RemoteCallState.active,
          startedAt: call.startedAt ?? DateTime.now(),
        );
      case RemoteCallEngineConnectionState.checking:
        if (call.state == RemoteCallState.dialing ||
            call.state == RemoteCallState.ringing) {
          _transition(RemoteCallState.connecting);
        }
      case RemoteCallEngineConnectionState.disconnected:
        _transition(RemoteCallState.reconnecting);
        _disconnectedTimer?.cancel();
        // F7: first disconnect uses configured grace; subsequent use backoff table.
        final backoff = _reconnectAttempt == 0
            ? _disconnectedGracePeriod
            : _reconnectBackoff[(_reconnectAttempt - 1).clamp(
                0,
                _reconnectBackoff.length - 1,
              )];
        _disconnectedTimer = Timer(backoff, () {
          unawaited(restartIce());
        });
      case RemoteCallEngineConnectionState.failed:
        await _finishCall(
          call,
          terminalState: RemoteCallState.failed,
          notifyPeer: true,
          errorMessage: _terminalMessage(RemoteCallState.failed),
        );
      case RemoteCallEngineConnectionState.closed:
        await _finishCall(
          call,
          terminalState: RemoteCallState.ended,
          notifyPeer: false,
          showTerminalState: false,
        );
    }
  }

  Future<void> _sendRenegotiationOffer(
    RemoteRenegotiationOfferEvent event,
  ) async {
    final call = _activeCall;
    if (call == null || call.callId != event.callId) return;
    await signalingGateway.sendCallSignal(
      targetAccountId:
          call.direction == kCallDirectionOutgoing || call.peerDeviceId == null
          ? call.peerAccountId
          : null,
      targetDeviceId: call.peerDeviceId,
      signal: RemoteCallSignal(
        callId: call.callId,
        signalType: kSignalOffer,
        sdp: event.sdp,
        isVideo: call.isVideo,
        targetDeviceId: call.peerDeviceId,
      ),
    );
  }

  Future<void> _handleRestartOffer(
    RemoteCallStatus call,
    RemoteCallSignal signal,
  ) async {
    _transition(RemoteCallState.reconnecting);
    final sdp = await engine.createAnswer(
      call.callId,
      signal.sdp!,
      video: call.isVideo,
    );
    await signalingGateway.sendCallSignal(
      targetAccountId: call.peerDeviceId == null ? call.peerAccountId : null,
      targetDeviceId: call.peerDeviceId,
      signal: RemoteCallSignal(
        callId: call.callId,
        signalType: kSignalAnswer,
        sdp: sdp,
        isVideo: call.isVideo,
        targetDeviceId: call.peerDeviceId,
      ),
    );
  }

  Future<void> _flushQueuedIce(String callId) async {
    final queued = _pendingIce.remove(callId) ?? const [];
    if (queued.isNotEmpty) {
      _diag('ice flushing cid=${_cid(callId)} count=${queued.length}');
    }
    for (final signal in queued) {
      await engine.addIceCandidate(
        callId,
        signal.candidate ?? '',
        signal.mlineIndex ?? 0,
        signal.sdpMid ?? '',
      );
    }
  }

  bool _isValidInboundCandidate(String candidate) {
    if (candidate.isEmpty) return true;
    if (candidate.length > _maxCandidateLength) return false;
    return candidate.startsWith('candidate:');
  }

  Future<void> _safeEndCall(String callId) async {
    try {
      await engine.endCall(callId);
    } catch (e) {
      _diag('engine endCall failed cid=${_cid(callId)} error=$e');
    }
  }

  String _cid(String callId) =>
      callId.length > 8 ? callId.substring(0, 8) : callId;

  String _candidateType(String candidate) {
    if (candidate.isEmpty) return 'end';
    final match = RegExp(r' typ ([A-Za-z0-9_-]+)').firstMatch(candidate);
    return match?.group(1) ?? 'unknown';
  }

  // ---------------------------------------------------------------------------
  // Call history persistence (P15-013, P15-014)
  // ---------------------------------------------------------------------------

  void _persistCallHistory(RemoteCallStatus call, {required bool ended}) {
    final durationSeconds = (call.startedAt != null && ended)
        ? DateTime.now().difference(call.startedAt!).inSeconds
        : 0;
    db.saveCallHistory(
      callId: call.callId,
      peerId: call.peerId,
      peerAccountId: call.peerAccountId,
      peerDeviceId: call.peerDeviceId,
      isVideo: call.isVideo,
      direction: call.direction,
      outcome: _historyOutcome(call.state, call.direction, durationSeconds),
      durationSeconds: durationSeconds,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String _historyOutcome(
    RemoteCallState state,
    String direction,
    int durationSeconds,
  ) {
    if (durationSeconds > 0 && state == RemoteCallState.ended) {
      return 'completed';
    }
    if (direction == kCallDirectionMissed) return 'missed';
    return switch (state) {
      RemoteCallState.declined => 'declined',
      RemoteCallState.busy => 'busy',
      RemoteCallState.failed => 'failed',
      RemoteCallState.ended => 'ended',
      _ => direction.toLowerCase(),
    };
  }

  List<Map<String, dynamic>> getCallHistory({int limit = 50}) =>
      db.getCallHistory(limit: limit);

  void clearCallHistory() => db.clearCallHistory();

  // ---------------------------------------------------------------------------
  // Call state recovery (P15-008)
  // ---------------------------------------------------------------------------

  void recoverCallState() {
    final stale = db.getActiveCallMarker();
    if (stale == null) return;
    final startedAt = stale['started_at'] as int;
    final ageMs = DateTime.now().millisecondsSinceEpoch - startedAt;
    if (ageMs > _callTimeoutMs) {
      db.saveCallHistory(
        callId: stale['call_id'] as String,
        peerId: stale['peer_id'] as String,
        peerAccountId:
            stale['peer_account_id'] as String? ?? stale['peer_id'] as String,
        peerDeviceId: stale['peer_device_id'] as String?,
        isVideo: (stale['is_video'] as int) != 0,
        direction: kCallDirectionMissed,
        outcome: 'missed',
        durationSeconds: 0,
        timestamp: startedAt,
      );
      db.clearActiveCallMarker();
    }
  }
}
