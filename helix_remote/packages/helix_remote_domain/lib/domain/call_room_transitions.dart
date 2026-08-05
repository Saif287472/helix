// Transition tables for the call lifecycles, in the same shape
// `remote_status.dart` already uses for messages, contacts and
// conversations: a frozen adjacency map plus a validator that throws
// rather than letting an illegal move through.
//
// Why these lifecycles first: before this file, the rules lived only in
// SQL `WHERE` clauses on the update statements (`... AND status =
// 'WAITING'`, `... AND status != 'ENDED'`). That works, but it is silent -
// an update that violates the lifecycle matches zero rows and reports
// success, so a caller that got the order wrong sees no error and the row
// simply doesn't change. The tables here make the same rules explicit,
// checkable in one place, and loud when broken.

import 'package:helix_remote_domain/domain/remote_status.dart';

/// A multi-party call room's own lifecycle: it opens waiting for someone to
/// join, becomes active on the first join, and ends once - permanently.
class RemoteCallRoomStatus {
  const RemoteCallRoomStatus._();

  static const waiting = 'WAITING';
  static const active = 'ACTIVE';
  static const ended = 'ENDED';

  /// `ended` is terminal: a room is never reopened, a new one is created.
  /// `waiting -> ended` is legal and routine - the host can end a room
  /// nobody joined.
  static const _transitions = <String, Set<String>>{
    waiting: {active, ended},
    active: {ended},
    ended: {},
  };

  static bool isTerminal(String status) =>
      (_transitions[status] ?? const {}).isEmpty;

  static bool canTransition(String from, String to) =>
      _transitions[from]?.contains(to) ?? false;

  static void validateTransition(String from, String to) {
    final allowed = _transitions[from];
    if (allowed == null) {
      throw RemoteIllegalStatusTransitionException(
        'Unknown call room status: $from',
        from: from,
        to: to,
      );
    }
    if (!allowed.contains(to)) {
      throw RemoteIllegalStatusTransitionException(
        'Illegal call room status transition: $from → $to',
        from: from,
        to: to,
      );
    }
  }
}

/// One device's membership in a room. Distinct from the room's own status:
/// a room stays active while individual participants come and go.
class RemoteCallRoomParticipantStatus {
  const RemoteCallRoomParticipantStatus._();

  static const invited = 'INVITED';
  static const joined = 'JOINED';
  static const left = 'LEFT';
  static const kicked = 'KICKED';

  /// `left -> joined` is deliberately allowed: dropping off a call and
  /// rejoining it is normal. `kicked` is not - a host's removal has to
  /// outlast a reconnect attempt, or kicking someone would achieve nothing.
  static const _transitions = <String, Set<String>>{
    invited: {joined, left, kicked},
    joined: {left, kicked},
    left: {joined},
    kicked: {},
  };

  static bool isTerminal(String status) =>
      (_transitions[status] ?? const {}).isEmpty;

  static bool canTransition(String from, String to) =>
      _transitions[from]?.contains(to) ?? false;

  static void validateTransition(String from, String to) {
    final allowed = _transitions[from];
    if (allowed == null) {
      throw RemoteIllegalStatusTransitionException(
        'Unknown call room participant status: $from',
        from: from,
        to: to,
      );
    }
    if (!allowed.contains(to)) {
      throw RemoteIllegalStatusTransitionException(
        'Illegal call room participant status transition: $from → $to',
        from: from,
        to: to,
      );
    }
  }
}

/// The client-side view of a group call, mirroring `GroupCallStatus` in
/// `helix_remote_calls`. Kept here rather than next to that enum so the
/// rules sit with every other lifecycle table instead of inside the
/// service that happens to drive them.
class RemoteGroupCallStatus {
  const RemoteGroupCallStatus._();

  static const idle = 'idle';
  static const joining = 'joining';
  static const active = 'active';
  static const ended = 'ended';

  /// `joining -> idle` covers a join that fails or is cancelled before the
  /// room is reached. `ended -> idle` is what lets the same service object
  /// be reused for the next call rather than being torn down.
  static const _transitions = <String, Set<String>>{
    idle: {joining},
    joining: {active, ended, idle},
    active: {ended},
    ended: {idle},
  };

