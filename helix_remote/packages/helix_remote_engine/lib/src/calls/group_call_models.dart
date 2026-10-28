import 'package:meta/meta.dart';

/// Where a group call is for this device.
enum GroupCallPhase {
  /// An invitation is ringing; this device has not joined.
  ringing,

  /// This device is in the room.
  active,

  /// Over; [GroupCallSnapshot.end] says how. The next snapshot is `null`.
  ended,
}

/// How a group call ended, from this device's point of view.
enum GroupCallEnd {
  /// This user left.
  hungUp,

  /// This user declined the invitation.
  declinedByMe,

  /// Nobody joined before the invitation timed out.
  unanswered,

  /// Everyone else left or dropped.
  everyoneLeft,

  /// Media could not be set up.
  failed,

  /// The call time of whoever pays ran out (Free plan, ADR-036).
  callTimeOver,
}

/// Where one other person is in a room.
enum GroupParticipantState {
  /// Invited, no connection yet (ringing, or waiting for their offer).
  invited,

  /// A connection is being set up.
  connecting,

  /// Media flows between this device and theirs.
  connected,

  /// They declined, or left.
  left,

  /// No connection could be made, or it dropped.
  failed,
}

/// One other person in a group call.
@immutable
final class GroupCallParticipant {
  const GroupCallParticipant(this.account, this.state);

  final String account;
  final GroupParticipantState state;
}

/// A group call as the UI sees it: immutable, replaced on every change.
@immutable
final class GroupCallSnapshot {
  const GroupCallSnapshot({
    required this.roomId,
    required this.group,
    required this.starter,
    required this.isIncoming,
    required this.video,
    required this.phase,
    required this.startedAt,
    required this.participants,
    this.answeredAt,
    this.endedAt,
    this.end,
    this.muted = false,
    this.cameraOn = false,
    this.endsAt,
    this.endingSoon = false,
  });

  final String roomId;

  /// The group conversation (`group:<id>`) the call belongs to.
  final String group;

  /// Who started the room.
  final String starter;

  /// This device was invited rather than started it.
  final bool isIncoming;
  final bool video;
  final GroupCallPhase phase;
  final DateTime startedAt;

  /// The first connection, when talk time starts; null before.
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final GroupCallEnd? end;

  /// Everyone else in the room, this user left out.
  final List<GroupCallParticipant> participants;
  final bool muted;
  final bool cameraOn;

  /// When the call is cut off for want of call time, or null if it spends
  /// none; [endingSoon] says that moment is near.
  final DateTime? endsAt;
  final bool endingSoon;

  bool get isLive => phase != GroupCallPhase.ended;

  /// How many other people are connected now.
  int get connected => participants
      .where((p) => p.state == GroupParticipantState.connected)
      .length;
}
