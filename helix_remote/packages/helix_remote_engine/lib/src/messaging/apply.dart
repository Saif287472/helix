import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/backup/inbox.dart';
import 'package:helix_remote_engine/src/calls/call_log_mirror.dart';
import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_engine/src/messaging/content_codec.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_engine/src/transfers/inbound_media.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What applying one content message did.
final class ApplyResult {
  const ApplyResult.applied({this.notice}) : ignoredBecause = null;

  const ApplyResult.ignored(String this.ignoredBecause) : notice = null;

  /// The new message a notification should show, if any.
  final IncomingNotice? notice;

  /// Why the content was dropped without effect (a code, never content).
  final String? ignoredBecause;

  bool get wasIgnored => ignoredBecause != null;
}

enum _Action { done, defer, ignore }

/// The chat a content message belongs to: a direct chat ([peer] is the other
/// person) or a group chat ([group] is its id, [peer] is empty).
typedef _Chat = ({String peer, String id, String? group});

/// Applies decrypted content to the database (plan §6.3 "apply"): the
/// message row (with its summary and FTS entry, kept by the DAO), reactions,
/// receipts, edits, deletes, poll votes, RSVPs, disappearing timers and
/// the control messages that change local state.
///
/// Everything here runs inside the caller's transaction, together with the
/// session state and the `processed_envelopes` row, so an envelope is
/// applied entirely or not at all.
///
/// Direct chats and group chats. Group content (a group `conv`) is applied
/// when it came through the group send (`viaGroup`, which the server checked
/// for membership and the group's send permission), from a member of the
/// stored roster; only receipts may arrive pairwise. Sender keys and group
/// keys are handled by the group pipeline before this runs.
final class ContentApplier {
  ContentApplier(this._ctx, this._outbox, {this._media});

  final EngineContext _ctx;
  final OutboxService _outbox;

  /// Decides what is fetched of an arriving attachment message (auto-download
  /// policy, thumbnails); null when the host has no transfer queue.
  final InboundMedia? _media;

  HelixDb get _db => _ctx.db;

  /// Applies [content] from [sender].
  Future<ApplyResult> apply({
    required DeviceAddress sender,
    required ContentMessage content,
    required DateTime receivedAt,
    bool viaGroup = false,
  }) async {
    final body = content.body;
    final self = _ctx.identity.accountId;

    // Control messages that need no chat.
    switch (body) {
      case ProfileKeyUpdateBody():
        if (sender.account == self) return const ApplyResult.ignored('self');
        await _profileKeyUpdate(sender.account, body, receivedAt);
        return const ApplyResult.applied();
      case ContactSyncBody():
        if (sender.account != self) {
          return const ApplyResult.ignored('not_self');
        }
        await _contactSync(body, receivedAt);
        return const ApplyResult.applied();
      case DecryptionErrorBody():
        await _decryptionError(sender, body, receivedAt);
        return const ApplyResult.applied();
      case ResendRequestBody():
        await _resendRequest(sender, body, receivedAt);
        return const ApplyResult.applied();
      case DeviceTransferOfferBody():
        // Own devices only; recorded here, fetched by the backup feature.
        final recorded = await TransferInbox.apply(
          _ctx,
          sender,
          body,
          receivedAt,
        );
        return recorded
            ? const ApplyResult.applied()
            : const ApplyResult.ignored('transfer_offer');
      case SenderKeyDistributionBody() || GroupKeyBody():
        return const ApplyResult.ignored('group_content');
      case TypingBody():
        return const ApplyResult.ignored('typing_not_stored');
      default:
    }

    final chat = _chatOf(sender.account, content);
    if (chat == null) return const ApplyResult.ignored('misaddressed');
    final group = chat.group;
    if (group != null) {
      final refused = await _groupGate(sender, content, group, viaGroup);
      if (refused != null) return ApplyResult.ignored(refused);
    } else {
      // Notices come from the engine itself, never from a peer's message:
      // the disappearing timer is the one system message that is sent.
      if (body is SystemBody && body.kind != MessageKinds.timerChanged) {
        return const ApplyResult.ignored('system_not_allowed');
      }
      if (sender.account != self) {
        final person = await _db.peopleDao.byAccount(chat.peer);
        if (person?.blocked ?? false) {
          return const ApplyResult.ignored('blocked');
        }
      }
    }

    if (!ContentCodec.isMessage(body) && body.isVisible) {
      // Live location updates and stops: C4 (they have no row of their own).
      return const ApplyResult.ignored('live_location_update');
    }
    if (ContentCodec.isMessage(body)) {
      return _insertMessage(sender, content, chat, receivedAt);
    }
    final applied = await _applyAction(
      senderAccount: sender.account,
      senderDevice: sender.device,
      content: content,
      chat: chat,
      now: receivedAt,
    );
    switch (applied) {
      case _Action.done:
        return const ApplyResult.applied();
      case _Action.ignore:
        return const ApplyResult.ignored('no_effect');
      case _Action.defer:
        await _defer(sender, content, receivedAt);
        return const ApplyResult.applied();
    }
  }

