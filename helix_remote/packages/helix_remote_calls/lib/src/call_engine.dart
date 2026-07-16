import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:helix_remote_calls/src/call_quality.dart';

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

enum RemoteCallEngineConnectionState {
  checking,
  connected,
  completed,
  disconnected,
  failed,
  closed,
}

class RemoteCallConnectionStateEvent extends RemoteCallEngineEvent {
  const RemoteCallConnectionStateEvent({
    required super.callId,
    required this.state,
  }) : connected =
           state == RemoteCallEngineConnectionState.connected ||
           state == RemoteCallEngineConnectionState.completed;

  @Deprecated('Use state for full connection-state mapping.')
  final bool connected;
  final RemoteCallEngineConnectionState state;
}

class RemoteCallEngineDiagnosticEvent extends RemoteCallEngineEvent {
  const RemoteCallEngineDiagnosticEvent({
    required super.callId,
    required this.message,
  });

  final String message;
}

class RemoteVideoStateEvent extends RemoteCallEngineEvent {
  const RemoteVideoStateEvent({required super.callId, required this.enabled});
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

class RemoteCallMediaEvent extends RemoteCallEngineEvent {
  const RemoteCallMediaEvent({
    required super.callId,
    this.localStream,
    this.remoteStream,
    this.localRenderer,
    this.remoteRenderer,
  });

  final webrtc.MediaStream? localStream;
  final webrtc.MediaStream? remoteStream;
  final webrtc.RTCVideoRenderer? localRenderer;
  final webrtc.RTCVideoRenderer? remoteRenderer;
}

/// Periodic quality sample emitted during an active call.
class RemoteCallQualityEvent extends RemoteCallEngineEvent {
  const RemoteCallQualityEvent({required super.callId, required this.metrics});
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
