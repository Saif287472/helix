import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:helix_remote_calls/src/call_engine.dart';
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

class RemoteCallSignal {
  const RemoteCallSignal({
    required this.callId,
    required this.signalType,
    this.sdp,
    this.candidate,
    this.mlineIndex,
    this.sdpMid,
    this.isVideo = false,
    this.peerId,
  });

  final String callId;
  final String signalType;
  final String? sdp;
  final String? candidate;
  final int? mlineIndex;
  final String? sdpMid;
  final bool isVideo;
  final String? peerId;

  Map<String, dynamic> toJson() => {
    'call_id': callId,
    'signal_type': signalType,
    if (sdp != null) 'sdp': sdp,
    if (candidate != null) 'candidate': candidate,
    if (mlineIndex != null) 'mline_index': mlineIndex,
    if (sdpMid != null) 'sdp_mid': sdpMid,
    'is_video': isVideo,
    if (peerId != null) 'peer_id': peerId,
  };

  factory RemoteCallSignal.fromJson(Map<String, dynamic> json) =>
      RemoteCallSignal(
        callId: json['call_id'] as String,
        signalType: json['signal_type'] as String,
        sdp: json['sdp'] as String?,
        candidate: json['candidate'] as String?,
        mlineIndex: json['mline_index'] as int?,
        sdpMid: json['sdp_mid'] as String?,
        isVideo: json['is_video'] as bool? ?? false,
        peerId: json['peer_id'] as String?,
      );
}

abstract interface class RemoteCallSignalingGateway {
  Future<void> sendCallSignal({
    required String targetPeerId,
    required RemoteCallSignal signal,
  });
}

enum RemoteCallState { idle, offering, ringing, active, ended }

class RemoteCallStatus {
  const RemoteCallStatus({
    required this.callId,
    required this.peerId,
    required this.isVideo,
    required this.direction,
    required this.state,
    this.startedAt,
  });

