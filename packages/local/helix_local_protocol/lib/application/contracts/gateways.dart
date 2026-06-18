import 'dart:typed_data';

import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';

abstract interface class DiscoveryGateway {
  Stream<List<Peer>> get peers;
  Future<void> start();
  Future<void> stop();
}

abstract interface class SecureSessionGateway {
  Stream<ProtocolFrame> get frames;
  Future<void> send(ProtocolFrame frame);
  Future<void> close();
}

abstract interface class MessageGateway {
  Future<void> sendMessage(String threadId, ChatMessageFrame frame);
  Future<void> sendAck(String threadId, ChatAckFrame frame);
}

abstract interface class TransferGateway {
  bool get supportsFileResume;
  Stream<FileResumeFrame> get resumeEvents;
  Future<void> sendProbe(FileProbeFrame frame);
  Future<void> sendChunk(FileTransferFrame frame);
  Future<void> sendComplete(FileCompleteFrame frame);
  Future<void> sendCancel(FileCancelFrame frame);
  Future<void> sendFileResume(FileResumeFrame frame);
}

abstract interface class EphemeralMediaGateway {
  Future<void> sendEphemeralMedia(EphemeralMediaFrame frame);
}

// ---------------------------------------------------------------------------
// Call engine event hierarchy (emitted by CallEngine, consumed by CallService)
// ---------------------------------------------------------------------------

sealed class CallEngineEvent {
  const CallEngineEvent();
}

final class IceCandidateEvent extends CallEngineEvent {
  const IceCandidateEvent({
    required this.callId,
    required this.candidate,
    required this.mlineIndex,
    required this.sdpMid,
  });
  final String callId;
  final String candidate;
  final int mlineIndex;
  final String sdpMid;
}

final class CallConnectionStateEvent extends CallEngineEvent {
  const CallConnectionStateEvent({
    required this.callId,
    required this.connected,
  });
  final String callId;
  final bool connected;
}

final class CallFailedEvent extends CallEngineEvent {
  const CallFailedEvent({required this.callId, required this.reason});
  final String callId;
  final String reason;
}

final class RemoteVideoStateEvent extends CallEngineEvent {
  const RemoteVideoStateEvent({required this.callId, required this.enabled});
  final String callId;
  final bool enabled;
}

final class RenegotiationOfferEvent extends CallEngineEvent {
  const RenegotiationOfferEvent({required this.callId, required this.sdp});
  final String callId;
  final String sdp;
}

/// Emitted after [CallEngine.switchCamera] completes, reporting whether the
/// local camera is now front-facing — used to decide whether the local
/// video preview should be mirrored.
final class LocalCameraFacingEvent extends CallEngineEvent {
  const LocalCameraFacingEvent({
    required this.callId,
    required this.isFrontCamera,
  });
  final String callId;
  final bool isFrontCamera;
}

// ---------------------------------------------------------------------------
// CallEngine — WebRTC peer-connection lifecycle
// ---------------------------------------------------------------------------

abstract interface class CallEngine {
  Stream<CallEngineEvent> get events;

  /// Create an SDP offer for a new call; returns the local SDP string.
  Future<String> createOffer(String callId, {bool video = false});

  /// Create an SDP answer for an incoming offer; returns the local SDP string.
  Future<String> createAnswer(String callId, String offerSdp, {bool video = false});

  /// Apply the remote peer's SDP answer to a previously created offer.
  Future<void> setRemoteAnswer(String callId, String answerSdp);

  /// Add a remote ICE candidate received via signaling.
  Future<void> addIceCandidate(
    String callId,
    String candidate,
    int mlineIndex,
    String sdpMid,
  );

  /// Mute or unmute the local audio track.
  Future<void> setMuted(String callId, {required bool muted});

  /// Route audio output to the loudspeaker or back to the default earpiece.
  Future<void> setSpeakerOn(String callId, {required bool enabled});

  /// Enable or disable the local camera. If enabling for the first time on
  /// an already-connected call, this triggers SDP renegotiation, surfaced
  /// via a [RenegotiationOfferEvent] on [CallEngine.events].
  Future<void> setVideoEnabled(String callId, {required bool enabled});

  /// Switch between front and back camera. No-op if no video track exists.
  Future<void> switchCamera(String callId);

  /// Close the peer connection for [callId] and release media resources.
  Future<void> endCall(String callId);

  /// Dispose all active sessions and release all resources.
  Future<void> dispose();
}

// ---------------------------------------------------------------------------
// CallSignalingGateway — sends call frames to a specific peer
// ---------------------------------------------------------------------------

abstract interface class CallSignalingGateway {
  Future<void> sendCallSignal(String peerId, CallSignalFrame frame);
}

class NotificationActionIntent {
  const NotificationActionIntent({
    required this.actionId,
    this.threadId,
    this.input,
  });

  final String actionId;
  final String? threadId;
  final String? input;
}

abstract interface class NotificationGateway {
  Stream<NotificationActionIntent> get actions;
  Stream<String> get taps;

  Future<void> init();
  Future<void> showForegroundServiceNotification();
  Future<void> showIncomingRequest(String requesterName, String requestId);
  Future<void> showNewMessage(
    String? senderName,
    bool showSender, {
    String? threadId,
    bool soundEnabled = true,
  });
  Future<void> showIncomingCall(String callId, String peerDisplayName);
  Future<void> cancelIncomingCall(String callId);
  Future<void> cancelNotification(int id);
  Future<void> cancelAll();
  void dispose();
}

abstract interface class SecureIdentityStore {
  Future<DeviceIdentity?> loadIdentity();
  Future<void> saveIdentity(DeviceIdentity identity);
  Future<void> clearIdentity();
}

abstract interface class MessageCipher {
  Future<Uint8List> encrypt(Uint8List plaintext);
  Future<Uint8List> decrypt(Uint8List ciphertext);
}

abstract interface class MessageCodec {
  ChatMessageFrame encodeMessage({
    required String messageId,
    required String threadId,
    required String text,
    required int timestamp,
    String? replyToMessageId,
  });
}

abstract interface class GroupSignalingGateway {
  Future<void> sendControl(String peerFingerprint, GroupControlFrame frame);
  Future<void> sendMessage(String peerFingerprint, GroupMessageFrame frame);
}

abstract interface class ForegroundServiceGateway {
  Future<void> stopService();
}

abstract interface class DiagnosticsGateway {
  Future<String?> getWifiIP();
  Future<String?> getWifiName();
  Future<String> getConnectivityType();
}
