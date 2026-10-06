import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/pairwise_crypto.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/groups/group_inbound.dart';
import 'package:helix_remote_engine/src/messaging/apply.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What the inbound pipeline asks the rest of the engine to do.
abstract interface class InboundHooks {
  /// The server says this device's one-time prekeys are low.
  Future<void> onPrekeysLow(int remaining);

  /// The account's device list changed (a device was linked or revoked).
  Future<void> onOwnDevicesChanged();

  /// This device was revoked.
  Future<void> onThisDeviceRevoked();

  /// A contact started or stopped typing.
  void onTyping(String conversationId, String account, {required bool typing});

  /// A `call_signal` envelope (sealed signal, or the server's "answered on
  /// another of your devices" notice). Ephemeral: never stored or acked.
  Future<void> onCallSignal(Envelope envelope);
}

/// The result of processing one envelope.
final class InboundResult {
  const InboundResult(this.outcome, {this.notice, this.duplicate = false});

  /// Already processed earlier (a replay); nothing was applied.
  const InboundResult.duplicate()
    : outcome = EnvelopeOutcome.ignored,
      notice = null,
      duplicate = true;

  final EnvelopeOutcome outcome;
  final IncomingNotice? notice;
  final bool duplicate;
}

/// The inbound pipeline (plan §6.3): one envelope in, one transaction out.
///
/// `processed_envelopes` de-duplicates replays. Pairwise payloads are
/// decrypted under the sender device's lock; the content is decoded (an
/// unknown type becomes a placeholder, never a crash); then ONE database
/// transaction commits the new ratchet state, the consumed one-time prekey,
/// the message row with its summary and FTS entry, reactions, receipts,
/// edits and deletes, deferred actions, the `processed_envelopes` row and
/// the cursor. The caller acks after this returns.
///
/// An envelope that cannot be read is quarantined: a "couldn't decrypt"
/// row (and, when the keys are the problem, a request for a fresh session,
/// CRYPTO_V2.md §13a) replaces it, and the stream goes on. Only a
/// [TransientEngineException] (no network while looking up a sender's
/// keys) leaves the envelope unprocessed, because the cumulative ack cannot
/// skip it.
///
/// Group envelopes (`group_message`, `roster_change`) and group key material
/// go to [GroupInbound], which uses the same bookkeeping.
///
/// Nothing here needs the UI, a socket or a timer, so the FCM background
/// isolate runs the same code (`Engine.syncOnce`).
final class InboundProcessor {
  InboundProcessor(
    this._ctx,
    this._crypto,
    this._applier,
    this._outbox,
    this._hooks, {
    this._groups,
  });

  final EngineContext _ctx;
  final PairwiseCrypto _crypto;
  final ContentApplier _applier;
  final OutboxService _outbox;
  final InboundHooks _hooks;
  final GroupInbound? _groups;

  HelixDb get _db => _ctx.db;

  /// Processes [envelope]. Throws [TransientEngineException] when it should
  /// be tried again later; every other outcome is recorded.
  Future<InboundResult> process(Envelope envelope) async {
    final from = envelope.from;
    if (envelope.seq != null &&
        await _db.inboxDao.isProcessed(
          envelope.id,
          senderDevice: from?.device,
        )) {
      return const InboundResult.duplicate();
    }
    switch (envelope.kind) {
      case EnvelopeKind.message:
        return _message(envelope);
      case EnvelopeKind.deviceListChange:
        await _bestEffort(_hooks.onOwnDevicesChanged);
        return _record(envelope, EnvelopeOutcome.applied);
      case EnvelopeKind.keyChange:
        await _keyChange(envelope);
        return _record(envelope, EnvelopeOutcome.applied);
      case EnvelopeKind.accountSignal:
        return _accountSignal(envelope);
      case EnvelopeKind.prekeysLow:
        final remaining = _parse(envelope, PrekeysLowEvent.fromJson)?.remaining;
        if (remaining != null) {
          await _bestEffort(() => _hooks.onPrekeysLow(remaining));
        }
        return _record(envelope, EnvelopeOutcome.applied);
      case EnvelopeKind.callSignal:
        // Call signals are ephemeral (no seq, nothing to record): the calls
        // service opens and acts on them.
        await _bestEffort(() => _hooks.onCallSignal(envelope));
        return _record(envelope, EnvelopeOutcome.ignored);
      case EnvelopeKind.groupMessage:
        final groups = _groups;
        return groups == null
            ? _record(envelope, EnvelopeOutcome.ignored)
            : groups.groupMessage(envelope, _mark);
      case EnvelopeKind.rosterChange:
        final groups = _groups;
        return groups == null
            ? _record(envelope, EnvelopeOutcome.ignored)
            : groups.rosterChange(envelope, _mark);
      case EnvelopeKind.unknown:
        // An unknown kind is acked and ignored (REALTIME_V2.md) so a newer
        // server cannot wedge this client's stream.
        return _record(envelope, EnvelopeOutcome.ignored);
    }
  }