  final String callId;
  final String peerId;
  final bool isVideo;
  final String direction;
  final RemoteCallState state;
  final DateTime? startedAt;
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
  });

  final HelixRemoteDatabase db;
  final RemoteCallEngine engine;
  final RemoteCallSignalingGateway signalingGateway;
  final RemoteIceConfig iceConfig;

  RemoteCallStatus? _activeCall;
  RemoteCallStatus? get activeCall => _activeCall;

  String? _pendingOfferSdp;

  StreamSubscription<RemoteCallEngineEvent>? _engineSub;

  // Calls older than this (ms) are treated as stale on recovery.
  static const int _callTimeoutMs = 60000;

  void start() {
    _engineSub = engine.events.listen(_onEngineEvent);
  }

  void stop() {
    _engineSub?.cancel();
    _engineSub = null;
  }

  // ---------------------------------------------------------------------------
  // Outbound call
  // ---------------------------------------------------------------------------

  Future<void> startOutgoingCall({
    required String peerId,
    required bool isVideo,
  }) async {
    if (_activeCall != null) throw StateError('A call is already in progress');
    final callId = const Uuid().v4();
    _activeCall = RemoteCallStatus(
      callId: callId,
      peerId: peerId,
      isVideo: isVideo,
      direction: kCallDirectionOutgoing,
      state: RemoteCallState.offering,
    );
    db.setActiveCallMarker(
      callId: callId,
      peerId: peerId,
      isVideo: isVideo,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final sdp = await engine.createOffer(callId, video: isVideo);
    await signalingGateway.sendCallSignal(
      targetPeerId: peerId,
      signal: RemoteCallSignal(
        callId: callId,
        signalType: kSignalOffer,
        sdp: sdp,
        isVideo: isVideo,
        peerId: peerId,
      ),
    );
  }

  Future<void> endActiveCall() async {
    final call = _activeCall;
    if (call == null) return;
    final signalType = call.state == RemoteCallState.ringing
        ? kSignalDecline
        : kSignalEnd;
    await signalingGateway.sendCallSignal(
      targetPeerId: call.peerId,
      signal: RemoteCallSignal(callId: call.callId, signalType: signalType),
    );
    await engine.endCall(call.callId);
    _persistCallHistory(call, ended: true);
    db.clearActiveCallMarker();
    _activeCall = null;
  }

  // ---------------------------------------------------------------------------
  // Inbound signal processing (P15-002)
  // ---------------------------------------------------------------------------

  Future<void> processInboundSignal(RemoteCallSignal signal) async {
    switch (signal.signalType) {
      case kSignalOffer:
        await _handleInboundOffer(signal);
      case kSignalAnswer:
        await _handleInboundAnswer(signal);
      case kSignalIce:
        await _handleInboundIce(signal);
      case kSignalDecline:
      case kSignalEnd:
      case kSignalBusy:
        await _handleCallTerminated(signal);
      default:
        break;
    }
  }

  Future<void> _handleInboundOffer(RemoteCallSignal signal) async {
    if (_activeCall != null) {
      await signalingGateway.sendCallSignal(
        targetPeerId: signal.peerId ?? '',
        signal: RemoteCallSignal(
          callId: signal.callId,
          signalType: kSignalBusy,
        ),
      );
      return;
    }
    _pendingOfferSdp = signal.sdp;
    _activeCall = RemoteCallStatus(
      callId: signal.callId,
      peerId: signal.peerId ?? '',
      isVideo: signal.isVideo,
      direction: kCallDirectionIncoming,
      state: RemoteCallState.ringing,
    );
  }

  Future<void> acceptIncomingCall() async {
    final call = _activeCall;
    if (call == null || call.state != RemoteCallState.ringing) return;
    final offerSdp = _pendingOfferSdp ?? '';
    _pendingOfferSdp = null;
    final sdp = await engine.createAnswer(
      call.callId,
      offerSdp,
      video: call.isVideo,
    );
    _activeCall = RemoteCallStatus(
      callId: call.callId,
      peerId: call.peerId,
      isVideo: call.isVideo,
      direction: call.direction,
      state: RemoteCallState.active,
      startedAt: DateTime.now(),
    );
    db.setActiveCallMarker(
      callId: call.callId,
      peerId: call.peerId,
      isVideo: call.isVideo,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await signalingGateway.sendCallSignal(
      targetPeerId: call.peerId,
      signal: RemoteCallSignal(
        callId: call.callId,
        signalType: kSignalAnswer,
        sdp: sdp,
        isVideo: call.isVideo,
      ),
    );
  }

  Future<void> declineIncomingCall() async {
    final call = _activeCall;
    if (call == null) return;
    await signalingGateway.sendCallSignal(
      targetPeerId: call.peerId,
      signal: RemoteCallSignal(callId: call.callId, signalType: kSignalDecline),
    );
    _persistCallHistory(
      RemoteCallStatus(
        callId: call.callId,
        peerId: call.peerId,
        isVideo: call.isVideo,
        direction: kCallDirectionMissed,
        state: RemoteCallState.ended,
      ),
      ended: false,
    );
    _activeCall = null;
  }

  Future<void> _handleInboundAnswer(RemoteCallSignal signal) async {
    final call = _activeCall;
    if (call == null || call.callId != signal.callId) return;
    if (signal.sdp != null) {
      await engine.setRemoteAnswer(call.callId, signal.sdp!);
    }
    _activeCall = RemoteCallStatus(
      callId: call.callId,
      peerId: call.peerId,
      isVideo: call.isVideo,
      direction: call.direction,
      state: RemoteCallState.active,
      startedAt: DateTime.now(),
    );
  }

  Future<void> _handleInboundIce(RemoteCallSignal signal) async {
    if (signal.candidate == null) return;
    await engine.addIceCandidate(
      signal.callId,
      signal.candidate!,
      signal.mlineIndex ?? 0,
      signal.sdpMid ?? '',
    );
  }

  Future<void> _handleCallTerminated(RemoteCallSignal signal) async {
    final call = _activeCall;
    if (call == null || call.callId != signal.callId) return;
    await engine.endCall(call.callId);
    final isMissed =
        signal.signalType == kSignalDecline &&
        call.direction == kCallDirectionIncoming;
    _persistCallHistory(
      RemoteCallStatus(
        callId: call.callId,
        peerId: call.peerId,
        isVideo: call.isVideo,
        direction: isMissed ? kCallDirectionMissed : call.direction,
        state: RemoteCallState.ended,
        startedAt: call.startedAt,
      ),
      ended: call.startedAt != null,
    );
    db.clearActiveCallMarker();
    _activeCall = null;
  }

  // ---------------------------------------------------------------------------
  // Media controls (P15-009, P15-010, P15-011)
  // ---------------------------------------------------------------------------

  Future<void> setMuted({required bool muted}) async {
    final call = _activeCall;
    if (call == null) return;
    await engine.setMuted(call.callId, muted: muted);
  }

  Future<void> setSpeakerOn({required bool enabled}) async {
    final call = _activeCall;
    if (call == null) return;
    await engine.setSpeakerOn(call.callId, enabled: enabled);
  }

  Future<void> setVideoEnabled({required bool enabled}) async {
    final call = _activeCall;
    if (call == null) return;
    await engine.setVideoEnabled(call.callId, enabled: enabled);
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
    if (call == null) return;
    await engine.restartIce(call.callId);
  }

  // ---------------------------------------------------------------------------
  // ICE candidate filtering and forwarding (P15-006, P15-015)
  // ---------------------------------------------------------------------------

  void _onEngineEvent(RemoteCallEngineEvent event) {
    if (event is RemoteIceCandidateEvent) {
      final call = _activeCall;
      if (call == null) return;
      if (!_shouldForwardCandidate(event.candidate)) return;
      signalingGateway.sendCallSignal(
        targetPeerId: call.peerId,
        signal: RemoteCallSignal(
          callId: call.callId,
          signalType: kSignalIce,
          candidate: event.candidate,
          mlineIndex: event.mlineIndex,
          sdpMid: event.sdpMid,
        ),
      );
    }
  }

  bool _shouldForwardCandidate(String candidate) {
    if (iceConfig.ipPrivacy == IpPrivacyMode.relayOnly) {
      return candidate.contains('typ relay');
    }
    return true;
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
      isVideo: call.isVideo,
      direction: call.direction,
      durationSeconds: durationSeconds,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  List<Map<String, dynamic>> getCallHistory({int limit = 50}) =>
      db.getCallHistory(limit: limit);

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
        isVideo: (stale['is_video'] as int) != 0,
        direction: kCallDirectionMissed,
        durationSeconds: 0,
        timestamp: startedAt,
      );
      db.clearActiveCallMarker();
    }
  }
}
