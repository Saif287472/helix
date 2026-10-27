import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/platform/picker_cleanup.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show
        EventBody,
        Mention,
        MessageRef,
        PollBody,
        PollOption,
        PresenceResponse,
        RsvpState;

/// Everything the chat list and the conversation need from the engine, in one
/// place.
///
/// The two features' `application/` layers read and act through this class
/// instead of reaching into [Engine] themselves, for two reasons. The list of
/// what a chat screen may do is short and worth reading in one file; and a
/// test can replace it with a subclass that keeps the engine's real read
/// queries over an in-memory database but records (and simulates) the writes,
/// which need a signed-in account and a server.
///
/// Reads are the engine's watch queries, unchanged. Nothing here keeps state.
class ChatGateway {
  ChatGateway(this._engine);

  final Engine _engine;

  ChatsService get _chats => _engine.chats;

  /// This account's id, or null before sign-in.
  String? get selfAccountId => _engine.accountId;

  /// Whether this engine can move attachments at all (it has a file store).
  bool get canSendMedia => _engine.media.isAvailable;

  // ------------------------------------------------------------- reading

  Stream<List<ConversationListItem>> watchChats({bool archived = false}) =>
      _chats.watchChats(archived: archived);

  Stream<ConversationRow?> watchChat(String conversationId) =>
      _chats.watchChat(conversationId);

  Future<ConversationRow?> chat(String conversationId) =>
      _chats.watchChat(conversationId).first;

  Stream<List<GroupMemberRow>> watchMembers(String groupId) =>
      _engine.groups.watchMembers(groupId);

  Future<bool> isGroupAdmin(String groupId) async {
    final role = await _engine.groups.role(groupId);
    return role != null && (role.wire == 'owner' || role.wire == 'admin');
  }

  Stream<Map<String, Set<String>>> watchAllTyping() =>
      _engine.presence.watchAllTyping();

  Stream<Set<String>> watchTyping(String conversationId) =>
      _engine.presence.watchTyping(conversationId);

  Stream<List<MessageRow>> watchLatest(String conversationId, int limit) =>
      _chats.watchMessages(conversationId, limit: limit);

  Stream<List<MessageRow>> watchFrom(
    String conversationId,
    String fromSortKey,
    int limit,
  ) => _chats.watchMessagesFrom(conversationId, fromSortKey, limit: limit);

  Future<MessagePage> pageOlder(
    String conversationId, {
    String? before,
    int limit = 50,
  }) => _chats.pageOlder(conversationId, before: before, limit: limit);

  Stream<List<ReactionRow>> watchReactionsSince(
    String conversationId,
    String fromSortKey,
  ) => _chats.watchReactionsSince(conversationId, fromSortKey);

  Stream<List<AttachmentRow>> watchAttachments(int messageRowid) =>
      _chats.watchAttachments([messageRowid]);

  /// The photos, videos and files of a conversation, newest first.
  Stream<List<SharedAttachment>> watchSharedAttachments(
    String conversationId,
  ) => _chats.watchSharedAttachments(conversationId);

  /// The messages of a conversation that hold a web link, newest first.
  Stream<List<MessageRow>> watchMessagesWithLinks(String conversationId) =>
      _chats.watchMessagesWithLinks(conversationId);

  Stream<List<AttachmentTransferView>> watchTransfers(int messageRowid) =>
      _engine.media.watchMessage(messageRowid);

  Future<MessageRow?> message(int rowid) => _chats.message(rowid);

  Future<MessageRow?> findMessage(String conversationId, String messageId) =>
      _chats.findMessage(conversationId, messageId);

  Future<List<ReceiptRow>> receiptsOf(int rowid) => _chats.receiptsOf(rowid);

  Future<List<ReactionRow>> reactionsOf(int rowid) =>
      _chats.reactionsOf([rowid]);

  /// The direct chat with [peerAccount], created if it does not exist.
  Future<String> openDirect(String peerAccount) async =>
      (await _chats.openDirect(peerAccount)).id;

