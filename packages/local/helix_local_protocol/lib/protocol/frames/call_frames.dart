part of '../protocol_messages.dart';

// ---------------------------------------------------------------------------
// 0x1E CallSignalFrame — WebRTC call signaling (offer/answer/ice/control).
// ---------------------------------------------------------------------------

/// Signal types: offer | answer | ice | ringing | accept | decline | cancel |
///               end | busy
class CallSignalFrame extends ProtocolFrame {
  @override
  final int type = kTypeCallSignal;

  /// Unique per-call identifier (UUID v4). All signals in one call share this.
  final String callId;

  /// One of: offer, answer, ice, ringing, accept, decline, cancel, end, busy.
  final String signalType;

  /// SDP payload for offer / answer / accept frames.
  final String? sdp;

  /// ICE candidate string for ice frames.
  final String? candidate;

  /// m-line index for ice frames.
  final int? mlineIndex;

  /// SDP mid for ice frames.
  final String? sdpMid;

  CallSignalFrame({
    required this.callId,
    required this.signalType,
    this.sdp,
    this.candidate,
    this.mlineIndex,
    this.sdpMid,
  });

  factory CallSignalFrame._fromMap(Map<Object?, Object?> map) =>
      CallSignalFrame(
        callId: _requireString(map, 1, 'callId'),
        signalType: _requireString(map, 2, 'signalType'),
        sdp: map[3] as String?,
        candidate: map[4] as String?,
        mlineIndex: map[5] as int?,
        sdpMid: map[6] as String?,
      );

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeCallSignal,
    1: callId,
    2: signalType,
    if (sdp != null) 3: sdp,
    if (candidate != null) 4: candidate,
    if (mlineIndex != null) 5: mlineIndex,
    if (sdpMid != null) 6: sdpMid,
  });
}
