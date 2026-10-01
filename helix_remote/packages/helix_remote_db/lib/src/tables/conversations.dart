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
