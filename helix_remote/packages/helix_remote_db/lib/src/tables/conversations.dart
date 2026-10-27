import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/values.dart';

/// One chat. The `last_message_*`, `unread_count` and `mention_count`
/// columns are a denormalised summary for the chat list; `MessagesDao`
/// updates them in the same transaction as every message write.
@DataClassName('ConversationRow')
@TableIndex(name: 'conversations_list', columns: {#archived, #lastMessageAt})
class Conversations extends Table {
  /// `direct:<peer account>` for direct chats ([directConversationId]).
  TextColumn get id => text()();
  TextColumn get kind => textEnum<ConversationKind>()();
  TextColumn get title => text().nullable()();
  BlobColumn get avatar => blob().nullable()();
  IntColumn get pinnedAt => integer().nullable().map(const EpochMs())();

  IntColumn get mutedUntil => integer().nullable().map(const EpochMs())();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  /// `messages.local_rowid` of the newest message (by sort key).
  IntColumn get lastMessageRowid => integer().nullable()();
  TextColumn get lastMessageSortKey => text().nullable()();
  IntColumn get lastMessageAt => integer().nullable().map(const EpochMs())();
  TextColumn get lastMessagePreview => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get mentionCount => integer().withDefault(const Constant(0))();

  /// The user has read everything up to this sort key.
  TextColumn get lastReadSortKey => text().nullable()();
  TextColumn get draft => text().nullable()();
  IntColumn get disappearingSeconds => integer().nullable()();
  IntColumn get createdAt => integer().map(const EpochMs())();

  /// When the chat was made a favourite (a private filter on the chat list,
  /// never sent). Null when it is not one. Schema 6.
  IntColumn get favouriteAt => integer().nullable().map(const EpochMs())();

  /// When the chat was locked: it is out of the chat list, out of search,
  /// starred messages and the GIF tray, and its notifications show no name or
  /// text; it is opened from Locked chats after the phone's own unlock. Null
  /// when it is not locked. Private to the device, never sent. Schema 8.
  IntColumn get lockedAt => integer().nullable().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {id};
}

/// The other people in a chat. A direct chat has one member, the peer.
@DataClassName('ConversationMemberRow')
@TableIndex(name: 'conversation_members_account', columns: {#accountId})
class ConversationMembers extends Table {
  TextColumn get conversationId =>
      text().references(Conversations, #id, onDelete: KeyAction.cascade)();
  TextColumn get accountId => text()();
  IntColumn get joinedAt => integer().nullable().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {conversationId, accountId};
}

/// A list the person made on the Chats tab ("Work", "Family"): a private way
/// to group chats, never sent anywhere. Schema 7.
@DataClassName('ChatListRow')
class ChatLists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Where the list's chip sits among the others, first to last.
  IntColumn get position => integer()();
  IntColumn get createdAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {id};
}

/// A chat on a list. A chat may be on several, and leaves them all when it is
/// deleted. Schema 7.
@DataClassName('ChatListMemberRow')
@TableIndex(name: 'chat_list_members_chat', columns: {#conversationId})
class ChatListMembers extends Table {
  TextColumn get listId =>
      text().references(ChatLists, #id, onDelete: KeyAction.cascade)();
  TextColumn get conversationId =>
      text().references(Conversations, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {listId, conversationId};
}