  /// Gives up on an envelope that kept failing for no reason the pipeline
  /// understands: it is quarantined (a placeholder row for a message) so the
  /// stream can go on. No session reset is requested.
  Future<InboundResult> quarantineUnprocessable(Envelope envelope) async {
    final from = envelope.from;
    if (from == null || envelope.kind != EnvelopeKind.message) {
      return _record(envelope, EnvelopeOutcome.quarantined);
    }
    try {
      return await _quarantine(
        envelope,
        DeviceAddress(from.account, from.device),
        'internal_error',
        requestReset: false,
      );
    } on ArgumentError {
      return _record(envelope, EnvelopeOutcome.quarantined);
    }
  }

  // ----------------------------------------------------------- messages

  Future<InboundResult> _message(Envelope envelope) async {
    final from = envelope.from;
    final payload = envelope.payload;
    if (from == null || payload == null) {
      return _record(envelope, EnvelopeOutcome.ignored);
    }
    final DeviceAddress sender;
    try {
      sender = DeviceAddress(from.account, from.device);
    } on ArgumentError {
      return _record(envelope, EnvelopeOutcome.ignored);
    }
    final SealedPayload sealed;
    try {
      sealed = SealedPayload.decode(payload);
    } on Object {
      return _quarantine(envelope, sender, 'bad_payload', requestReset: false);
    }
    if (sealed is SenderKeyMessage) {
      return _record(envelope, EnvelopeOutcome.ignored); // Groups: C4.
    }
    return _crypto.runLocked(
      sender,
      () => _decryptAndApply(envelope, sender, sealed),
    );
  }

  Future<InboundResult> _decryptAndApply(
    Envelope envelope,
    DeviceAddress sender,
    SealedPayload sealed,
  ) async {
    final PairwiseDecryptResult result;
    try {
      result = await _crypto.decrypt(sender, sealed);
    } on TransientEngineException {
      rethrow;
    } on CryptoV2Exception catch (e) {
      return _undecryptable(envelope, sender, e);
    }

    final identity = _ctx.identity;
    final aik = result.remoteIdentity.accountIdentityKey;
    if (sender.account == identity.accountId &&
        !bytesEqual(aik, identity.accountKey.publicKey)) {
      // A device claiming this account under another key.
      return _quarantine(
        envelope,
        sender,
        'untrusted_identity',
        requestReset: false,
      );
    }
    if (result.newSession && sender.account != identity.accountId) {
      final pinned = (await _db.peopleDao.byAccount(
        sender.account,
      ))?.identityKey;
      if (pinned != null && !bytesEqual(pinned, aik)) {
        return _quarantine(
          envelope,
          sender,
          'untrusted_identity',
          requestReset: false,
        );
      }
    }

    final ContentMessage content;
    try {
      content = ContentMessage.decode(result.content);
    } on Object {
      // Decryption worked, so the ratchet moved: commit it, then quarantine.
      // Any decode failure is deterministic (the same bytes fail again), so
      // none is retried: a crafted value must not stall the stream.
      await _commitSessionOnly(result);
      return _quarantine(envelope, sender, 'bad_content', requestReset: false);
    }

    final now = _ctx.now();
    if (content.body is TypingBody) {
      await _commitSessionOnly(result);
      _typing(sender, content);
      return const InboundResult(EnvelopeOutcome.ignored);
    }
    // Group content needs the group's roster (and, for an unknown group or
    // sender, the network) before the transaction; a failure here leaves
    // the envelope unprocessed, nothing was committed.
    final groups = _groups;
    if (groups != null) await groups.prepare(sender, content);

    late ApplyResult applied;
    await _db.transaction(() async {
      await _ctx.sessionStore.save(result.sessions, now: now);
      final used = result.consumedOneTimePrekeyId;
      if (used != null) {
        await _db.cryptoDao.deletePrekey(PrekeyKind.oneTime, used);
      }
      if (result.newSession && sender.account != identity.accountId) {
        await _db.peopleDao.upsertPerson(
          PeopleCompanion.insert(
            accountId: sender.account,
            identityKey: Value(aik),
            updatedAt: now,
          ),
        );
      }
      applied = groups != null && groups.isControl(content.body)
          ? await groups.applyControl(sender, content, now)
          : await _applier.apply(
              sender: sender,
              content: content,
              receivedAt: now,
            );
      await _mark(
        envelope,
        applied.wasIgnored ? EnvelopeOutcome.ignored : EnvelopeOutcome.applied,
        now,
      );
    });
    final notice = applied.notice;
    if (notice != null) _ctx.emit(IncomingMessageEvent(notice));
    return InboundResult(
      applied.wasIgnored ? EnvelopeOutcome.ignored : EnvelopeOutcome.applied,
      notice: notice,
    );
  }

