import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Keeps the Calls tab right on devices that never saw a call ring.
///
/// The caller's device posts a `call_log` message to the chat when a call
/// ends (CONTENT_V2.md §2) "so both sides' devices agree". A device that was
/// offline, or is the caller's other device, learns the call from that
/// message: this writes the matching `call_log` row, unless the device
/// already logged the call itself (it saw it ring).
abstract final class CallLogMirror {
  /// Writes the row for [body] if this device has none. [peer] is the other
  /// party; [fromSelf] says one of this account's own devices placed the
  /// call. [sentAt] is when the message was sent (the end of the call).
  /// Returns true when a row was created.
  static Future<bool> record(
    HelixDb db, {
    required String peer,
    required bool fromSelf,
    required CallLogBody body,
    required DateTime sentAt,
  }) async {
    if (await db.callsDao.byId(body.callId) != null) return false;
    final (String direction, String state)? facts = switch (body.outcome) {
      CallOutcome.answered =>
        fromSelf ? ('outgoing', 'ended') : ('incoming', 'answered_elsewhere'),
      CallOutcome.missed =>
        fromSelf ? ('outgoing', 'unanswered') : ('missed', 'missed'),
      CallOutcome.declined =>
        fromSelf ? ('outgoing', 'declined') : ('incoming', 'declined'),
      CallOutcome.failed => (fromSelf ? 'outgoing' : 'incoming', 'failed'),
      CallOutcome.unknown => null,
    };
    if (facts == null) return false;
    final seconds = body.durationS;
    final answered = body.outcome == CallOutcome.answered && seconds != null
        ? sentAt.subtract(Duration(seconds: seconds))
        : null;
    await db.callsDao.start(
      CallLogCompanion.insert(
        callId: body.callId,
        peerAccountId: peer,
        kind: 'direct',
        direction: facts.$1,
        video: Value(body.media == CallMedia.video),
        state: facts.$2,
        startedAt: answered ?? sentAt,
        answeredAt: Value(answered),
        endedAt: Value(sentAt),
      ),
    );
    return true;
  }
}