  // ------------------------------------------------------------- chats

  _Chat? _chatOf(String senderAccount, ContentMessage c) {
    final conversation = c.conversation;
    if (conversation is GroupConversation) {
      return (
        peer: '',
        id: GroupIds.conversationId(conversation.group),
        group: conversation.group,
      );
    }
    if (conversation is! DirectConversation) return null;
    final self = _ctx.identity.accountId;
    final fromSelf = senderAccount == self;
    if (!fromSelf && conversation.to != self) return null;
    final peer = conversation.chatPeer(
      sender: senderAccount,
      selfAccount: self,
    );
    if (peer == self) return null;
    return (peer: peer, id: directConversationId(peer), group: null);
  }

  /// Why content for a group chat is refused, or null when it may be
  /// applied.
  Future<String?> _groupGate(
    DeviceAddress sender,
    ContentMessage content,
    String groupId,
    bool viaGroup,
  ) async {
    if (await _db.groupsDao.byId(groupId) == null) return 'unknown_group';
    final self = _ctx.identity.accountId;
    final member = await _db.groupsDao.member(groupId, sender.account);
    if (member == null && sender.account != self) return 'not_a_member';
    final body = content.body;
    // Only receipts may come pairwise: everything else has to go through
    // the group send, where the server enforces membership and the group's
    // send permission.
    if (!viaGroup && body is! ReceiptBody) return 'group_content_not_via_group';
    if (body is SystemBody) {
      // Notices come from the server's roster envelopes, never from a
      // member's message; the disappearing timer is the one setting sent.
      if (body.kind != MessageKinds.timerChanged) return 'system_not_allowed';
      if (!_isAdmin(member?.role)) return 'not_allowed';
    }
    return null;
  }

  bool _isAdmin(String? role) => role == 'owner' || role == 'admin';

  /// The author's clock may be wrong or hostile: a message cannot claim to
  /// be from the future (it would sort below everything forever).
  DateTime _clamp(DateTime sentAt, DateTime now) {
    final limit = now.add(const Duration(minutes: 1));
    return sentAt.isAfter(limit) ? limit : sentAt;
  }

  // ---------------------------------------------------- visible messages

