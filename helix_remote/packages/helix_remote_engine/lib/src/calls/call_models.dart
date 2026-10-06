import 'package:meta/meta.dart';

/// Which way a call came.
enum CallDirection { incoming, outgoing }

/// Where a call stands, as the UI shows it.
enum CallPhase {
  /// Outgoing: the offer is going out, no device has reported ringing.
  calling,

  /// Outgoing: a device of the callee is ringing. Incoming: this device is
  /// ringing and waits for [CallsService.accept] or [CallsService.decline].
  ringing,

  /// Both sides agreed; the media connection is being set up.
  connecting,

  /// Media flows: the call is live.
  active,

  /// Over; [CallSnapshot.end] says how. The next snapshot is `null`.
  ended,
}

/// How a call ended, from this device's point of view.
enum CallEnd {
  /// This user hung up an answered call.
  hungUp,

  /// The other side hung up an answered call.
  remoteHungUp,

  /// This user declined the incoming call.
  declinedByMe,

  /// The callee declined this user's call.
  declinedByPeer,

  /// This user cancelled before anyone answered.
  cancelledByMe,

  /// The caller gave up before this device answered (a missed call).
  cancelledByPeer,

  /// Nobody answered in time (outgoing), or this device was not answered in
  /// time (incoming: a missed call).
  unanswered,

  /// The callee is in another call.
  busy,

  /// Another device of this account answered (incoming call, no longer
  /// ringing here).
  answeredElsewhere,

  /// Another device of this account declined.
  declinedElsewhere,

  /// Media never connected or broke for good, or the call could not be set
  /// up.
  failed,

  /// Both sides called each other at once and this call lost.
  glare,
}

/// A call as the UI sees it: immutable, replaced on every change.
@immutable
final class CallSnapshot {
  const CallSnapshot({
    required this.callId,
    required this.peer,
    required this.direction,
    required this.video,
    required this.phase,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
    this.end,
    this.muted = false,
    this.cameraOn = false,
  });

  final String callId;

  /// The other party's account id (look the person up in `people`).
  final String peer;
  final CallDirection direction;

  /// The call was offered with video.
  final bool video;
  final CallPhase phase;
  final DateTime startedAt;

  /// When media connected (talk time is measured from here), or null.
  final DateTime? answeredAt;
  final DateTime? endedAt;

  /// Set when [phase] is [CallPhase.ended].
  final CallEnd? end;
  final bool muted;
  final bool cameraOn;

  bool get isIncoming => direction == CallDirection.incoming;

  /// Still going (not [CallPhase.ended]).
  bool get isLive => phase != CallPhase.ended;

  CallSnapshot copyWith({
    CallPhase? phase,
    DateTime? answeredAt,
    DateTime? endedAt,
    CallEnd? end,
    bool? muted,
    bool? cameraOn,
  }) => CallSnapshot(
    callId: callId,
    peer: peer,
    direction: direction,
    video: video,
    phase: phase ?? this.phase,
    startedAt: startedAt,
    answeredAt: answeredAt ?? this.answeredAt,
    endedAt: endedAt ?? this.endedAt,
    end: end ?? this.end,
    muted: muted ?? this.muted,
    cameraOn: cameraOn ?? this.cameraOn,
  );

  @override
  String toString() => 'CallSnapshot(${direction.name} ${phase.name})';
}

/// An offer that waits for this device on the server (it was offline when
/// the call came), seen without opening it: who is calling and until when.
/// What a host's call notification needs; the offer itself is opened only
/// by the running app (`CallsService.fetchPending`).
@immutable
final class PendingCallNotice {
  const PendingCallNotice({
    required this.callId,
    required this.caller,
    required this.expiresAt,
  });

  final String callId;

  /// The caller's account id.
  final String caller;

  /// After this the call stops ringing (the server drops the offer).
  final DateTime expiresAt;
}
