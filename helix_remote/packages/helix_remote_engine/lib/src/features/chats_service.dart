import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/messaging/content_codec.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Chats and messages (direct chats in C3b): lists as watch queries, and
/// every user action as one transaction that writes the optimistic row and
/// the outbox op together (plan §6.3). Sending happens later, in the
/// outbox worker; nothing here touches the network.
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
  }) {
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
    return _sendVisible(
      conversationId,
      TextBody(text: text, mentions: mentions),
      reply: replyTo,
    );
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
    final peer = _peerOf(conversationId);
    final chat = await _db.conversationsDao.byId(conversationId);
    if (chat == null) throw StateError('no such chat');
    final now = _ctx.now();
    final self = _ctx.identity;
    final expire = applyTimer ? chat.disappearingSeconds : null;
    final profileKey = (await _db.accountDao.current())?.profileKey;
    final content = ContentMessage(
      id: _ctx.ids.next(),
      sentAt: now,
      conversation: DirectConversation(to: peer),
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
    await _outbox.enqueueContent(
      content: content,
      audience: [peer, self.accountId],
      conversationId: conversationId,
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
    if (!target.outgoing ||
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
    final peer = _peerOf(conversationId);
    final toPeer = await _db.settingsDao.get(EngineSettings.sendReadReceipts);
    final self = _ctx.identity.accountId;
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
    final peer = _peerOf(target.conversationId);
    await _outbox.enqueueContent(
      content: ContentMessage(
        id: _ctx.ids.next(),
        sentAt: _ctx.now(),
        conversation: DirectConversation(to: peer),
        body: ReceiptBody(kind: ReceiptKind.viewed, ids: [target.messageId]),
      ),
      audience: [peer, _ctx.identity.accountId],
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
        'is not a direct chat (groups arrive in C4)',
      );
    }
    return conversationId.substring(prefix.length);
  }

  Future<MessageRow> _requireMessage(int rowid) async {
    final row = await _db.messagesDao.byRowid(rowid);
    if (row == null) throw StateError('no such message');
    return row;
  }

  /// Sends an action on [target]'s chat to the peer and this account's
  /// other devices.
  Future<void> _sendAction(MessageRow target, ContentBody body) {
    final peer = _peerOf(target.conversationId);
    return _outbox.enqueueContent(
      content: ContentMessage(
        id: _ctx.ids.next(),
        sentAt: _ctx.now(),
        conversation: DirectConversation(to: peer),
        body: body,
      ),
      audience: [peer, _ctx.identity.accountId],
      conversationId: target.conversationId,
      // Actions on a message are not worth waking the recipient's phone.
      urgent: false,
    );
  }
}
