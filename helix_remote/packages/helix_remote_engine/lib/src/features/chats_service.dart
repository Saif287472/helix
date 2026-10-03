import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_engine/src/groups/group_keyring.dart';
import 'package:helix_remote_engine/src/messaging/content_codec.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Chats and messages (direct chats and group chats): lists as watch
/// queries, and every user action as one transaction that writes the
/// optimistic row and the outbox op together (plan §6.3). Sending happens
/// later, in the outbox worker; nothing here touches the network.
///
/// A group chat is the conversation `group:<group id>` (`GroupsService`
/// creates and joins groups); it takes the same actions as a direct chat.
/// A group message is encrypted once for the whole group and sent through
/// the group endpoint; reactions, edits, deletes and votes go the same way,
/// receipts go to their author only.
///
/// Attachments (media content) are sent through `Engine.media` (the transfer
/// queue); this service sends text, replies, mentions, reactions, edits, deletes,
/// receipts, locations, contacts, stickers-free kinds, polls and timer
/// changes, i.e. every content type that needs no blob.
final class ChatsService {
  ChatsService(this._ctx, this._outbox, {required this._onExpiryChanged});

  final EngineContext _ctx;
  final OutboxService _outbox;
  final void Function() _onExpiryChanged;

  HelixDb get _db => _ctx.db;

  /// Retries a failed media message (its uploads, then its send); true when
  /// it was one. Set by the engine; media is sent by `Engine.media`.
  Future<bool> Function(int rowid)? retryMediaHook;

  // ------------------------------------------------------------- reading

  /// The chat list: pinned first, then newest activity.
  Stream<List<ConversationListItem>> watchChats({bool archived = false}) =>
      _db.conversationsDao.watchList(archived: archived);

  /// Badge numbers over the non-archived chats.
  Stream<UnreadTotals> watchUnread() =>
      _db.conversationsDao.watchUnreadTotals();

  Stream<ConversationRow?> watchChat(String conversationId) =>
      _db.conversationsDao.watchById(conversationId);

  /// The newest [limit] messages, oldest first, live.
  Stream<List<MessageRow>> watchMessages(
    String conversationId, {
    int limit = 50,
  }) => _db.messagesDao.watchLatest(conversationId, limit: limit);

  /// One page back in time, for scrolling up.
  Future<MessagePage> pageOlder(
    String conversationId, {
    String? before,
    int limit = 50,
  }) => _db.messagesDao.pageOlder(conversationId, before: before, limit: limit);

  Future<List<ReactionRow>> reactionsOf(Iterable<int> rowids) =>
      _db.messagesDao.reactionsFor(rowids);

  Stream<List<ReactionRow>> watchReactions(Iterable<int> rowids) =>
      _db.messagesDao.watchReactionsFor(rowids);

  Future<List<ReceiptRow>> receiptsOf(int rowid) =>
      _db.messagesDao.receiptsFor(rowid);

  Future<List<AttachmentRow>> attachmentsOf(Iterable<int> rowids) =>
      _db.messagesDao.attachmentsFor(rowids);

  Future<MessageRow?> message(int rowid) => _db.messagesDao.byRowid(rowid);

  /// Full-text search over message text and captions, newest first.
  Future<List<MessageRow>> search(
    String query, {
    String? conversationId,
    int limit = 50,
  }) => _db.messagesDao.search(
    query,
    conversationId: conversationId,
    limit: limit,
  );

  /// The direct chat with [peerAccount], created if missing. There are no
  /// contact requests: anyone can be messaged (AGENTS.md product rules).
  Future<ConversationRow> openDirect(String peerAccount) =>
      _db.transaction(() async {
        final now = _ctx.now();
        await _db.peopleDao.upsertPerson(
          PeopleCompanion.insert(accountId: peerAccount, updatedAt: now),
        );
        return _db.conversationsDao.ensureDirect(peerAccount, now: now);
      });

  // ------------------------------------------------------------- sending