  Future<List<MessageRow>> search(
    String query, {
    String? conversationId,
    int limit = 50,
  }) => _chats.search(query, conversationId: conversationId, limit: limit);

  Future<String?> localPathOf(int attachmentId) =>
      _engine.media.openLocalPath(attachmentId);

  // ----------------------------------------------------------- chat state

  Future<void> setPinned(String id, {required bool pinned}) =>
      _chats.setPinned(id, pinned: pinned);

  Future<void> setMutedUntil(String id, DateTime? until) =>
      _chats.setMutedUntil(id, until);

  Future<void> setArchived(String id, {required bool archived}) =>
      _chats.setArchived(id, archived: archived);

  Future<void> setDraft(String id, String? draft) => _chats.setDraft(id, draft);

  Future<void> deleteChat(String id) => _chats.deleteChat(id);

  Future<void> clearChat(String id) => _chats.clearChat(id);

  Future<void> markRead(String id) => _chats.markRead(id);

  Future<void> setDisappearing(String id, int? seconds) =>
      _chats.setDisappearing(id, seconds);

  /// Votes in a poll: [optionIds] are all your answers now (none takes your
  /// vote back).
  Future<void> vote(int rowid, List<String> optionIds) =>
      _chats.vote(rowid, optionIds);

  /// Answers an event invitation.
  Future<void> rsvp(int rowid, RsvpState state) => _chats.rsvp(rowid, state);

  /// Sends a poll of [options] (two to twelve, already trimmed and different).
  Future<void> sendPoll(
    String conversationId, {
    required String question,
    required List<String> options,
    bool multiple = false,
  }) => _chats.sendBody(
    conversationId,
    PollBody(
      question: question,
      options: [
        for (final (i, text) in options.indexed)
          PollOption(id: 'o${i + 1}', text: text),
      ],
      multiple: multiple,
    ),
  );

  /// Sends an event. The zone is named by its offset from UTC ("UTC+06:00"):
  /// the phone gives no IANA name, and receivers show [startsAt] in their own
  /// time (CONTENT_V2.md).
  Future<void> sendEvent(
    String conversationId, {
    required String title,
    required DateTime startsAt,
    String place = '',
  }) => _chats.sendBody(
    conversationId,
    EventBody(
      title: title,
      startsAt: startsAt,
      timeZone: utcOffsetName(startsAt.timeZoneOffset),
      locationText: place.isEmpty ? null : place,
    ),
  );

  /// Stars a message, or takes the star off: a private bookmark.
  Future<void> setStarred(int rowid, {required bool starred}) =>
      _chats.setStarred(rowid, starred: starred);

  /// The starred messages of every chat, the newest star first.
  Stream<List<MessageRow>> watchStarred() => _chats.watchStarred();

  /// The messages pinned in [conversationId], the newest pin first.
  Stream<List<MessageRow>> watchPinned(String conversationId) =>
      _chats.watchPinned(conversationId);

  /// Pins a message for everyone in its chat, or takes the pin off. Throws
  /// [EngineStateException] when the chat already keeps
  /// [ChatsService.maxPinnedMessages].
  Future<void> pinMessage(int rowid, {required bool pinned}) =>
      _chats.pinMessage(rowid, pinned: pinned);

  /// Makes a chat a favourite, or not one.
  Future<void> setFavourite(String id, {required bool favourite}) =>
      _chats.setFavourite(id, favourite: favourite);

  Future<void> markDisplayed(int rowid) => _chats.markDisplayed(rowid);

  // -------------------------------------------------------------- sending

  Future<void> sendText(
    String conversationId,
    String text, {
    MessageRef? replyTo,
    List<Mention> mentions = const [],
  }) => _chats.sendText(
    conversationId,
    text,
    replyTo: replyTo,
    mentions: mentions,
  );

