/// Domain models for F8 group calls, call links, and scheduled calls.

// ---------------------------------------------------------------------------
// Call room
// ---------------------------------------------------------------------------

enum CallRoomStatus { waiting, active, ended }

class CallRoomParticipant {
  const CallRoomParticipant({
    required this.accountId,
    required this.deviceId,
    required this.role,
    required this.status,
    this.isScreenSharing = false,
    this.joinedAt,
  });

  final String accountId;
  final String deviceId;
  final String role;   // HOST | PARTICIPANT
  final String status; // INVITED | JOINED | LEFT | KICKED
  final bool isScreenSharing;
  final DateTime? joinedAt;

  bool get isJoined => status == 'JOINED';

  factory CallRoomParticipant.fromJson(Map<String, dynamic> j) {
    final jAt = j['joined_at'] as int?;
    return CallRoomParticipant(
      accountId: j['account_id'] as String,
      deviceId: j['device_id'] as String,
      role: j['role'] as String,
      status: j['status'] as String,
      isScreenSharing: (j['is_screen_sharing'] as int? ?? 0) != 0,
      joinedAt: jAt != null ? DateTime.fromMillisecondsSinceEpoch(jAt) : null,
    );
  }
}

class CallRoom {
  const CallRoom({
    required this.roomId,
    required this.hostAccountId,
    required this.status,
    required this.isVideo,
    required this.participants,
    required this.roomKeyEpoch,
    this.roomKeyId,
    this.startedAt,
    this.endedAt,
  });

  final String roomId;
  final String hostAccountId;
  final CallRoomStatus status;
  final bool isVideo;
  final List<CallRoomParticipant> participants;
  final int roomKeyEpoch;
  final String? roomKeyId;
  final DateTime? startedAt;
  final DateTime? endedAt;

  List<CallRoomParticipant> get joinedParticipants =>
      participants.where((p) => p.isJoined).toList(growable: false);

  factory CallRoom.fromJson(Map<String, dynamic> j) {
    final status = switch (j['status'] as String?) {
      'ACTIVE' => CallRoomStatus.active,
      'ENDED' => CallRoomStatus.ended,
      _ => CallRoomStatus.waiting,
    };
    final raw = j['participants'] as List<dynamic>? ?? [];
    final startMs = j['started_at'] as int?;
    final endMs = j['ended_at'] as int?;
    return CallRoom(
      roomId: j['room_id'] as String,
      hostAccountId: j['host_account_id'] as String,
      status: status,
      isVideo: (j['is_video'] as int? ?? 0) != 0,
      participants: raw
          .whereType<Map<String, dynamic>>()
          .map(CallRoomParticipant.fromJson)
          .toList(),
      roomKeyEpoch: j['room_key_epoch'] as int? ?? 0,
      roomKeyId: j['room_key_id'] as String?,
      startedAt: startMs != null
          ? DateTime.fromMillisecondsSinceEpoch(startMs)
          : null,
      endedAt: endMs != null ? DateTime.fromMillisecondsSinceEpoch(endMs) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Call link
// ---------------------------------------------------------------------------

class CallLink {
  const CallLink({
    required this.linkId,
    required this.linkToken,
    required this.requiresApproval,
    required this.createdAt,
    required this.expiresAt,
    this.roomId,
    this.maxUses = 0,
    this.useCount = 0,
  });

  final String linkId;
  final String linkToken;
  final String? roomId;
  final bool requiresApproval;
  final int maxUses;
  final int useCount;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExhausted => maxUses > 0 && useCount >= maxUses;

  factory CallLink.fromJson(Map<String, dynamic> j) => CallLink(
    linkId: j['link_id'] as String,
    linkToken: j['link_token'] as String,
    roomId: j['room_id'] as String?,
    requiresApproval: (j['requires_approval'] as int? ?? 0) != 0,
    maxUses: j['max_uses'] as int? ?? 0,
    useCount: j['use_count'] as int? ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['created_at'] as int),
    expiresAt: DateTime.fromMillisecondsSinceEpoch(j['expires_at'] as int),
  );
}

// ---------------------------------------------------------------------------
// Scheduled call
// ---------------------------------------------------------------------------

enum RsvpStatus { pending, yes, no }

class ScheduledCallAttendee {
  const ScheduledCallAttendee({
    required this.accountId,
    required this.rsvpStatus,
  });

  final String accountId;
  final RsvpStatus rsvpStatus;

  factory ScheduledCallAttendee.fromJson(Map<String, dynamic> j) {
    final rsvp = switch (j['rsvp_status'] as String?) {
      'YES' => RsvpStatus.yes,
      'NO' => RsvpStatus.no,
      _ => RsvpStatus.pending,
    };
    return ScheduledCallAttendee(
      accountId: j['account_id'] as String,
      rsvpStatus: rsvp,
    );
  }
}

class ScheduledCall {
  const ScheduledCall({
    required this.scheduledCallId,
    required this.hostAccountId,
    required this.title,
    required this.scheduledAt,
    required this.createdAt,
    this.roomId,
    this.attendees = const [],
  });

  final String scheduledCallId;
  final String hostAccountId;
  final String title;
  final String? roomId;
  final DateTime scheduledAt;
  final DateTime createdAt;
  final List<ScheduledCallAttendee> attendees;

  factory ScheduledCall.fromJson(Map<String, dynamic> j) {
    final raw = j['attendees'] as List<dynamic>? ?? [];
    return ScheduledCall(
      scheduledCallId: j['scheduled_call_id'] as String,
      hostAccountId: j['host_account_id'] as String,
      title: j['title'] as String,
      roomId: j['room_id'] as String?,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(j['scheduled_at'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(j['created_at'] as int),
      attendees: raw
          .whereType<Map<String, dynamic>>()
          .map(ScheduledCallAttendee.fromJson)
          .toList(),
    );
  }
}