  /// Sends [text] (optionally as a reply, with mentions). Returns the new
  /// row, status `pending` until the outbox worker has sent it.
  Future<MessageRow> sendText(
    String conversationId,
    String text, {
    MessageRef? replyTo,
    List<Mention> mentions = const [],
  }) async {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'is empty');
    }
    if (text.length > ContentLimits.maxTextLength) {
      throw ArgumentError.value(
        '<${text.length} chars>',
        'text',
        'is too long',
      );
    }
    if (mentions.isNotEmpty && GroupIds.isGroupConversation(conversationId)) {
      await _checkMentions(conversationId, text, mentions);
    }
    return _sendVisible(
      conversationId,
      TextBody(text: text, mentions: mentions),
      reply: replyTo,
    );
  }

  /// Mentions in a group name members and point inside the text.
  Future<void> _checkMentions(
    String conversationId,
    String text,
    List<Mention> mentions,
  ) async {
    final members = {
      for (final m in await _db.groupsDao.members(
        GroupIds.groupIdOf(conversationId),
      ))
        m.accountId,
    };
    for (final m in mentions) {
      if (!members.contains(m.account) ||
          m.start < 0 ||
          m.length <= 0 ||
          m.start + m.length > text.length) {
        throw const GroupException(GroupFailure.badMention);
      }
    }
  }

  /// Sends a message of any content type that needs no blob: location,
  /// contact card, poll, event, and so on. (Media goes through
  /// `Engine.media`.)
  Future<MessageRow> sendBody(
    String conversationId,
    ContentBody body, {
    MessageRef? replyTo,
    bool viewOnce = false,
  }) {
    if (!ContentCodec.isMessage(body) ||
        body is MediaBody ||
        body is StickerBody) {
      throw ArgumentError.value(
        body.type,
        'body',
        'is not a message this service sends (media goes through '
            'Engine.media, stickers are not sent yet)',
      );
    }
    return _sendVisible(
      conversationId,
      body,
      reply: replyTo,
      viewOnce: viewOnce,
    );
  }

  Future<MessageRow> _sendVisible(
    String conversationId,
    ContentBody body, {
    MessageRef? reply,
    bool viewOnce = false,
    bool applyTimer = true,
  }) async {
    final row = await _db.transaction(
      () => _writeVisible(conversationId, body, reply, viewOnce, applyTimer),
    );
    // After the commit: the timer reads the table.
    if (row.expiresAt != null) _onExpiryChanged();
    return row;
  }

  Future<MessageRow> _writeVisible(
    String conversationId,
    ContentBody body,
    MessageRef? reply,
    bool viewOnce,
    bool applyTimer,
  ) async {
    final route = await _routeOf(conversationId, sending: true);
    final chat = await _db.conversationsDao.byId(conversationId);
    if (chat == null) throw StateError('no such chat');
    final now = _ctx.now();
    final self = _ctx.identity;
    final expire = applyTimer ? chat.disappearingSeconds : null;
    final profileKey = (await _db.accountDao.current())?.profileKey;
    final content = ContentMessage(
      id: _ctx.ids.next(),
      sentAt: now,
      conversation: route.conversation,
      body: body,
      reply: reply,
      expireSeconds: expire,
      profileKey: profileKey == null ? null : Uint8List.fromList(profileKey),
      viewOnce: viewOnce,
    );
    final stored = ContentCodec.split(body);
    final row = await _db.messagesDao.insertMessage(
      MessagesCompanion.insert(
        messageId: content.id,
        conversationId: conversationId,
        sender: self.accountId,
        senderDevice: Value(self.deviceId),
        outgoing: true,
        sortKey: SortKey.of(now, content.id),
        sentAt: now,
        receivedAt: now,
        kind: body.type,
        body: Value(stored.text),
        payload: Value(stored.payload),
        replyToId: Value(reply?.id),
        replyToAuthor: Value(reply?.author),
        status: MessageStatus.pending,
        expireSeconds: Value(expire),
        // The author sees the message at once, so the timer starts now.
        expiresAt: Value(
          expire == null ? null : now.add(Duration(seconds: expire)),
        ),
        viewOnceState: viewOnce
            ? const Value(ViewOnceState.unopened)
            : const Value.absent(),
      ),
    );
    await _db.conversationsDao.setDraft(conversationId, null);
    await _enqueue(
      route,
      conversationId,
      content,
      messageRowid: row.localRowid,
    );
    return row;
  }

  /// Reacts to a message with [emoji]; `null` removes this account's
  /// reaction. One reaction per account per message.
  Future<void> react(int rowid, String? emoji) => _db.transaction(() async {
    final target = await _requireMessage(rowid);
    if (target.deletedAt != null) return;
    if (emoji != null &&
        (emoji.isEmpty || emoji.length > ContentLimits.maxEmojiLength)) {
      throw ArgumentError.value(emoji, 'emoji');
    }
    final now = _ctx.now();
    final self = _ctx.identity.accountId;
    final current = (await _db.messagesDao.reactionsFor([
      rowid,
    ])).where((r) => r.reactor == self).firstOrNull;
    if (emoji == null && current == null) return;
    if (emoji == null) {
      await _db.messagesDao.removeReaction(rowid, reactor: self);
    } else {
      await _db.messagesDao.setReaction(
        rowid,
        reactor: self,
        emoji: emoji,
        at: now,
      );
    }
    await _sendAction(
      target,
      ReactionBody(
        target: MessageRef(id: target.messageId, author: target.sender),
        emoji: emoji ?? current!.emoji,
        remove: emoji == null,
      ),
    );
  });

  /// Votes in a poll ([optionIds] empty withdraws the vote). Only options of
  /// the poll are accepted.
  Future<void> vote(int rowid, List<String> optionIds) =>
      _db.transaction(() async {
        final poll = await _requireMessage(rowid);
        final body = ContentCodec.join(poll);
        if (body is! PollBody || poll.deletedAt != null) {
          throw StateError('not a poll');
        }
        final options = {for (final o in body.options) o.id};
        if (!optionIds.every(options.contains) ||
            (!body.multiple && optionIds.length > 1)) {
          throw ArgumentError.value(optionIds, 'optionIds');
        }
        await _setAnswer(poll, 'votes', optionIds.isEmpty ? null : optionIds);
        await _sendAction(
          poll,
          PollVoteBody(
            target: MessageRef(id: poll.messageId, author: poll.sender),
            optionIds: optionIds,
          ),
        );
      });

  /// Answers an event invitation.
  Future<void> rsvp(int rowid, RsvpState state, {bool plusOne = false}) =>
      _db.transaction(() async {
        final event = await _requireMessage(rowid);
        if (event.kind != EventBody.typeName || event.deletedAt != null) {
          throw StateError('not an event');
        }
        await _setAnswer(event, 'rsvps', {
          'state': state.wire,
          'plus_one': plusOne,
        });
        await _sendAction(
          event,
          RsvpBody(
            target: MessageRef(id: event.messageId, author: event.sender),
            state: state,
            plusOne: plusOne,
          ),
        );
      });

  /// Records this account's own vote or RSVP in the message's payload (the
  /// same place incoming ones go).
  Future<void> _setAnswer(MessageRow row, String key, Object? answer) async {
    final payload = row.payload == null
        ? <String, Object?>{}
        : (jsonDecode(row.payload!) as Map).cast<String, Object?>();
    final answers = {...(payload[key] as Map? ?? const {})};
    if (answer == null) {
      answers.remove(_ctx.identity.accountId);
    } else {
      answers[_ctx.identity.accountId] = answer;
    }
    await _db.messagesDao.updatePayload(
      row.localRowid,
      jsonEncode({...payload, key: answers}),
    );
  }

  /// Edits the text (or media caption) of an own message within 15 minutes
  /// of sending it (CONTENT_V2.md §3).
  Future<void> edit(int rowid, String text) => _db.transaction(() async {
    final target = await _requireMessage(rowid);
    final now = _ctx.now();
    if (!target.outgoing ||
        target.deletedAt != null ||
        (target.kind != TextBody.typeName &&
            target.kind != MediaBody.typeName) ||
        now.difference(target.sentAt) > ContentLimits.editWindow) {
      throw StateError('this message can no longer be edited');
    }
    if (text.length > ContentLimits.maxTextLength) {
      throw ArgumentError.value(
        '<${text.length} chars>',
        'text',
        'is too long',
      );
    }
    await _db.messagesDao.editMessage(rowid, body: text, editedAt: now);
    final ref = MessageRef(id: target.messageId, author: target.sender);
    await _sendAction(
      target,
      target.kind == MediaBody.typeName
          ? EditBody(target: ref, caption: text)
          : EditBody(target: ref, text: text),
    );
  });

  /// Deletes an own message for everyone within two days.
  Future<void> deleteForEveryone(int rowid) => _db.transaction(() async {
    final target = await _requireMessage(rowid);
    final now = _ctx.now();
    // A group admin may delete anyone's message (CONTENT_V2.md §3).
    final byAdmin =
        !target.outgoing &&
        GroupIds.isGroupConversation(target.conversationId) &&
        await _isGroupAdmin(target.conversationId);
    if ((!target.outgoing && !byAdmin) ||
        target.deletedAt != null ||
        now.difference(target.sentAt) > ContentLimits.deleteWindow) {
      throw StateError('this message can no longer be deleted for everyone');
    }
    await _db.messagesDao.deleteForEveryone(rowid, deletedAt: now);
    await _sendAction(
      target,
      DeleteBody(
        target: MessageRef(id: target.messageId, author: target.sender),
      ),
    );
  });

  /// Removes messages from this device only.
  Future<void> deleteForMe(Iterable<int> rowids) =>
      _db.messagesDao.removeMessages(rowids);

  /// Reads everything in the chat: clears the unread count, sends `read`
  /// receipts to the authors (when the setting allows) and to this
  /// account's other devices so they stop showing the messages as unread.
  Future<void> markRead(String conversationId) => _db.transaction(() async {
    final chat = await _db.conversationsDao.byId(conversationId);
    final newest = chat?.lastMessageSortKey;
    if (chat == null || newest == null) return;
    final read = await _db.messagesDao.markReadUpTo(conversationId, newest);
    if (read.isEmpty) return;
    final toPeer = await _db.settingsDao.get(EngineSettings.sendReadReceipts);
    final self = _ctx.identity.accountId;
    if (GroupIds.isGroupConversation(conversationId)) {
      await _markGroupRead(conversationId, read, sendToAuthors: toPeer);
      return;
    }
    final peer = _peerOf(conversationId);
    final ids = [for (final m in read) m.messageId];
    for (var i = 0; i < ids.length; i += ContentLimits.maxIdsPerReceipt) {
      final chunk = ids.skip(i).take(ContentLimits.maxIdsPerReceipt).toList();
      await _outbox.enqueueContent(
        content: ContentMessage(
          id: _ctx.ids.next(),
          sentAt: _ctx.now(),
          conversation: DirectConversation(to: peer),
          body: ReceiptBody(kind: ReceiptKind.read, ids: chunk),
        ),
        audience: [self, if (toPeer) peer],
        urgent: false,
      );
    }
  });

  /// The user opened a view-once message: it is marked opened and a
  /// `viewed` receipt goes to the author. The app shows the media (through
  /// `Engine.media`) and calls `MediaService.consumeViewOnce` when the viewer
  /// closes, which deletes it.
  Future<void> openViewOnce(int rowid) => _db.transaction(() async {
    final target = await _requireMessage(rowid);
    if (target.viewOnceState != ViewOnceState.unopened) return;
    await _db.messagesDao.setViewOnceState(rowid, ViewOnceState.opened);
    if (target.outgoing) return;
    final route = await _routeOf(target.conversationId);
    await _outbox.enqueueContent(
      content: ContentMessage(
        id: _ctx.ids.next(),
        sentAt: _ctx.now(),
        conversation: route.conversation,
        body: ReceiptBody(kind: ReceiptKind.viewed, ids: [target.messageId]),
      ),
      // In a group the author hears about it, not everyone.
      audience: [route.peer ?? target.sender, _ctx.identity.accountId],
      urgent: false,
    );
  });

  /// Starts the disappearing timer of a message the user just saw (the
  /// timer counts from first display, CONTENT_V2.md §5).
  Future<void> markDisplayed(int rowid) async {
    await _db.messagesDao.markDisplayed(rowid, _ctx.now());
    _onExpiryChanged();
  }

  /// Sets the chat's disappearing-message timer ([seconds] null or 0 turns
  /// it off) and tells the other side with a `system` message.
  Future<void> setDisappearing(String conversationId, int? seconds) =>
      _db.transaction(() async {
        final value = seconds == null || seconds <= 0 ? null : seconds;
        await _db.conversationsDao.setDisappearingSeconds(
          conversationId,
          value,
        );
        await _sendVisible(
          conversationId,
          SystemBody(
            kind: MessageKinds.timerChanged,
            fields: {'seconds': value ?? 0},
          ),
          applyTimer: false,
        );
      });

  /// Puts a failed message back in the queue.
  Future<void> retrySend(int rowid) async {
    if (await retryMediaHook?.call(rowid) ?? false) return;
    for (final op in await _db.outboxDao.forMessage(rowid)) {
      if (op.state == OutboxState.failed) await _outbox.retry(op.id);
    }
  }

  // ----------------------------------------------------------- chat state

  Future<void> setPinned(String id, {required bool pinned}) =>
      _db.conversationsDao.setPinned(id, pinned ? _ctx.now() : null);

  Future<void> setMutedUntil(String id, DateTime? until) =>
      _db.conversationsDao.setMutedUntil(id, until);

  Future<void> setArchived(String id, {required bool archived}) =>
      _db.conversationsDao.setArchived(id, archived);

  Future<void> setDraft(String id, String? draft) =>
      _db.conversationsDao.setDraft(id, draft);

  /// Deletes the chat and its messages from this device.
  Future<void> deleteChat(String id) =>
      _db.conversationsDao.deleteConversation(id);

  // ------------------------------------------------------------- internals

  String _peerOf(String conversationId) {
    const prefix = 'direct:';
    if (!conversationId.startsWith(prefix)) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'is not a direct chat',
      );
    }
    return conversationId.substring(prefix.length);
  }

  /// Where a chat's content goes: the peer of a direct chat, or the group.
  /// [sending] also checks that this account may send to the group (the
  /// server enforces it too; this fails at once, not from the outbox).
  Future<_Route> _routeOf(String conversationId, {bool sending = false}) async {
    if (!GroupIds.isGroupConversation(conversationId)) {
      return _Route.direct(_peerOf(conversationId));
    }
    final groupId = GroupIds.groupIdOf(conversationId);
    final member = await _db.groupsDao.selfMembership(groupId);
    if (member == null) throw const GroupException(GroupFailure.notAMember);
    if (sending && member.role == 'member') {
      final settings = (await GroupKeyring(_ctx).meta(groupId)).settings;
      if (settings.sendMessages == GroupPermission.admins) {
        throw const GroupException(GroupFailure.notAllowed);
      }
    }
    return _Route.group(groupId);
  }

  Future<bool> _isGroupAdmin(String conversationId) async {
    final role = (await _db.groupsDao.selfMembership(
      GroupIds.groupIdOf(conversationId),
    ))?.role;
    return role == 'owner' || role == 'admin';
  }

  Future<void> _enqueue(
    _Route route,
    String conversationId,
    ContentMessage content, {
    int? messageRowid,
    bool urgent = true,
  }) {
    final group = route.groupId;
    if (group != null) {
      return _outbox.enqueueGroupContent(
        content: content,
        groupId: group,
        conversationId: conversationId,
        messageRowid: messageRowid,
        urgent: urgent,
      );
    }
    return _outbox.enqueueContent(
      content: content,
      audience: [route.peer!, _ctx.identity.accountId],
      conversationId: conversationId,
      messageRowid: messageRowid,
      urgent: urgent,
    );
  }

  /// Read receipts of a group chat: this account's other devices learn
  /// everything that was read; each author hears about their own messages
  /// (when the setting allows, and not in a group too large for receipts).
  Future<void> _markGroupRead(
    String conversationId,
    List<MessageRow> read, {
    required bool sendToAuthors,
  }) async {
    final groupId = GroupIds.groupIdOf(conversationId);
    final conversation = GroupConversation(group: groupId);
    final self = _ctx.identity.accountId;
    Future<void> receipt(
      List<MessageRow> messages,
      List<String> audience,
    ) async {
      final ids = [for (final m in messages) m.messageId];
      for (var i = 0; i < ids.length; i += ContentLimits.maxIdsPerReceipt) {
        await _outbox.enqueueContent(
          content: ContentMessage(
            id: _ctx.ids.next(),
            sentAt: _ctx.now(),
            conversation: conversation,
            body: ReceiptBody(
              kind: ReceiptKind.read,
              ids: ids.skip(i).take(ContentLimits.maxIdsPerReceipt).toList(),
            ),
          ),
          audience: audience,
          urgent: false,
        );
      }
    }

    await receipt(read, [self]);
    final size = (await _db.groupsDao.members(groupId)).length;
    if (!sendToAuthors || size > GroupLimits.receiptsMaxMembers) return;
    final byAuthor = <String, List<MessageRow>>{};
    for (final m in read) {
      if (m.sender != self) (byAuthor[m.sender] ??= []).add(m);
    }
    for (final entry in byAuthor.entries) {
      await receipt(entry.value, [entry.key]);
    }
  }

  Future<MessageRow> _requireMessage(int rowid) async {
    final row = await _db.messagesDao.byRowid(rowid);
    if (row == null) throw StateError('no such message');
    return row;
  }

  /// Sends an action on [target]'s chat to the peer and this account's
  /// other devices.
  Future<void> _sendAction(MessageRow target, ContentBody body) async {
    final route = await _routeOf(target.conversationId, sending: true);
    return _enqueue(
      route,
      target.conversationId,
      ContentMessage(
        id: _ctx.ids.next(),
        sentAt: _ctx.now(),
        conversation: route.conversation,
        body: body,
      ),
      // Actions on a message are not worth waking the recipient's phone.
      urgent: false,
    );
  }
}

/// A chat's destination: [peer] for a direct chat, [groupId] for a group.
final class _Route {
  _Route.direct(String this.peer) : groupId = null;

  _Route.group(String this.groupId) : peer = null;

  final String? peer;
  final String? groupId;

  ConversationRef get conversation => groupId != null
      ? GroupConversation(group: groupId!)
      : DirectConversation(to: peer!);
}
