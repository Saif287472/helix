import 'package:helix_remote_engine/src/calls/call_models.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:meta/meta.dart';

/// Where the engine stands. Hosts show sign-in when [signedOut] or
/// [revoked], and treat [running] as "messaging works" (use
/// `Engine.connection` for the socket's state).
enum EngineStatus {
  /// Created, [Engine.start] not called yet.
  idle,

  /// No account on this database, or the session ended: sign in.
  signedOut,

  /// Workers are running.
  running,

  /// [Engine.stop] was called.
  stopped,

  /// The server revoked this device (close code 4003 or `device_revoked`).
  /// With `wipeOnRevocation` the local data is already gone.
  revoked,
}

/// What a notification needs about one new incoming message. Returned from
/// every inbound run so the FCM background isolate can show it, and
/// emitted on [Engine.events] when the app is running.
@immutable
final class IncomingNotice {
  const IncomingNotice({
    required this.conversationId,
    required this.messageRowid,
    required this.messageId,
    required this.sender,
    required this.kind,
    required this.preview,
    required this.muted,
    required this.sentAt,
  });

  final String conversationId;
  final int messageRowid;
  final String messageId;

  /// Account id of the author.
  final String sender;

  /// The content type (`text`, `media`, …).
  final String kind;

  /// Message text or caption, one line; empty for kinds without text.
  final String preview;

  /// The chat is muted: record the message, show no alert.
  final bool muted;
  final DateTime sentAt;
}

/// Things that happen while the engine runs, for UI and notifications.
/// Data changes themselves are watch queries on the database; events cover
/// what a query cannot show.
sealed class EngineEvent {
  const EngineEvent();
}

final class IncomingMessageEvent extends EngineEvent {
  const IncomingMessageEvent(this.notice);

  final IncomingNotice notice;
}

/// A contact started or stopped typing (ephemeral; never stored).
final class TypingEvent extends EngineEvent {
  const TypingEvent({
    required this.conversationId,
    required this.account,
    required this.typing,
  });

  final String conversationId;
  final String account;
  final bool typing;
}

/// An account's identity key changed (CRYPTO_V2.md §2): old sessions were
/// dropped and the safety number differs.
final class KeyChangedEvent extends EngineEvent {
  const KeyChangedEvent(this.account);

  final String account;
}

/// A server-generated signal about this account (new sign-in, password
/// changed, suspension, …).
final class AccountSignalReceived extends EngineEvent {
  const AccountSignalReceived(this.signal);

  final AccountSignalEvent signal;
}

/// This account's device list changed (a device was linked or revoked).
final class OwnDevicesChanged extends EngineEvent {
  const OwnDevicesChanged();
}

/// A message could not be sent and the engine gave up (`errorCode`).
final class SendFailedEvent extends EngineEvent {
  const SendFailedEvent({required this.messageRowid, required this.errorCode});

  final int? messageRowid;
  final String errorCode;
}

/// An envelope could not be read and was quarantined (a "couldn't decrypt"
/// row is shown when it belongs to a chat). [code] says why, never what.
final class EnvelopeQuarantined extends EngineEvent {
  const EnvelopeQuarantined({required this.envelopeId, required this.code});

  final String envelopeId;
  final String code;
}

/// The account was suspended (or reinstated) while the app was running.
final class SuspensionChanged extends EngineEvent {
  const SuspensionChanged({required this.suspended});

  final bool suspended;
}

/// A call is ringing on this device (a live offer, or one fetched after a
/// push). The UI shows its incoming-call screen; [call] follows the call
/// through `CallsService.watchCurrent`.
final class IncomingCallEvent extends EngineEvent {
  const IncomingCallEvent(this.call);

  final CallSnapshot call;
}

/// A call rang here and nobody answered it (or it was cancelled), so the
/// user missed it. [notice] is shaped like a message notice
/// (`kind: 'missed_call'`, `messageId` the call id, `messageRowid` 0 because
/// there is no message row yet) so one notification path serves both. Calls
/// that this device never saw ring reach it as an `IncomingNotice` for the
/// caller's `call_log` message instead.
final class MissedCallEvent extends EngineEvent {
  const MissedCallEvent(this.notice);

  final IncomingNotice notice;
}