  Future<ApplyResult> _insertMessage(
    DeviceAddress sender,
    ContentMessage content,
    _Chat chat,
    DateTime now,
  ) async {
    final self = _ctx.identity.accountId;
    final fromSelf = sender.account == self;
    final existing = await _db.messagesDao.find(
      content.id,
      sender: sender.account,
    );
    if (existing != null) {
      if (existing.kind != MessageKinds.undecryptable) {
        return const ApplyResult.ignored('duplicate');
      }
      // The re-sent message (CRYPTO_V2.md §13a) replaces its placeholder.
      await _db.messagesDao.removeMessages([existing.localRowid]);
    }
    final group = chat.group;
    if (group != null) {
      final title = (await _db.groupsDao.byId(group))?.title;
      await _db.conversationsDao.ensureGroup(
        chat.id,
        title: title == null || title.isEmpty ? null : title,
        now: now,
      );
    } else {
      await _db.conversationsDao.ensureDirect(chat.peer, now: now);
    }
    // The person this message tells us about: the peer of a direct chat, or
    // the author of a message in a group (not this account's own).
    final person = group == null ? chat.peer : sender.account;
    if (group == null || !fromSelf) {
      await _db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: person,
          updatedAt: now,
          profileKey: !fromSelf && content.profileKey != null
              ? Value(content.profileKey)
              : const Value.absent(),
        ),
      );
    }
    final body = content.body;
    final stored = ContentCodec.split(body);
    final sentAt = _clamp(content.sentAt, now);
    final unsupported = content.isFromNewerVersion;
    final reply = content.reply;
    final row = await _db.messagesDao.insertMessage(
      MessagesCompanion.insert(
        messageId: content.id,
        conversationId: chat.id,
        sender: sender.account,
        senderDevice: Value(sender.device),
        outgoing: fromSelf,
        sortKey: SortKey.of(sentAt, content.id),
        sentAt: sentAt,
        receivedAt: now,
        kind: ContentCodec.storedKind(content),
        body: Value(unsupported ? null : stored.text),
        payload: Value(
          unsupported ? jsonEncode(body.toJson()) : stored.payload,
        ),
        replyToId: Value(reply?.id),
        replyToAuthor: Value(reply?.author),
        mentionsMe: Value(
          body is TextBody && body.mentions.any((m) => m.account == self),
        ),
        status: fromSelf ? MessageStatus.sent : MessageStatus.received,
        expireSeconds: Value(content.expireSeconds),
        viewOnceState: content.viewOnce
            ? const Value(ViewOnceState.unopened)
            : const Value.absent(),
      ),
      media: body is MediaBody && !unsupported
          ? ContentCodec.attachments(body)
          : const [],
    );
    await _media?.onMessageStored(row);
    if (body is SystemBody && body.kind == MessageKinds.timerChanged) {
      final seconds = body.fields['seconds'];
      await _db.conversationsDao.setDisappearingSeconds(
        chat.id,
        seconds is int && seconds > 0 ? seconds : null,
      );
    }
    for (final waiting in await _db.inboxDao.takeDeferred(
      content.id,
      author: sender.account,
    )) {
      await _applyDeferred(waiting, now);
    }
    // A call's log message teaches this device a call it never saw ring.
    final callLog = body is CallLogBody && !unsupported ? body : null;
    final unseenCall =
        callLog != null &&
        await CallLogMirror.record(
          _db,
          peer: chat.peer,
          fromSelf: fromSelf,
          body: callLog,
          sentAt: sentAt,
        );
    if (fromSelf) return const ApplyResult.applied();

    // The author is the sender: this branch only runs for a message that
    // arrived, and the receipt goes back to whoever wrote it.
    await _delivered(chat, content.id, sender.account, now);
    // Only a missed call this device did not see ring alerts the user (one
    // that rang here already did, and the others were answered or declined).
    if (callLog != null &&
        !(unseenCall && callLog.outcome == CallOutcome.missed)) {
      return const ApplyResult.applied();
    }
    await _delivered(chat, content.id, sender.account, now);
    final conversation = await _db.conversationsDao.byId(chat.id);
    final muted = conversation?.mutedUntil;
    return ApplyResult.applied(
      notice: IncomingNotice(
        conversationId: chat.id,
        messageRowid: row.localRowid,
        messageId: row.messageId,
        sender: sender.account,
        kind: row.kind,
        preview: callLog == null
            ? MessagesDao.preview(row)
            : (callLog.media == CallMedia.video
                  ? 'Missed video call'
                  : 'Missed voice call'),
        muted: muted != null && muted.isAfter(now),
        sentAt: row.sentAt,
        mentionsMe: row.mentionsMe,
      ),
    );
  }

  /// A `delivered` receipt for the author (CONTENT_V2.md §3), queued in the
  /// transaction that stored the message. In a group it goes to the author
  /// only, and not at all in a group too large for every member to send
  /// one.
  Future<void> _delivered(
    _Chat chat,
    String messageId,
    String author,
    DateTime now,
  ) async {
    final group = chat.group;
    if (group != null &&
        (await _db.groupsDao.members(group)).length >
            GroupLimits.receiptsMaxMembers) {
      return;
    }
    final receipt = ContentMessage(
      id: _ctx.ids.next(),
      sentAt: now,
      conversation: group == null
          ? DirectConversation(to: chat.peer)
          : GroupConversation(group: group),
      body: ReceiptBody(kind: ReceiptKind.delivered, ids: [messageId]),
    );
    await _outbox.enqueueContent(
      content: receipt,
      audience: [group == null ? chat.peer : author],
      urgent: false,
    );
  }

  // ----------------------------------------------------------- actions

  Future<void> _defer(
    DeviceAddress sender,
    ContentMessage content,
    DateTime now,
  ) async {
    final target = _targetOf(content.body)!;
    await _db.inboxDao.deferAction(
      DeferredActionsCompanion.insert(
        targetMessageId: target.id,
        targetAuthor: target.author,
        sender: sender.account,
        senderDevice: Value(sender.device),
        kind: content.body.type,
        payload: jsonEncode(content.toJson()),
        receivedAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      ),
    );
  }

  Future<void> _applyDeferred(DeferredActionRow waiting, DateTime now) async {
    final ContentMessage content;
    try {
      content = ContentMessage.decode(utf8.encode(waiting.payload));
    } on FormatException {
      return;
    }
    final chat = _chatOf(waiting.sender, content);
    if (chat == null) return;
    await _applyAction(
      senderAccount: waiting.sender,
      senderDevice: waiting.senderDevice,
      content: content,
      chat: chat,
      now: now,
    );
  }

  MessageRef? _targetOf(ContentBody body) => switch (body) {
    ReactionBody() => body.target,
    EditBody() => body.target,
    DeleteBody() => body.target,
    PollVoteBody() => body.target,
    RsvpBody() => body.target,
    _ => null,
  };

  Future<_Action> _applyAction({
    required String senderAccount,
    required String? senderDevice,
    required ContentMessage content,
    required _Chat chat,
    required DateTime now,
  }) async {
    final body = content.body;
    if (body is ReceiptBody) {
      await _receipt(senderAccount, body, content, chat, now);
      return _Action.done;
    }
    final ref = _targetOf(body);
    if (ref == null) return _Action.ignore;
    final target = await _db.messagesDao.find(ref.id, sender: ref.author);
    if (target == null) return _Action.defer;
    if (target.conversationId != chat.id) return _Action.ignore;
    final at = _clamp(content.sentAt, now);
    switch (body) {
      case ReactionBody():
        if (target.deletedAt != null) return _Action.ignore;
        return _reaction(target, senderAccount, body, at);
      case EditBody():
        return _edit(target, senderAccount, body, at);
      case DeleteBody():
        // A group admin may delete anyone's message (CONTENT_V2.md §3).
        final group = chat.group;
        final admin =
            group != null &&
            _isAdmin((await _db.groupsDao.member(group, senderAccount))?.role);
        return _delete(target, senderAccount, at, now, byAdmin: admin);
      case PollVoteBody():
        return _pollVote(target, senderAccount, body);
      case RsvpBody():
        return _rsvp(target, senderAccount, body);
      default:
        return _Action.ignore;
    }
  }

  Future<_Action> _reaction(
    MessageRow target,
    String reactor,
    ReactionBody body,
    DateTime at,
  ) async {
    final current = (await _db.messagesDao.reactionsFor([
      target.localRowid,
    ])).where((r) => r.reactor == reactor).firstOrNull;
    // The newest reaction wins when they arrive out of order.
    if (current != null && current.reactedAt.isAfter(at)) return _Action.ignore;
    if (body.remove) {
      await _db.messagesDao.removeReaction(target.localRowid, reactor: reactor);
    } else {
      await _db.messagesDao.setReaction(
        target.localRowid,
        reactor: reactor,
        emoji: body.emoji,
        at: at,
      );
    }
    return _Action.done;
  }

  Future<_Action> _edit(
    MessageRow target,
    String editor,
    EditBody body,
    DateTime at,
  ) async {
    // Only the author edits, within 15 minutes of the original, and only
    // the text of text and media messages (CONTENT_V2.md §3).
    if (target.sender != editor || target.deletedAt != null) {
      return _Action.ignore;
    }
    if (at.difference(target.sentAt) > ContentLimits.editWindow) {
      return _Action.ignore;
    }
    if (target.editedAt != null && !at.isAfter(target.editedAt!)) {
      return _Action.ignore;
    }
    final String? text;
    switch (target.kind) {
      case 'text':
        text = body.text;
      case 'media':
        text = body.caption;
      default:
        return _Action.ignore;
    }
    if (text == null) return _Action.ignore;
    await _db.messagesDao.editMessage(
      target.localRowid,
      body: text,
      editedAt: at,
    );
    return _Action.done;
  }

  Future<_Action> _delete(
    MessageRow target,
    String deleter,
    DateTime at,
    DateTime now, {
    bool byAdmin = false,
  }) async {
    if ((target.sender != deleter && !byAdmin) || target.deletedAt != null) {
      return _Action.ignore;
    }
    if (at.difference(target.sentAt) > ContentLimits.deleteWindow) {
      return _Action.ignore;
    }
    await _db.messagesDao.deleteForEveryone(target.localRowid, deletedAt: now);
    return _Action.done;
  }

  Future<_Action> _pollVote(
    MessageRow target,
    String voter,
    PollVoteBody body,
  ) async {
    if (target.kind != PollBody.typeName || target.deletedAt != null) {
      return _Action.ignore;
    }
    final payload = _payloadOf(target);
    final options = {
      for (final o in (payload['options'] as List? ?? const []))
        if (o is Map && o['id'] is String) o['id'] as String,
    };
    if (!body.optionIds.every(options.contains)) return _Action.ignore;
    final votes = {...(payload['votes'] as Map? ?? const {})};
    if (body.optionIds.isEmpty) {
      votes.remove(voter);
    } else {
      votes[voter] = body.optionIds;
    }
    await _db.messagesDao.updatePayload(
      target.localRowid,
      jsonEncode({...payload, 'votes': votes}),
    );
    return _Action.done;
  }

  Future<_Action> _rsvp(MessageRow target, String who, RsvpBody body) async {
    if (target.kind != EventBody.typeName || target.deletedAt != null) {
      return _Action.ignore;
    }
    final payload = _payloadOf(target);
    final rsvps = {...(payload['rsvps'] as Map? ?? const {})};
    rsvps[who] = {'state': body.state.wire, 'plus_one': body.plusOne};
    await _db.messagesDao.updatePayload(
      target.localRowid,
      jsonEncode({...payload, 'rsvps': rsvps}),
    );
    return _Action.done;
  }

  Map<String, Object?> _payloadOf(MessageRow row) {
    try {
      return (jsonDecode(row.payload ?? '{}') as Map).cast<String, Object?>();
    } on Object {
      return {};
    }
  }

  Future<void> _receipt(
    String senderAccount,
    ReceiptBody body,
    ContentMessage content,
    _Chat chat,
    DateTime now,
  ) async {
    final self = _ctx.identity.accountId;
    final at = _clamp(content.sentAt, now);
    final group = chat.group;
    if (group != null) {
      await _groupReceipt(senderAccount, body, chat, group, at);
      return;
    }
    if (senderAccount != self) {
      // The peer reports on messages this account sent.
      for (final id in body.ids) {
        final message = await _db.messagesDao.find(id, sender: self);
        if (message == null || message.conversationId != chat.id) continue;
        await _db.messagesDao.recordReceipt(
          message.localRowid,
          account: senderAccount,
          kind: body.kind,
          at: at,
        );
        await _db.messagesDao.advanceStatus(
          message.localRowid,
          switch (body.kind) {
            ReceiptKind.delivered => MessageStatus.delivered,
            ReceiptKind.read => MessageStatus.read,
            ReceiptKind.viewed => MessageStatus.viewed,
          },
        );
      }
      return;
    }
    // This account's other device read messages: keep "read" in sync.
    if (body.kind == ReceiptKind.delivered) return;
    String? newest;
    for (final id in body.ids) {
      final message = await _db.messagesDao.find(id, sender: chat.peer);
      if (message == null || message.conversationId != chat.id) continue;
      if (newest == null || message.sortKey.compareTo(newest) > 0) {
        newest = message.sortKey;
      }
    }
    if (newest != null) await _db.messagesDao.markReadUpTo(chat.id, newest);
  }

  /// A receipt in a group chat. A member reports on a message this account
  /// sent: the message moves to `delivered` or `read` once every member that
  /// was in the group when it was sent has reported, so the ticks mean
  /// "everyone". This account's own other device reports reads: they are
  /// kept in sync.
  Future<void> _groupReceipt(
    String senderAccount,
    ReceiptBody body,
    _Chat chat,
    String groupId,
    DateTime at,
  ) async {
    final self = _ctx.identity.accountId;
    if (senderAccount == self) {
      if (body.kind == ReceiptKind.delivered) return;
      String? newest;
      for (final id in body.ids) {
        final message = await _db.messagesDao.findInConversation(chat.id, id);
        if (message == null || message.outgoing) continue;
        if (newest == null || message.sortKey.compareTo(newest) > 0) {
          newest = message.sortKey;
        }
      }
      if (newest != null) await _db.messagesDao.markReadUpTo(chat.id, newest);
      return;
    }
    for (final id in body.ids) {
      final message = await _db.messagesDao.find(id, sender: self);
      if (message == null || message.conversationId != chat.id) continue;
      await _db.messagesDao.recordReceipt(
        message.localRowid,
        account: senderAccount,
        kind: body.kind,
        at: at,
      );
      await _advanceGroupStatus(message, groupId);
    }
  }

  Future<void> _advanceGroupStatus(MessageRow message, String groupId) async {
    final self = _ctx.identity.accountId;
    final audience = [
      for (final m in await _db.groupsDao.members(groupId))
        if (m.accountId != self &&
            !(m.joinedAt?.isAfter(message.sentAt) ?? false))
          m.accountId,
    ];
    if (audience.isEmpty) return;
    final receipts = {
      for (final r in await _db.messagesDao.receiptsFor(message.localRowid))
        r.accountId: r,
    };
    bool everyone(bool Function(ReceiptRow r) reached) => audience.every((a) {
      final r = receipts[a];
      return r != null && reached(r);
    });
    final MessageStatus? status;
    if (everyone((r) => r.viewedAt != null)) {
      status = MessageStatus.viewed;
    } else if (everyone((r) => r.readAt != null || r.viewedAt != null)) {
      status = MessageStatus.read;
    } else if (everyone(
      (r) => r.deliveredAt != null || r.readAt != null || r.viewedAt != null,
    )) {
      status = MessageStatus.delivered;
    } else {
      status = null;
    }
    if (status != null) {
      await _db.messagesDao.advanceStatus(message.localRowid, status);
    }
  }

  // ------------------------------------------------- control messages

  Future<void> _profileKeyUpdate(
    String account,
    ProfileKeyUpdateBody body,
    DateTime now,
  ) => _db.peopleDao.upsertPerson(
    PeopleCompanion.insert(
      accountId: account,
      updatedAt: now,
      profileKey: Value(body.key),
      profileVersion: Value(body.version),
    ),
  );

  Future<void> _contactSync(ContactSyncBody body, DateTime now) async {
    for (final entry in body.entries) {
      await _db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: entry.account,
          updatedAt: now,
          nickname: Value(entry.nickname),
        ),
      );
    }
  }

  /// A device could not decrypt a message of this one (CRYPTO_V2.md §13a):
  /// send it again, over the new session, if it is recent.
  Future<void> _decryptionError(
    DeviceAddress sender,
    DecryptionErrorBody body,
    DateTime now,
  ) async {
    if (body.senderDevice != _ctx.identity.deviceId) return;
    await _resend(sender.account, [body.messageId], now, device: sender);
  }

  Future<void> _resendRequest(
    DeviceAddress sender,
    ResendRequestBody body,
    DateTime now,
  ) => _resend(sender.account, body.ids, now, device: sender);

  /// Sends own messages again. [device] is the one that could not read them:
  /// for a group message it gets this device's sender key again with it.
  ///
  /// Anyone can message anyone, and message ids are visible to the server,
  /// so a request is honoured only from a party that was entitled to the
  /// message in the first place ([_mayResend]); anything else is ignored
  /// without an answer, so the requester learns nothing (not even that the
  /// id exists).
  Future<void> _resend(
    String toAccount,
    List<String> messageIds,
    DateTime now, {
    DeviceAddress? device,
  }) async {
    final self = _ctx.identity.accountId;
    final account = await _db.accountDao.current();
    final profileKey = account?.profileKey;
    for (final id in messageIds.take(ContentLimits.maxIdsPerReceipt)) {
      final row = await _db.messagesDao.find(id, sender: self);
      if (row == null ||
          row.deletedAt != null ||
          !row.outgoing ||
          now.difference(row.sentAt) > _ctx.config.resendWindow) {
        continue;
      }
      if (!await _mayResend(row, toAccount)) continue;
      if (GroupIds.isGroupConversation(row.conversationId)) {
        final groupId = GroupIds.groupIdOf(row.conversationId);
        if (device == null) continue;
        await _outbox.enqueueGroupContent(
          content: ContentCodec.rebuild(
            row,
            to: toAccount,
            conversation: GroupConversation(group: groupId),
            profileKey: profileKey == null
                ? null
                : Uint8List.fromList(profileKey),
          ),
          groupId: groupId,
          conversationId: row.conversationId,
          requestId: _ctx.ids.next(),
          redistribute: [device],
        );
        continue;
      }
      final peer = row.conversationId.substring('direct:'.length);
      // The failing device may belong to the peer or to this account's other
      // devices; either way the whole account is addressed (the server
      // needs every device of a listed account) and devices that already
      // have the message drop the duplicate.
      final content = ContentCodec.rebuild(
        row,
        to: peer,
        profileKey: profileKey == null ? null : Uint8List.fromList(profileKey),
      );
      await _outbox.enqueueContent(
        content: content,
        audience: [toAccount],
        conversationId: row.conversationId,
        requestId: _ctx.ids.next(),
      );
    }
  }

  /// Whether [requester] may have the own message [row] sent again.
  ///
  /// A direct message: only the chat's peer (not blocked) or one of this
  /// account's own devices. A group message: this account's own devices, or a
  /// current member that is neither banned nor blocked and that joined at or
  /// before the message was sent (a member added later cannot pull the
  /// history before it joined; a missing join time counts as "not entitled").
  Future<bool> _mayResend(MessageRow row, String requester) async {
    final self = _ctx.identity.accountId;
    if (requester == self) return true;
    if ((await _db.peopleDao.byAccount(requester))?.blocked ?? false) {
      return false;
    }
    if (GroupIds.isGroupConversation(row.conversationId)) {
      final groupId = GroupIds.groupIdOf(row.conversationId);
      final member = await _db.groupsDao.member(groupId, requester);
      final joined = member?.joinedAt;
      return member != null &&
          joined != null &&
          !joined.isAfter(row.sentAt) &&
          !await _db.groupsDao.isBanned(groupId, requester);
    }
    return row.conversationId == directConversationId(requester);
  }
}
