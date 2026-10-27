import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_engine/src/groups/group_keyring.dart';
import 'package:helix_remote_engine/src/groups/group_ops.dart';
import 'package:helix_remote_engine/src/messaging/content_codec.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// An action (a reaction, an edit, a delete, a vote, an RSVP) whose send
/// failed for good (AUD-12i-1). The op itself stays in the outbox; the chat
/// draws the failure under [targetRowid]'s message and
/// [ChatsService.retryAction] puts it back in the queue. A failed action
/// changes nothing about the message's own status: the local effect (the
/// edited text, the deleted row, the reaction) is already applied.
final class FailedAction {
  const FailedAction({
    required this.opId,
    required this.targetRowid,
    required this.action,
    required this.errorCode,
  });

  final int opId;

  /// The local row of the message the action is about.
  final int targetRowid;

  /// The content body type (`reaction`, `edit`, `delete`, `pin`, `poll_vote`,
  /// `rsvp`), for the chat's words.
  final String action;

  /// Why the last attempt failed (`forbidden`, `expired`, ...).
  final String errorCode;
}

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

  /// Up to [limit] messages from [fromSortKey] (inclusive) onwards, oldest
  /// first, live: a window the user jumped to (a search hit, a quoted
  /// message, the first unread one).
  Stream<List<MessageRow>> watchMessagesFrom(
    String conversationId,
    String fromSortKey, {
    int limit = 100,
  }) => _db.messagesDao.watchFrom(conversationId, fromSortKey, limit: limit);

  /// The reactions on the messages from [fromSortKey] onwards, live.
  Stream<List<ReactionRow>> watchReactionsSince(
    String conversationId,
    String fromSortKey,
  ) => _db.messagesDao.watchReactionsSince(conversationId, fromSortKey);

  /// The attachments of [rowids], live (transfer state, local paths).
  Stream<List<AttachmentRow>> watchAttachments(Iterable<int> rowids) =>
      _db.messagesDao.watchAttachmentsFor(rowids);

  /// The photos, videos and files of [conversationId], newest first, live
  /// (the shared-media view).
  Stream<List<SharedAttachment>> watchSharedAttachments(
    String conversationId, {
    int limit = 500,
  }) => _db.messagesDao.watchSharedAttachments(conversationId, limit: limit);

  /// The messages of [conversationId] that hold a web link, newest first,
  /// live.
  Stream<List<MessageRow>> watchMessagesWithLinks(
    String conversationId, {
    int limit = 200,
  }) => _db.messagesDao.watchMessagesWithLinks(conversationId, limit: limit);

  /// The GIFs on this device, newest first, one per file: the GIF tray.
  Future<List<AttachmentRow>> recentGifs({int limit = 60}) =>
      _db.messagesDao.recentGifs(limit: limit);

  /// A message of [conversationId] by its content id, whoever wrote it (a
  /// reply quote or a read receipt names it that way).
  Future<MessageRow?> findMessage(String conversationId, String messageId) =>
      _db.messagesDao.findInConversation(conversationId, messageId);

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
  /// contact requests: anyone can be messaged (AGENTS.md product rules). This
  /// account's own id is the note-to-self chat, which needs no people row.
  Future<ConversationRow> openDirect(String peerAccount) =>
      _db.transaction(() async {
        final now = _ctx.now();
        final self = _ctx.isSignedIn ? _ctx.identity.accountId : null;
        if (peerAccount != self) {
          await _db.peopleDao.upsertPerson(
            PeopleCompanion.insert(accountId: peerAccount, updatedAt: now),
          );
        }
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
    LinkPreview? linkPreview,
  }) async {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'is empty');
    }
    // A preview is of a link the message holds: one for an address that is not
    // in the text would be a card the sender never showed.
    if (linkPreview != null && !text.contains(linkPreview.url)) {
      throw ArgumentError.value(
        linkPreview.url,
        'linkPreview',
        'is not in text',
      );
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
      TextBody(text: text, mentions: mentions, linkPreview: linkPreview),
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
    String? id,
  }) async {
    final row = await _db.transaction(
      () =>
          _writeVisible(conversationId, body, reply, viewOnce, applyTimer, id),
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
    String? presetId,
  ) async {
    final route = await _routeOf(conversationId, sending: true);
    final chat = await _db.conversationsDao.byId(conversationId);
    if (chat == null) throw StateError('no such chat');
    final now = _ctx.now();
    final self = _ctx.identity;
    final expire = applyTimer ? chat.disappearingSeconds : null;
    final profileKey = (await _db.accountDao.current())?.profileKey;
    final content = ContentMessage(
      id: presetId ?? _ctx.ids.next(),
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

  /// Longest a live location may be shared for.
  static const maxLiveShare = Duration(hours: 8);

  /// Starts sharing a live location in [conversationId] until now + [duration].
  /// The message is the share's `start`; its id is the session id that every
  /// update and the stop name. Throws [ArgumentError] for a duration that is
  /// not positive or is over [maxLiveShare].
  Future<MessageRow> startLiveLocation(
    String conversationId, {
    required int latE7,
    required int lngE7,
    required int accuracyM,
    required Duration duration,
  }) {
    if (duration <= Duration.zero || duration > maxLiveShare) {
      throw ArgumentError.value(duration, 'duration');
    }
    final id = _ctx.ids.next();
    return _sendVisible(
      conversationId,
      LiveLocationBody(
        sessionId: id,
        state: LiveLocationState.start,
        latE7: latE7,
        lngE7: lngE7,
        accuracyM: accuracyM,
        expiresAt: _ctx.now().add(duration),
      ),
      id: id,
    );
  }

  /// Sends the next position of the share in message [rowid]. Returns `false`
  /// (and sends nothing) when the share is not this account's, or has ended.
  Future<bool> updateLiveLocation(
    int rowid, {
    required int latE7,
    required int lngE7,
    required int accuracyM,
  }) => _db.transaction(() async {
    final target = await _db.messagesDao.byRowid(rowid);
    final now = _ctx.now();
    if (target == null ||
        !target.outgoing ||
        target.kind != LiveLocationBody.typeName ||
        !isLiveLocationActive(target.payload, now)) {
      return false;
    }
    final payload = jsonDecode(target.payload!) as Map<String, Object?>;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      payload['expires_at']! as int,
      isUtc: true,
    );
    await _db.messagesDao.updatePayload(
      rowid,
      jsonEncode({
        ...payload,
        'state': 'update',
        'lat_e7': latE7,
        'lng_e7': lngE7,
        'accuracy_m': accuracyM,
        'updated_at': now.millisecondsSinceEpoch,
      }),
    );
    await _sendAction(
      target,
      LiveLocationBody(
        sessionId: target.messageId,
        state: LiveLocationState.update,
        latE7: latE7,
        lngE7: lngE7,
        accuracyM: accuracyM,
        expiresAt: expiresAt,
      ),
    );
    return true;
  });

  /// Ends the share in message [rowid]: the place leaves this device's copy
  /// and the people in the chat are told. Does nothing for a share that is not
  /// this account's or has ended already.
  Future<void> stopLiveLocation(int rowid) => _db.transaction(() async {
    final target = await _db.messagesDao.byRowid(rowid);
    final now = _ctx.now();
    if (target == null ||
        !target.outgoing ||
        target.kind != LiveLocationBody.typeName ||
        !isLiveLocationActive(target.payload, now)) {
      return;
    }
    final payload = jsonDecode(target.payload!) as Map<String, Object?>;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      payload['expires_at']! as int,
      isUtc: true,
    );
    await _db.messagesDao.updatePayload(
      rowid,
      liveLocationEnd(jsonEncode({...payload, 'state': 'stop'}), now),
    );
    await _sendAction(
      target,
      LiveLocationBody(
        sessionId: target.messageId,
        state: LiveLocationState.stop,
        latE7: 0,
        lngE7: 0,
        accuracyM: 0,
        expiresAt: expiresAt,
      ),
    );
  });

  /// The shares this account still has running, for resuming them after the
  /// app restarts.
  Future<List<MessageRow>> activeLiveShares() =>
      _db.messagesDao.activeLiveShares(_ctx.now());

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

  // ---------------------------------------------- stars, pins, favourites

  /// Stars a message, or takes the star off. A star is a private bookmark:
  /// nothing is sent, and a deleted message cannot be starred.
  Future<void> setStarred(int rowid, {required bool starred}) async {
    final row = await _requireMessage(rowid);
    if (row.deletedAt != null) return;
    await _db.messagesDao.setStarred(rowid, starred ? _ctx.now() : null);
  }

  /// The starred messages of every chat, the newest star first, live.
  Stream<List<MessageRow>> watchStarred({int limit = 500}) =>
      _db.messagesDao.watchStarred(limit: limit);

  /// The most messages one chat keeps pinned at once.
  static const maxPinnedMessages = 3;

  /// The messages pinned in [conversationId], the newest pin first, live.
  Stream<List<MessageRow>> watchPinned(String conversationId) =>
      _db.messagesDao.watchPinned(conversationId);

  /// Pins a message in its chat for everyone in it, or takes the pin off
  /// (`pin` content, CONTENT_V2.md §3). A chat keeps at most
  /// [maxPinnedMessages]: pinning one more throws [EngineStateException], and
  /// the person unpins one first. A deleted message cannot be pinned.
  Future<void> pinMessage(int rowid, {required bool pinned}) =>
      _db.transaction(() async {
        final target = await _requireMessage(rowid);
        if (target.deletedAt != null) return;
        if ((target.pinnedAt != null) == pinned) return;
        if (pinned) {
          final held = await _db.messagesDao.pinnedIn(target.conversationId);
          if (held.length >= maxPinnedMessages) {
            throw const EngineStateException(
              'a chat keeps at most $maxPinnedMessages pinned messages',
            );
          }
        }
        await _db.messagesDao.setPinned(rowid, pinned ? _ctx.now() : null);
        await _sendAction(
          target,
          PinBody(
            target: MessageRef(id: target.messageId, author: target.sender),
            remove: !pinned,
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

  /// Removes messages from this device only. A message still queued for
  /// sending is cancelled with it (AUD-12i-2): deleting is the only removal
  /// offered on an unsent message, and it must not deliver it later. And it is
  /// recorded as deleted here, so a backup merge - a restore, or the catch-up
  /// inside an ordinary backup - does not bring it back (AUD-12q-1).
  Future<void> deleteForMe(Iterable<int> rowids) => _db.transaction(() async {
    final ids = rowids.toSet();
    if (ids.isEmpty) return;
    await _discardQueuedActionsAbout(ids);
    await _db.tombstonesDao.recordMessages(ids);
    await _db.messagesDao.removeMessages(ids);
  });

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

  /// The actions of [conversationId] that failed for good, newest first,
  /// live. Unlike a message (whose row turns `failed`), an action leaves no
  /// row to read, so the op in the outbox is what the chat shows the retry
  /// for.
  Stream<List<FailedAction>> watchFailedActions(String conversationId) =>
      _db.outboxDao.watchForConversation(conversationId).map(_failedActionsOf);

  /// [watchFailedActions], read once.
  Future<List<FailedAction>> failedActions(String conversationId) async =>
      _failedActionsOf(await _db.outboxDao.forConversation(conversationId));

  /// Puts a failed action back in the queue (the retry under its message).
  Future<void> retryAction(int opId) => _outbox.retry(opId);

  // ----------------------------------------------------------- chat state

  Future<void> setPinned(String id, {required bool pinned}) =>
      _db.conversationsDao.setPinned(id, pinned ? _ctx.now() : null);

  /// Makes the chat a favourite, or not one: a private filter on the chat
  /// list, never sent.
  Future<void> setFavourite(String id, {required bool favourite}) =>
      _db.conversationsDao.setFavourite(id, favourite ? _ctx.now() : null);

  // ------------------------------------------------------------- lists

  /// The most lists a person keeps, and the longest a list's name is.
  static const maxChatLists = 10;
  static const maxChatListName = 24;

  /// The person's lists, in the order of their chips, live. Private to this
  /// device: a list is never sent.
  Stream<List<ChatListRow>> watchChatLists() =>
      _db.conversationsDao.watchLists();

  /// Which chats are on which list, live.
  Stream<List<ChatListMemberRow>> watchChatListMembers() =>
      _db.conversationsDao.watchListMembers();

  /// Makes a list called [name] (trimmed). Throws [ArgumentError] for an empty
  /// or too long name and [EngineStateException] for a name already used
  /// (case aside) or when [maxChatLists] exist. Returns the new list's id.
  Future<String> createChatList(String name) => _db.transaction(() async {
    final clean = _listName(name);
    final lists = await _db.conversationsDao.lists();
    if (lists.length >= maxChatLists) {
      throw const EngineStateException('there are already too many lists');
    }
    _requireFreeName(lists, clean, except: null);
    final id = _ctx.ids.next();
    await _db.conversationsDao.createList(id, clean, _ctx.now());
    return id;
  });

  /// Renames a list, under the same rules as [createChatList].
  Future<void> renameChatList(String id, String name) =>
      _db.transaction(() async {
        final clean = _listName(name);
        _requireFreeName(await _db.conversationsDao.lists(), clean, except: id);
        await _db.conversationsDao.renameList(id, clean);
      });

  /// Deletes a list. Its chats stay; they just leave it.
  Future<void> deleteChatList(String id) => _db.conversationsDao.deleteList(id);

  /// Puts the chats on a list, or takes them off it.
  Future<void> setChatsOnList(
    String listId,
    Iterable<String> conversationIds, {
    required bool member,
  }) => _db.transaction(() async {
    for (final id in conversationIds) {
      if (member) {
        await _db.conversationsDao.addToList(listId, id);
      } else {
        await _db.conversationsDao.removeFromList(listId, id);
      }
    }
  });

  String _listName(String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > maxChatListName) {
      throw ArgumentError.value(name, 'name', 'must be 1-$maxChatListName');
    }
    return clean;
  }

  void _requireFreeName(
    List<ChatListRow> lists,
    String name, {
    required String? except,
  }) {
    final lowered = name.toLowerCase();
    if (lists.any((l) => l.id != except && l.name.toLowerCase() == lowered)) {
      throw const EngineStateException('a list with that name exists');
    }
  }

  Future<void> setMutedUntil(String id, DateTime? until) =>
      _db.conversationsDao.setMutedUntil(id, until);

  Future<void> setArchived(String id, {required bool archived}) =>
      _db.conversationsDao.setArchived(id, archived);

  Future<void> setDraft(String id, String? draft) =>
      _db.conversationsDao.setDraft(id, draft);

  /// Removes every message of the chat from this device; the chat stays. The
  /// chat is recorded as cleared here, so no backup merge fills it again
  /// (AUD-12q-1); what arrives from now on is kept as usual.
  Future<void> clearChat(String id) async {
    await _db.transaction(() async {
      await _db.tombstonesDao.recordConversation(id);
      await _db.messagesDao.clearConversation(id);
    });
    _onExpiryChanged();
  }

  /// Deletes the chat and its messages from this device; anything still
  /// queued for it is cancelled with it. Recorded as deleted here, so no
  /// backup merge creates it again (AUD-12q-1).
  Future<void> deleteChat(String id) => _db.transaction(() async {
    await _db.outboxDao.cancelForConversation(id);
    await _db.tombstonesDao.recordConversation(id);
    await _db.conversationsDao.deleteConversation(id);
  });

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
    int? targetRowid,
    bool urgent = true,
  }) {
    final group = route.groupId;
    if (group != null) {
      return _outbox.enqueueGroupContent(
        content: content,
        groupId: group,
        conversationId: conversationId,
        messageRowid: messageRowid,
        targetRowid: targetRowid,
        urgent: urgent,
      );
    }
    return _outbox.enqueueContent(
      content: content,
      audience: [route.peer!, _ctx.identity.accountId],
      conversationId: conversationId,
      messageRowid: messageRowid,
      targetRowid: targetRowid,
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
  /// other devices. The op names [target] in its payload so a terminal
  /// failure can be shown on it and retried (AUD-12i-1).
  Future<void> _sendAction(MessageRow target, ContentBody body) async {
    final route = await _routeOf(target.conversationId, sending: true);
    await _discardSuperseded(target, body.type);
    return _enqueue(
      route,
      target.conversationId,
      ContentMessage(
        id: _ctx.ids.next(),
        sentAt: _ctx.now(),
        conversation: route.conversation,
        body: body,
      ),
      targetRowid: target.localRowid,
      // Actions on a message are not worth waking the recipient's phone.
      urgent: false,
    );
  }

  /// Drops queued (pending or failed) actions about messages being removed:
  /// their target will not exist here, so they must neither send nor leave a
  /// failure line behind.
  Future<void> _discardQueuedActionsAbout(Set<int> targets) async {
    final conversations = <String>{};
    for (final id in targets) {
      final row = await _db.messagesDao.byRowid(id);
      if (row != null) conversations.add(row.conversationId);
    }
    for (final conversationId in conversations) {
      for (final op in await _db.outboxDao.forConversation(conversationId)) {
        if (op.messageRowid != null ||
            (op.state != OutboxState.pending &&
                op.state != OutboxState.failed)) {
          continue;
        }
        final target = _actionOf(op)?.targetRowid;
        if (target != null && targets.contains(target)) {
          await _db.outboxDao.discard(op.id);
        }
      }
    }
  }

  /// A new attempt at the same action replaces an earlier failed one: its
  /// failure line would otherwise outlive the fix, and its retry would
  /// re-send an action the person has since redone.
  Future<void> _discardSuperseded(MessageRow target, String action) async {
    final ops = await _db.outboxDao.forConversation(target.conversationId);
    for (final op in ops) {
      if (op.state != OutboxState.failed) continue;
      final failure = _actionOf(op);
      if (failure == null ||
          failure.targetRowid != target.localRowid ||
          failure.action != action) {
        continue;
      }
      await _db.outboxDao.discard(op.id);
    }
  }

  /// The failed actions among [ops], newest first (the query orders them).
  static List<FailedAction> _failedActionsOf(List<OutboxOpRow> ops) {
    final out = <FailedAction>[];
    for (final op in ops) {
      if (op.state != OutboxState.failed) continue;
      final action = _actionOf(op);
      if (action != null) out.add(action);
    }
    return out;
  }

  /// [op] as a failed action, or null when it is not an action op (a
  /// message send, a rekey) or its payload cannot be read.
  static FailedAction? _actionOf(OutboxOpRow op) {
    final ContentMessage content;
    final int? target;
    try {
      if (op.kind == OutboxKinds.sendContent) {
        final payload = SendContentPayload.decode(op.payload);
        content = payload.content;
        target = payload.targetRowid;
      } else if (op.kind == GroupOutboxKinds.sendGroupContent) {
        final payload = SendGroupContentPayload.decode(op.payload);
        content = payload.content;
        target = payload.targetRowid;
      } else {
        return null;
      }
    } on ProtocolFormatException {
      // A corrupt payload has its own failure ('bad_payload'); it names no
      // message to show it on.
      return null;
    }
    if (target == null) return null;
    return FailedAction(
      opId: op.id,
      targetRowid: target,
      action: content.body.type,
      errorCode: op.lastError ?? 'failed',
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
