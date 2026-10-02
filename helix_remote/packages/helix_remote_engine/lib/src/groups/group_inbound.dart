import 'dart:convert';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_engine/src/groups/group_keyring.dart';
import 'package:helix_remote_engine/src/groups/group_notices.dart';
import 'package:helix_remote_engine/src/groups/group_rekey.dart';
import 'package:helix_remote_engine/src/groups/group_roster.dart';
import 'package:helix_remote_engine/src/groups/sender_key_store.dart';
import 'package:helix_remote_engine/src/messaging/apply.dart';
import 'package:helix_remote_engine/src/messaging/inbound.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Writes `processed_envelopes` and the cursor (the pipeline's own
/// bookkeeping), inside the caller's transaction.
typedef EnvelopeMarker =
    Future<void> Function(
      Envelope envelope,
      EnvelopeOutcome outcome,
      DateTime now,
    );

/// The group half of the inbound pipeline (plan §6.3, CRYPTO_V2.md §7).
///
/// - **Group messages** (`group_message` envelopes): the sender-key
///   ciphertext is verified and decrypted under the sender device's key,
///   decoded, and applied by the same `ContentApplier` as direct chats, in
///   one transaction with the new key state. A message that cannot be read
///   is **quarantined**: a "couldn't decrypt" row, and, when the sender key
///   is missing, a `decryption_error` to the sender (CRYPTO_V2.md §13a) so
///   it sends its key and the message again.
/// - **Control content** that arrives pairwise: `sender_key_distribution`
///   (stored per sending device) and `group_key` (the group master key of an
///   epoch).
/// - **Roster changes** (`roster_change` envelopes, server-generated): the
///   group is read again, notices are written, keys of removed members are
///   dropped, and the member responsible hands out or rotates the group key.
///
/// The network is used only before the transaction (an unknown group is
/// fetched, a member the roster does not list yet triggers a refresh); a
/// network failure there is a `TransientEngineException`, which holds the
/// stream back and retries.
final class GroupInbound {
  GroupInbound(
    this._ctx,
    this._roster,
    this._store,
    this._keyring,
    this._keys,
    this._applier,
    this._outbox,
    this._hooks,
  ) : _notices = GroupNotices(_ctx);

  final EngineContext _ctx;
  final GroupRosterSync _roster;
  final DbSenderKeyStore _store;
  final GroupKeyring _keyring;
  final GroupKeyDistributor _keys;
  final ContentApplier _applier;
  final OutboxService _outbox;
  final InboundHooks _hooks;
  final GroupNotices _notices;

  HelixDb get _db => _ctx.db;

  SenderKeyGroupProtocol get _protocol => SenderKeyGroupProtocol(
    self: _ctx.identity.address,
    store: _store,
    random: _ctx.random,
    clock: _ctx.clock,
  );

  // ---------------------------------------------------------- group messages