  void _typing(DeviceAddress sender, ContentMessage content) {
    final conversation = content.conversation;
    final self = _ctx.identity.accountId;
    if (sender.account == self ||
        conversation is! DirectConversation ||
        conversation.to != self) {
      return;
    }
    final body = content.body as TypingBody;
    _hooks.onTyping(
      directConversationId(sender.account),
      sender.account,
      typing: body.state == TypingState.started,
    );
  }

  Future<void> _commitSessionOnly(PairwiseDecryptResult result) =>
      _db.transaction(() async {
        await _ctx.sessionStore.save(result.sessions, now: _ctx.now());
        final used = result.consumedOneTimePrekeyId;
        if (used != null) {
          await _db.cryptoDao.deletePrekey(PrekeyKind.oneTime, used);
        }
      });

  // ------------------------------------------------ decryption failures

  Future<InboundResult> _undecryptable(
    Envelope envelope,
    DeviceAddress sender,
    CryptoV2Exception error,
  ) {
    final code = switch (error) {
      UntrustedIdentityException() ||
      InvalidSignatureException() => 'untrusted_identity',
      DecryptionFailedException() => 'auth_failed',
      NoSessionException() => 'no_session',
      UnknownPrekeyException() => 'unknown_prekey',
      DuplicateOrExpiredMessageException() => 'replayed_or_expired',
      TooManySkippedMessagesException() => 'too_many_skipped',
      MalformedCryptoInputException() => 'malformed',
      _ => 'crypto',
    };
    if (envelope.seq == null) {
      // Ephemeral (typing): nothing to show, nothing to repair.
      return Future.value(const InboundResult(EnvelopeOutcome.ignored));
    }
    // A message that fails authentication under a session this device
    // holds is most likely one that was encrypted under a session it has
    // since lost (a restore, a session started while it was in flight), so
    // a re-send is requested for it too. The crypto layer's own flag stays
    // false for such errors because tampering looks the same; the cost of
    // being wrong is a cooldown-limited session start and a re-send the
    // sender authenticates anyway.
    final lostSession =
        error.requestsSessionReset || error is DecryptionFailedException;
    return _quarantine(envelope, sender, code, requestReset: lostSession);
  }