  static bool canTransition(String from, String to) =>
      _transitions[from]?.contains(to) ?? false;

  static void validateTransition(String from, String to) {
    final allowed = _transitions[from];
    if (allowed == null) {
      throw RemoteIllegalStatusTransitionException(
        'Unknown group call status: $from',
        from: from,
        to: to,
      );
    }
    if (!allowed.contains(to)) {
      throw RemoteIllegalStatusTransitionException(
        'Illegal group call status transition: $from → $to',
        from: from,
        to: to,
      );
    }
  }
}

/// A 1:1 call, mirroring `RemoteCallState` in `helix_remote_calls`.
///
/// The caller's path is preparing → dialing → connecting → active; the
/// callee's is preparing → ringing → connecting → active. Both converge,
/// which is why `connecting` has two predecessors.
class RemoteCallSessionStatus {
  const RemoteCallSessionStatus._();

  static const preparing = 'preparing';
  static const dialing = 'dialing';
  static const ringing = 'ringing';
  static const connecting = 'connecting';
  static const active = 'active';
  static const reconnecting = 'reconnecting';
  static const declined = 'declined';
  static const busy = 'busy';
  static const failed = 'failed';
  static const ended = 'ended';

  /// `active <-> reconnecting` is the ICE-restart loop and has to cycle.
  /// `declined`, `busy`, `failed` and `ended` are all terminal: every one
  /// of them means this call object is finished, and a retry is a new call.
  static const _transitions = <String, Set<String>>{
    preparing: {dialing, ringing, failed, ended},
    dialing: {connecting, declined, busy, failed, ended},
    ringing: {connecting, declined, failed, ended},
    connecting: {active, failed, ended},
    active: {reconnecting, failed, ended},
    reconnecting: {active, failed, ended},
    declined: {},
    busy: {},
    failed: {},
    ended: {},
  };

  static bool isTerminal(String status) =>
      (_transitions[status] ?? const {}).isEmpty;

  static bool canTransition(String from, String to) =>
      _transitions[from]?.contains(to) ?? false;

  static void validateTransition(String from, String to) {
    final allowed = _transitions[from];
    if (allowed == null) {
      throw RemoteIllegalStatusTransitionException(
        'Unknown call state: $from',
        from: from,
        to: to,
      );
    }
    if (!allowed.contains(to)) {
      throw RemoteIllegalStatusTransitionException(
        'Illegal call state transition: $from → $to',
        from: from,
        to: to,
      );
    }
  }
}

/// Outbox delivery, driven by `outbox_worker.dart`.
///
/// The worker was already the only writer of these values, but nothing
/// stopped a future caller from, say, moving a row out of `DLQ` - which
/// would quietly resurrect an event that was deliberately parked.
class RemoteOutboxStatus {
  const RemoteOutboxStatus._();

  static const pending = 'PENDING';
  static const completed = 'COMPLETED';
  static const failed = 'FAILED';
  static const dlq = 'DLQ';

  /// `failed` is the retryable state - the worker moves a row back to
  /// `pending` on the next sweep, or to `dlq` once retries run out. Both
  /// `completed` and `dlq` are terminal: an event is delivered once, and a
  /// dead-lettered one is only ever removed by an operator, never retried
  /// back into the queue.
  static const _transitions = <String, Set<String>>{
    pending: {completed, failed, dlq},
    failed: {pending, completed, failed, dlq},
    completed: {},
    dlq: {},
  };

  static bool isTerminal(String status) =>
      (_transitions[status] ?? const {}).isEmpty;

  static bool canTransition(String from, String to) =>
      _transitions[from]?.contains(to) ?? false;

  static void validateTransition(String from, String to) {
    final allowed = _transitions[from];
    if (allowed == null) {
      throw RemoteIllegalStatusTransitionException(
        'Unknown outbox status: $from',
        from: from,
        to: to,
      );
    }
    if (!allowed.contains(to)) {
      throw RemoteIllegalStatusTransitionException(
        'Illegal outbox status transition: $from → $to',
        from: from,
        to: to,
      );
    }
  }
}
