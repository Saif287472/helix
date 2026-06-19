import 'dart:async';
import 'call_quality.dart';

/// Base class for events emitted by [RemoteCallEngine].
abstract class RemoteCallEngineEvent {
  const RemoteCallEngineEvent({required this.callId});
  final String callId;
}

class RemoteIceCandidateEvent extends RemoteCallEngineEvent {
  const RemoteIceCandidateEvent({
    required super.callId,
    required this.candidate,
    required this.mlineIndex,
    required this.sdpMid,
  });
  final String candidate;
  final int mlineIndex;
  final String sdpMid;
}

class RemoteCallConnectionStateEvent extends RemoteCallEngineEvent {
  const RemoteCallConnectionStateEvent({
    required super.callId,
    required this.connected,
  });
  final bool connected;
}

class RemoteVideoStateEvent extends RemoteCallEngineEvent {
  const RemoteVideoStateEvent({
    required super.callId,
    required this.enabled,
  });
  final bool enabled;
}

class RemoteCameraFacingEvent extends RemoteCallEngineEvent {
  const RemoteCameraFacingEvent({
    required super.callId,
    required this.isFrontCamera,
  });
  final bool isFrontCamera;
}

class RemoteRenegotiationOfferEvent extends RemoteCallEngineEvent {
  const RemoteRenegotiationOfferEvent({
    required super.callId,
    required this.sdp,
  });
  final String sdp;
}

/// Periodic quality sample emitted during an active call.
class RemoteCallQualityEvent extends RemoteCallEngineEvent {
  const RemoteCallQualityEvent({
    required super.callId,
    required this.metrics,
  });
  final CallQualityMetrics metrics;
}

/// Abstract interface for the Remote call engine.
///
/// The production implementation uses flutter_webrtc with STUN/TURN.
/// Tests inject a stub. No Local LAN protocol, no private-IP filtering.
abstract interface class RemoteCallEngine {
  Stream<RemoteCallEngineEvent> get events;

  Future<String> createOffer(String callId, {bool video = false});
  Future<String> createAnswer(
    String callId,
    String offerSdp, {
    bool video = false,
  });
  Future<void> setRemoteAnswer(String callId, String answerSdp);
  Future<void> addIceCandidate(
    String callId,
    String candidate,
    int mlineIndex,
    String sdpMid,
  );
  Future<void> restartIce(String callId);
  Future<void> setMuted(String callId, {required bool muted});
  Future<void> setSpeakerOn(String callId, {required bool enabled});
  Future<void> setVideoEnabled(String callId, {required bool enabled});
  Future<void> switchCamera(String callId);
  Future<void> endCall(String callId);
  Future<void> dispose();
}