  /// Replaces an unreadable envelope with a visible placeholder and, when
  /// it makes sense, asks the sender's device for a fresh session
  /// (CRYPTO_V2.md §13a).
  ///
  /// Only user-visible messages get a placeholder and a repair request: the
  /// server's `urgent` flag marks them (receipts, reactions, edits and other
  /// control content go out non-urgent, and there is nothing the sender could
  /// re-send for them). A hostile server can only hide a placeholder this
  /// way, which it could do by dropping the message.
  Future<InboundResult> _quarantine(
    Envelope envelope,
    DeviceAddress sender,
    String code, {
    required bool requestReset,
  }) async {
    final now = _ctx.now();
    final self = _ctx.identity.accountId;
    final userMessage = envelope.urgent && envelope.seq != null;
    final repair = requestReset && userMessage;
    await _db.transaction(() async {
      if (sender.account != self && userMessage) {
        final person = await _db.peopleDao.byAccount(sender.account);
        final existing = await _db.messagesDao.find(
          envelope.id,
          sender: sender.account,
        );
        if (existing == null && !(person?.blocked ?? false)) {
          final chat = directConversationId(sender.account);
          await _db.conversationsDao.ensureDirect(sender.account, now: now);
          await _db.peopleDao.upsertPerson(
            PeopleCompanion.insert(accountId: sender.account, updatedAt: now),
          );
          final sentAt = envelope.sentAt.isAfter(now) ? now : envelope.sentAt;
          await _db.messagesDao.insertMessage(
            MessagesCompanion.insert(
              messageId: envelope.id,
              conversationId: chat,
              sender: sender.account,
              senderDevice: Value(sender.device),
              outgoing: false,
              sortKey: SortKey.of(sentAt, envelope.id),
              sentAt: sentAt,
              receivedAt: now,
              kind: MessageKinds.undecryptable,
              payload: Value(
                jsonEncode({
                  'code': code,
                  'waiting': repair,
                  'device': sender.device,
                }),
              ),
              status: MessageStatus.received,
            ),
          );
        }
      }
      if (repair) {
        await _outbox.enqueueReset(
          SessionResetPayload(
            account: sender.account,
            device: sender.device,
            messageId: envelope.id,
          ),
        );
      }
      await _mark(envelope, EnvelopeOutcome.quarantined, now);
    });
    _ctx.emit(EnvelopeQuarantined(envelopeId: envelope.id, code: code));
    return const InboundResult(EnvelopeOutcome.quarantined);
  }

  // ------------------------------------------------- server envelopes

  T? _parse<T>(Envelope envelope, T Function(JsonReader json) decode) {
    final data = envelope.data;
    if (data == null) return null;
    try {
      return decode(JsonReader(data));
    } on Object {
      return null;
    }
  }

  /// A key change reported for [KeyChangeEvent.account]: forget the cached
  /// devices so the next send fetches (and verifies) the new keys.
  Future<void> _keyChange(Envelope envelope) async {
    final event = _parse(envelope, KeyChangeEvent.fromJson);
    if (event == null || event.account == _ctx.identity.accountId) return;
    await _db.peopleDao.markDevicesStale(event.account);
  }

  Future<InboundResult> _accountSignal(Envelope envelope) async {
    final event = _parse(envelope, AccountSignalEvent.fromJson);
    if (event != null) {
      _ctx.emit(AccountSignalReceived(event));
      switch (event.signal) {
        case AccountSignalKind.deviceRevoked:
          if (event.device == _ctx.identity.deviceId) {
            await _record(envelope, EnvelopeOutcome.applied);
            // Not awaited: revoking stops the pipeline this call runs in.
            unawaited(_hooks.onThisDeviceRevoked());
            return const InboundResult(EnvelopeOutcome.applied);
          }
          await _bestEffort(_hooks.onOwnDevicesChanged);
        case AccountSignalKind.suspended:
          _ctx.emit(const SuspensionChanged(suspended: true));
        case AccountSignalKind.unsuspended:
          _ctx.emit(const SuspensionChanged(suspended: false));
        default:
      }
    }
    return _record(envelope, EnvelopeOutcome.applied);
  }

  /// Runs a follow-up whose failure must not block the stream: the next
  /// send or maintenance run repairs what it would have.
  Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Intentionally ignored: see above.
    }
  }

  // --------------------------------------------------------- bookkeeping

  Future<InboundResult> _record(
    Envelope envelope,
    EnvelopeOutcome outcome,
  ) async {
    await _db.transaction(() => _mark(envelope, outcome, _ctx.now()));
    return InboundResult(outcome);
  }

  /// `processed_envelopes` and the cursor, inside the caller's transaction.
  /// Ephemeral envelopes (no `seq`) are never recorded.
  Future<void> _mark(
    Envelope envelope,
    EnvelopeOutcome outcome,
    DateTime now,
  ) async {
    final seq = envelope.seq;
    if (seq == null) return;
    await _db.inboxDao.markProcessed(
      envelope.id,
      senderDevice: envelope.from?.device,
      seq: seq,
      outcome: outcome,
      at: now,
    );
    await _db.inboxDao.advanceCursor(processedSeq: seq, now: now);
  }
}
