// lib/domain/call/call_state.dart

enum CallDirection { outgoing, incoming }

enum CallStatus {
  idle,
  offering,
  ringing,
  connecting,
  active,
  ending,
  ended,
  failed,
}

/// Why a call ended, when known. Null means a normal hangup (either side
/// ended an active call, or the caller cancelled before the peer responded).
enum CallEndReason { declined, noAnswer, busy }

class CallState {
  const CallState({
    required this.callId,
    required this.peerId,
    required this.peerDisplayName,
    required this.direction,
    required this.status,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isVideoEnabled = false,
    this.isRemoteVideoEnabled = false,
    this.isFrontCamera = true,
    this.startedAt,
    this.endReason,
  });

  final String callId;
  final String peerId;
  final String peerDisplayName;
  final CallDirection direction;
  final CallStatus status;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final bool isRemoteVideoEnabled;

  /// Whether the local camera currently facing the user is the front
  /// ("selfie") camera, as opposed to the rear camera. Only meaningful while
  /// [isVideoEnabled] is true. Determines whether the local video preview
  /// should be mirrored: front camera output is mirrored (so the user's
  /// movements feel natural, like a mirror), rear camera output is shown
  /// as-is. Defaults to true since `getUserMedia` with no facing constraint
  /// opens the front camera first.
  final bool isFrontCamera;
  final DateTime? startedAt;
  final CallEndReason? endReason;

  bool get isActive => status == CallStatus.active;
  bool get isEnded => status == CallStatus.ended || status == CallStatus.failed;
  bool get isInProgress =>
      status == CallStatus.offering ||
      status == CallStatus.ringing ||
      status == CallStatus.connecting ||
      status == CallStatus.active ||
      status == CallStatus.ending;

  CallState copyWith({
    String? callId,
    String? peerId,
    String? peerDisplayName,
    CallDirection? direction,
    CallStatus? status,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isVideoEnabled,
    bool? isRemoteVideoEnabled,
    bool? isFrontCamera,
    DateTime? startedAt,
    CallEndReason? endReason,
  }) => CallState(
    callId: callId ?? this.callId,
    peerId: peerId ?? this.peerId,
    peerDisplayName: peerDisplayName ?? this.peerDisplayName,
    direction: direction ?? this.direction,
    status: status ?? this.status,
    isMuted: isMuted ?? this.isMuted,
    isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
    isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
    isRemoteVideoEnabled: isRemoteVideoEnabled ?? this.isRemoteVideoEnabled,
    isFrontCamera: isFrontCamera ?? this.isFrontCamera,
    startedAt: startedAt ?? this.startedAt,
    endReason: endReason ?? this.endReason,
  );
}