  Future<void> sendMedia(
    String conversationId,
    List<MediaInput> items, {
    String? caption,
    MessageRef? replyTo,
    bool viewOnce = false,
  }) async {
    try {
      await _engine.media.sendMedia(
        conversationId,
        items,
        caption: caption,
        replyTo: replyTo,
        viewOnce: viewOnce,
      );
    } finally {
      // The engine copied what it was given into its own store; the picker's
      // plaintext temporary copies have done their job.
      await PickerTemporaryFiles.clear();
    }
  }

  Future<void> react(int rowid, String? emoji) => _chats.react(rowid, emoji);

  Future<void> edit(int rowid, String text) => _chats.edit(rowid, text);

  Future<void> deleteForEveryone(int rowid) => _chats.deleteForEveryone(rowid);

  Future<void> deleteForMe(Iterable<int> rowids) => _chats.deleteForMe(rowids);

  Future<void> retrySend(int rowid) => _chats.retrySend(rowid);

  /// Actions of the chat that failed for good, live: the timeline shows each
  /// under its message with a retry (AUD-12i-1).
  Stream<List<FailedAction>> watchFailedActions(String conversationId) =>
      _chats.watchFailedActions(conversationId);

  /// [watchFailedActions], read once.
  Future<List<FailedAction>> failedActions(String conversationId) =>
      _chats.failedActions(conversationId);

  Future<void> retryAction(int opId) => _chats.retryAction(opId);

  /// Sends the message [rowid] on to [toConversationId]: a media message
  /// reuses its uploaded object, a text message is sent again as text.
  /// Anything else cannot be forwarded and throws a [StateError].
  Future<void> forward(int rowid, String toConversationId) async {
    final source = await _chats.message(rowid);
    if (source == null || source.deletedAt != null) {
      throw StateError('this message is gone');
    }
    switch (source.kind) {
      case 'media':
        await _engine.media.forward(rowid, toConversationId);
      case 'text':
        await _chats.sendText(toConversationId, source.body ?? '');
      default:
        throw StateError('this kind of message cannot be forwarded');
    }
  }

  Future<void> sendTyping(String conversationId, {required bool typing}) =>
      _engine.presence.sendTyping(conversationId, typing: typing);

  // ---------------------------------------------------------------- media

  Future<void> downloadNow(int attachmentId) =>
      _engine.media.downloadNow(attachmentId);

  Future<void> cancelTransfer(int attachmentId) =>
      _engine.media.cancel(attachmentId);

  Future<void> retryTransfer(int messageRowid) =>
      _engine.media.retry(messageRowid);

  Future<void> openViewOnce(int rowid) => _chats.openViewOnce(rowid);

  Future<void> consumeViewOnce(int rowid) =>
      _engine.media.consumeViewOnce(rowid);

  // --------------------------------------------------------------- people

  Future<void> block(String account) => _engine.people.block(account);

  Future<void> unblock(String account) => _engine.people.unblock(account);

  /// Whether [account] has blocked this account (the server says so).
  Stream<bool> watchBlocksMe(String account) =>
      _engine.people.watchBlocksMe(account);

  Future<PresenceResponse?> presence(String account) async {
    try {
      return await _engine.people.presence(account);
    } on Object {
      // Presence is a nicety: offline, hidden or unknown all show nothing.
      return null;
    }
  }
}

/// The gateway over the live runtime.
///
/// Tests override this with a [ChatGateway] built on an engine over an
/// in-memory database.
final chatGatewayProvider = FutureProvider<ChatGateway>((ref) async {
  final runtime = await ref.watch(runtimeProvider.future);
  return ChatGateway(runtime.engine);
});

/// "UTC+06:00", "UTC-03:30", "UTC+00:00": a zone named by its offset.
String utcOffsetName(Duration offset) {
  final minutes = offset.inMinutes.abs();
  String two(int n) => n.toString().padLeft(2, '0');
  final sign = offset.isNegative ? '-' : '+';
  return 'UTC$sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
}