  Future<InboundResult> groupMessage(
    Envelope envelope,
    EnvelopeMarker mark,
  ) async {
    final from = envelope.from;
    final groupId = envelope.groupId;
    final payload = envelope.payload;
    if (from == null || groupId == null || payload == null) {
      return _record(envelope, mark, EnvelopeOutcome.ignored);
    }
    final DeviceAddress sender;
    try {
      sender = DeviceAddress(from.account, from.device);
    } on ArgumentError {
      return _record(envelope, mark, EnvelopeOutcome.ignored);
    }
    if (await _roster.ensureKnown(groupId) == null) {
      // The server does not list this account as a member.
      return _record(envelope, mark, EnvelopeOutcome.ignored);
    }
    final SealedPayload sealed;
    try {
      sealed = SealedPayload.decode(payload);
    } on FormatException {
      return _quarantine(
        envelope,
        mark,
        sender,
        groupId,
        'bad_payload',
        resend: false,
      );
    }
    if (sealed is! SenderKeyMessage) {
      return _quarantine(
        envelope,
        mark,
        sender,
        groupId,
        'bad_payload',
        resend: false,
      );
    }
    final GroupDecryption decrypted;
    try {
      decrypted = await _protocol.decrypt(
        groupId: groupId,
        sender: sender,
        payload: sealed,
      );
    } on CryptoV2Exception catch (e) {
      return _undecryptable(envelope, mark, sender, groupId, e);
    }

    final ContentMessage content;
    try {
      content = ContentMessage.decode(decrypted.content);
    } on FormatException {
      // Decryption worked, so the chain moved: commit it, then quarantine.
      await _store.commit(decrypted.writes);
      return _quarantine(
        envelope,
        mark,
        sender,
        groupId,
        'bad_content',
        resend: false,
      );
    }
    final conversation = content.conversation;
    if (conversation is! GroupConversation || conversation.group != groupId) {
      await _store.commit(decrypted.writes);
      return _record(envelope, mark, EnvelopeOutcome.ignored);
    }
    if (content.body is TypingBody) {
      await _store.commit(decrypted.writes);
      if (sender.account != _ctx.identity.accountId) {
        _hooks.onTyping(
          GroupIds.conversationId(groupId),
          sender.account,
          typing: (content.body as TypingBody).state == TypingState.started,
        );
      }
      return const InboundResult(EnvelopeOutcome.ignored);
    }
    await prepare(sender, content, groupId: groupId);

    final now = _ctx.now();
    late ApplyResult applied;
    await _db.transaction(() async {
      await _store.commit(decrypted.writes);
      applied = await _applier.apply(
        sender: sender,
        content: content,
        receivedAt: now,
        viaGroup: true,
      );
      await mark(
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

  /// The network steps content of a group needs before it is applied in a
  /// transaction: an unknown group is fetched, and a sender the stored
  /// roster does not list (a member that joined since the last refresh) or a
  /// key of an epoch newer than the stored one triggers a refresh. Safe to
  /// call for any content; it does nothing for direct chats.
  Future<void> prepare(
    DeviceAddress sender,
    ContentMessage content, {
    String? groupId,
  }) async {
    final body = content.body;
    final id =
        groupId ??
        switch (body) {
          SenderKeyDistributionBody() => body.groupId,
          GroupKeyBody() => body.groupId,
          _ =>
            content.conversation is GroupConversation
                ? (content.conversation as GroupConversation).group
                : null,
        };
    if (id == null) return;
    final group = await _roster.ensureKnown(id);
    if (group == null) return;
    final self = _ctx.identity.accountId;
    final unknownSender =
        sender.account != self &&
        await _db.groupsDao.member(id, sender.account) == null;
    final futureEpoch = body is GroupKeyBody && body.epoch > group.epoch;
    if (unknownSender || futureEpoch) await _roster.refreshForInbound(id);
  }

  // ------------------------------------------------------------ quarantine

  Future<InboundResult> _undecryptable(
    Envelope envelope,
    EnvelopeMarker mark,
    DeviceAddress sender,
    String groupId,
    CryptoV2Exception error,
  ) {
    final code = switch (error) {
      UntrustedIdentityException() ||
      InvalidSignatureException() => 'untrusted_identity',
      DecryptionFailedException() => 'auth_failed',
      NoSenderKeyException() => 'no_sender_key',
      DuplicateOrExpiredMessageException() => 'replayed_or_expired',
      TooManySkippedMessagesException() => 'too_many_skipped',
      MalformedCryptoInputException() => 'malformed',
      _ => 'crypto',
    };
    // A missing key means the distribution never arrived; an authentication
    // failure is most likely a key we hold in another state than the
    // sender's. Both are cured by the sender sending its key and the message
    // again. A bad signature (tampering) and replays are not.
    final resend =
        error is NoSenderKeyException || error is DecryptionFailedException;
    return _quarantine(envelope, mark, sender, groupId, code, resend: resend);
  }

  Future<InboundResult> _quarantine(
    Envelope envelope,
    EnvelopeMarker mark,
    DeviceAddress sender,
    String groupId,
    String code, {
    required bool resend,
  }) async {
    // Ephemeral envelopes (typing) have nothing to show or repair.
    if (envelope.seq == null) {
      return const InboundResult(EnvelopeOutcome.ignored);
    }
    final now = _ctx.now();
    final self = _ctx.identity.accountId;
    final userMessage = envelope.urgent && envelope.seq != null;
    final repair = resend && userMessage;
    await _db.transaction(() async {
      final chat = GroupIds.conversationId(groupId);
      if (sender.account != self &&
          userMessage &&
          await _db.conversationsDao.byId(chat) != null &&
          await _db.messagesDao.find(envelope.id, sender: sender.account) ==
              null) {
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
      if (repair) {
        await _outbox.enqueueReset(
          SessionResetPayload(
            account: sender.account,
            device: sender.device,
            messageId: envelope.id,
          ),
        );
      }
      await mark(envelope, EnvelopeOutcome.quarantined, now);
    });
    _ctx.emit(EnvelopeQuarantined(envelopeId: envelope.id, code: code));
    return const InboundResult(EnvelopeOutcome.quarantined);
  }

  Future<InboundResult> _record(
    Envelope envelope,
    EnvelopeMarker mark,
    EnvelopeOutcome outcome,
  ) async {
    await _db.transaction(() => mark(envelope, outcome, _ctx.now()));
    return InboundResult(outcome);
  }

  // --------------------------------------------------------------- control

  /// Whether [body] is group key material that arrives over a pairwise
  /// session and is handled by [applyControl].
  bool isControl(ContentBody body) =>
      body is SenderKeyDistributionBody || body is GroupKeyBody;

  /// Applies a `sender_key_distribution` or `group_key` from [sender], inside
  /// the caller's transaction (call [prepare] first).
  Future<ApplyResult> applyControl(
    DeviceAddress sender,
    ContentMessage content,
    DateTime now,
  ) async {
    final body = content.body;
    final self = _ctx.identity.accountId;
    final String groupId;
    switch (body) {
      case SenderKeyDistributionBody():
        groupId = body.groupId;
      case GroupKeyBody():
        groupId = body.groupId;
      default:
        return const ApplyResult.ignored('not_control');
    }
    final conversation = content.conversation;
    if (conversation is GroupConversation && conversation.group != groupId) {
      return const ApplyResult.ignored('misaddressed');
    }
    final group = await _db.groupsDao.byId(groupId);
    if (group == null) return const ApplyResult.ignored('unknown_group');
    if (sender.account != self &&
        await _db.groupsDao.member(groupId, sender.account) == null) {
      return const ApplyResult.ignored('not_a_member');
    }
    if (body is SenderKeyDistributionBody) {
      final List<GroupCryptoWrite> writes;
      try {
        writes = await _protocol.receiveControl(sender: sender, body: body);
      } on CryptoV2Exception {
        return const ApplyResult.ignored('bad_sender_key');
      }
      await _store.commit(writes);
      return const ApplyResult.applied();
    }
    return _acceptGroupKey(group, body as GroupKeyBody);
  }

  /// A group master key for an epoch. A held key is never replaced by one
  /// that does not open the stored state, and keys for epochs the server has
  /// not reached are refused (they could push real keys out of the keyring).
  /// A member that is not an admin can still hand a key to someone it added;
  /// the residual risk (a member handing a new member a wrong key) is that
  /// the group's name stays unreadable until an admin's key arrives.
  Future<ApplyResult> _acceptGroupKey(GroupRow group, GroupKeyBody body) async {
    if (body.key.length != 32 || body.epoch < 0 || body.epoch > group.epoch) {
      return const ApplyResult.ignored('bad_group_key');
    }
    final held = await _keyring.keyFor(group.id, body.epoch);
    if (held != null && bytesEqual(held, body.key)) {
      return const ApplyResult.ignored('known_key');
    }
    final blob = group.state;
    final opensNew =
        blob != null &&
        await _keyring.tryOpen(group.id, blob, body.epoch, body.key) != null;
    if (held != null) {
      final opensHeld =
          blob != null &&
          await _keyring.tryOpen(group.id, blob, body.epoch, held) != null;
      if (opensHeld || !opensNew) {
        return const ApplyResult.ignored('key_conflict');
      }
    }
    await _keyring.put(group.id, body.epoch, body.key);
    await _roster.reopenState(group.id);
    return const ApplyResult.applied();
  }

  // --------------------------------------------------------- roster changes

  Future<InboundResult> rosterChange(
    Envelope envelope,
    EnvelopeMarker mark,
  ) async {
    final data = envelope.data;
    RosterChangeEvent? event;
    if (data != null) {
      try {
        event = RosterChangeEvent.fromJson(JsonReader(data));
      } on FormatException {
        event = null;
      }
    }
    if (event == null) {
      return _record(envelope, mark, EnvelopeOutcome.ignored);
    }
    final self = _ctx.identity.accountId;
    final groupId = event.groupId;
    final at = envelope.sentAt;
    switch (event.change) {
      case RosterChangeKind.deleted:
        await _roster.lose(
          groupId,
          'deleted',
          actor: event.actor,
          noticeId: envelope.id,
          at: at,
        );
      case RosterChangeKind.removed || RosterChangeKind.left:
        if (event.members.contains(self)) {
          await _roster.lose(
            groupId,
            event.change == RosterChangeKind.left ? 'left' : 'removed',
            actor: event.actor,
            noticeId: envelope.id,
            at: at,
          );
        } else {
          final update = await _roster.refreshForInbound(groupId);
          for (final account in event.members) {
            await _store.forgetMember(groupId, account);
          }
          if (update != null) {
            await _notices.add(
              groupId: groupId,
              kind: event.change == RosterChangeKind.left
                  ? GroupNoticeKinds.left
                  : GroupNoticeKinds.removed,
              actor: event.actor,
              members: event.members,
              messageId: envelope.id,
              at: at,
            );
            await _rekeyDuty(event);
          }
        }
      case RosterChangeKind.created || RosterChangeKind.added:
        final update = await _roster.refreshForInbound(groupId);
        if (update != null) {
          final joined =
              event.actor != null && event.members.contains(event.actor);
          await _notices.add(
            groupId: groupId,
            kind: event.change == RosterChangeKind.created
                ? GroupNoticeKinds.created
                : joined
                ? GroupNoticeKinds.joined
                : GroupNoticeKinds.added,
            actor: event.actor,
            members: event.members,
            messageId: envelope.id,
            at: at,
          );
          await _shareKeyDuty(event, update.group.epoch);
        }
      case RosterChangeKind.roleChanged || RosterChangeKind.settingsChanged:
        final update = await _roster.refreshForInbound(groupId);
        if (update != null) {
          await _notices.add(
            groupId: groupId,
            kind: event.change == RosterChangeKind.roleChanged
                ? GroupNoticeKinds.roleChanged
                : GroupNoticeKinds.settingsChanged,
            actor: event.actor,
            members: event.members,
            messageId: envelope.id,
            at: at,
          );
        }
      case RosterChangeKind.stateChanged:
        final update = await _roster.refreshForInbound(groupId);
        if (update != null &&
            update.applied &&
            update.previousTitle != null &&
            update.previousTitle!.isNotEmpty &&
            update.previousTitle != update.group.title) {
          await _notices.add(
            groupId: groupId,
            kind: GroupNoticeKinds.renamed,
            actor: event.actor,
            fields: {'name': update.group.title},
            messageId: envelope.id,
            at: at,
          );
        }
      case RosterChangeKind.joinRequested:
        final account = event.members.firstOrNull ?? event.actor;
        final role = (await _db.groupsDao.selfMembership(groupId))?.role;
        if (account != null &&
            (role == GroupRole.owner.wire || role == GroupRole.admin.wire)) {
          await _notices.add(
            groupId: groupId,
            kind: GroupNoticeKinds.joinRequested,
            actor: account,
            members: [account],
            messageId: envelope.id,
            at: at,
          );
          _ctx.emit(GroupJoinRequested(groupId: groupId, account: account));
        }
      case RosterChangeKind.unknown:
        break;
    }
    return _record(envelope, mark, EnvelopeOutcome.applied);
  }

  /// After someone was added: the member who added them hands over the group
  /// key (the acting device did that when it made the call), and for a link
  /// join, where the joiner added themselves, the first admin by account id
  /// does.
  Future<void> _shareKeyDuty(RosterChangeEvent event, int epoch) async {
    final self = _ctx.identity.accountId;
    final actor = event.actor;
    if (actor == self) return;
    final joiners = event.members.where((m) => m != self).toList();
    if (joiners.isEmpty) return;
    final selfJoin = actor != null && event.members.contains(actor);
    if (!selfJoin && actor != null) return; // The actor shares the key.
    if (!await _isFirstAdmin(event.groupId, exclude: event.members.toSet())) {
      return;
    }
    await _keys.share(event.groupId, joiners, epoch: epoch);
  }

  /// After a removal the server bumped the epoch: the remover rotates the
  /// group key when it made the call; for a leave or a server-side removal
  /// the first admin by account id does.
  Future<void> _rekeyDuty(RosterChangeEvent event) async {
    final actor = event.actor;
    // A member who removed someone (this device included) rotates the key.
    if (actor != null && !event.members.contains(actor)) return;
    if (!await _isFirstAdmin(event.groupId, exclude: event.members.toSet())) {
      return;
    }
    await _outbox.enqueueRekey(event.groupId);
  }

  Future<bool> _isFirstAdmin(
    String groupId, {
    required Set<String> exclude,
  }) async {
    final self = _ctx.identity.accountId;
    final admins = [
      for (final m in await _db.groupsDao.members(groupId))
        if ((m.role == GroupRole.owner.wire ||
                m.role == GroupRole.admin.wire) &&
            !exclude.contains(m.accountId))
          m.accountId,
    ]..sort();
    return admins.isNotEmpty && admins.first == self;
  }
}
