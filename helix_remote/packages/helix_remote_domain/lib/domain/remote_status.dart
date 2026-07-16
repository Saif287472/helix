// Canonical status vocabulary for Remote direct messaging (Phase 4, P4-02).
// Transition tables encode the only legal state progressions;
// RemoteIllegalStatusTransitionException is thrown for any other move.

class RemoteMessageStatus {
  const RemoteMessageStatus._();

  static const pending = 'PENDING';
  static const sent = 'SENT';
  static const delivered = 'DELIVERED';
  static const read = 'READ';
  static const retrying = 'RETRYING';
  static const failed = 'FAILED';
  static const secureSessionUnavailable = 'SECURE_SESSION_UNAVAILABLE';
  static const edited = 'EDITED';
  static const deleted = 'DELETED';
  static const tombstoned = 'TOMBSTONED';
  static const offline = 'OFFLINE';
  static const keyChanged = 'KEY_CHANGED';
  static const revokedDevice = 'REVOKED_DEVICE';

  // Terminal statuses have no outgoing transitions.
  static const _transitions = <String, Set<String>>{
    pending: {sent, failed, retrying, secureSessionUnavailable},
    sent: {delivered, failed, edited, deleted, tombstoned},
    delivered: {read, edited, deleted, tombstoned},
    read: {edited, deleted, tombstoned},
    retrying: {sent, failed},
    failed: {retrying},
    secureSessionUnavailable: {},
    edited: {deleted, tombstoned, read, delivered},
    deleted: {tombstoned},
    tombstoned: {},
    offline: {pending, retrying},
    keyChanged: {sent, failed},
    revokedDevice: {},
  };

  static bool isTerminal(String status) =>
      (_transitions[status] ?? const {}).isEmpty;

  /// Validates a status transition.
  /// Throws [RemoteIllegalStatusTransitionException] for forbidden transitions.
  static void validateTransition(String from, String to) {
    final allowed = _transitions[from];
    if (allowed == null) {
      throw RemoteIllegalStatusTransitionException(
        'Unknown source message status: $from',
        from: from,
        to: to,
      );
    }
    if (!allowed.contains(to)) {
      throw RemoteIllegalStatusTransitionException(
        'Illegal message status transition: $from → $to',
        from: from,
        to: to,
      );
    }
  }
}

class RemoteContactStatus {
  const RemoteContactStatus._();

  static const pendingSent = 'PendingSent';
  static const pendingReceived = 'PendingReceived';
  static const accepted = 'Accepted';
  static const blocked = 'Blocked';
  static const rejected = 'Rejected';
  static const cancelled = 'Cancelled';
  static const removed = 'Removed';

  static const _transitions = <String, Set<String>>{
    pendingSent: {accepted, cancelled, rejected},
    pendingReceived: {accepted, rejected},
    accepted: {blocked, removed},
    blocked: {accepted, removed},
    rejected: {},
    cancelled: {pendingSent},
    removed: {},
  };

  static void validateTransition(String from, String to) {
    final allowed = _transitions[from];
    if (allowed == null) {
      throw RemoteIllegalStatusTransitionException(
        'Unknown contact status: $from',
        from: from,
        to: to,
      );
    }
    if (!allowed.contains(to)) {
      throw RemoteIllegalStatusTransitionException(
        'Illegal contact status transition: $from → $to',
        from: from,
        to: to,
      );
    }
  }
}

class RemoteConversationStatus {
  const RemoteConversationStatus._();

  static const active = 'active';
  static const archived = 'archived';
  static const left = 'left';

  static const _transitions = <String, Set<String>>{
    active: {archived, left},
    archived: {active, left},
    left: {},
  };

  static void validateTransition(String from, String to) {
    final allowed = _transitions[from];
    if (allowed == null) {
      throw RemoteIllegalStatusTransitionException(
        'Unknown conversation status: $from',
        from: from,
        to: to,
      );
    }
    if (!allowed.contains(to)) {
      throw RemoteIllegalStatusTransitionException(
        'Illegal conversation status transition: $from → $to',
        from: from,
        to: to,
      );
    }
  }
}

class RemoteIllegalStatusTransitionException implements Exception {
  const RemoteIllegalStatusTransitionException(
    this.message, {
    required this.from,
    required this.to,
  });

  final String message;
  final String from;
  final String to;

  @override
  String toString() => 'RemoteIllegalStatusTransitionException: $message';
}
