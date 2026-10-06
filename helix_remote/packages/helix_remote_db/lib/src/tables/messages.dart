import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/tables/conversations.dart';
import 'package:helix_remote_db/src/values.dart';

/// Decrypted messages (decrypt once, on arrival; plan §3.5). Only visible
/// content types become rows (CONTENT_V2.md §2); actions on messages update
/// these rows, the reaction/receipt tables, or wait in `deferred_actions`.
@DataClassName('MessageRow')
@TableIndex(name: 'messages_unread', columns: {#conversationId, #status})
@TableIndex(name: 'messages_message_id', columns: {#messageId})
@TableIndex(name: 'messages_expires_at', columns: {#expiresAt})
class Messages extends Table {
  /// Local row id; also the FTS rowid.
  IntColumn get localRowid => integer().autoIncrement()();

  /// UUIDv7 chosen by the author. Other content names a message by
  /// `(message_id, sender)`.
  TextColumn get messageId => text()();
  TextColumn get conversationId =>
      text().references(Conversations, #id, onDelete: KeyAction.cascade)();
  TextColumn get sender => text()();
  TextColumn get senderDevice => text().nullable()();
  BoolColumn get outgoing => boolean()();

  /// [SortKey.of] `(sent_at, message_id)`; keyset paging runs on
  /// `(conversation_id, sort_key)`.
  TextColumn get sortKey => text()();
  IntColumn get sentAt => integer().map(const EpochMs())();
  IntColumn get receivedAt => integer().map(const EpochMs())();

  /// The content `type` (`text`, `media`, `poll`, …), or a type this client
  /// does not know (shown as "needs a newer version").
  TextColumn get kind => text()();

  /// Searchable text: the message text or the media caption. Indexed by
  /// `messages_fts`; cleared on delete for everyone.
  TextColumn get body => text().nullable()();

  /// The rest of the content body as JSON (poll options, location, contact
  /// card, link preview, mentions, …).
  TextColumn get payload => text().nullable()();
  TextColumn get replyToId => text().nullable()();
  TextColumn get replyToAuthor => text().nullable()();
  BoolColumn get forwarded => boolean().withDefault(const Constant(false))();
  BoolColumn get mentionsMe => boolean().withDefault(const Constant(false))();
  TextColumn get status => textEnum<MessageStatus>()();
  IntColumn get editedAt => integer().nullable().map(const EpochMs())();
  IntColumn get deletedAt => integer().nullable().map(const EpochMs())();

  /// Disappearing timer (`exp`), counted from first display on this device;
  /// [expiresAt] is set then.
  IntColumn get expireSeconds => integer().nullable()();
  IntColumn get expiresAt => integer().nullable().map(const EpochMs())();
  TextColumn get viewOnceState => textEnum<ViewOnceState>().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {messageId, sender},
    {conversationId, sortKey},
  ];
}

/// One reaction per account per message (a new one replaces the old).
@DataClassName('ReactionRow')
class MessageReactions extends Table {
  IntColumn get messageRowid => integer().references(
    Messages,
    #localRowid,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get reactor => text()();
  TextColumn get emoji => text()();
  IntColumn get reactedAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {messageRowid, reactor};
}

/// Per-recipient receipts for outgoing messages. Each time is set once.
@DataClassName('ReceiptRow')
class MessageReceipts extends Table {
  IntColumn get messageRowid => integer().references(
    Messages,
    #localRowid,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get accountId => text()();
  IntColumn get deliveredAt => integer().nullable().map(const EpochMs())();
  IntColumn get readAt => integer().nullable().map(const EpochMs())();
  IntColumn get viewedAt => integer().nullable().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {messageRowid, accountId};
}

/// Media items of a message, in album order ([position]).
@DataClassName('AttachmentRow')
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get messageRowid => integer().references(
    Messages,
    #localRowid,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get position => integer()();

  /// `MediaItemKind` wire name (`image`, `voice_note`, …).
  TextColumn get kind => text()();

  /// Server object id and the pointer's key material (CRYPTO_V2.md §12).
  TextColumn get mediaId => text()();
  BlobColumn get mediaKey => blob()();
  BlobColumn get digest => blob()();
  TextColumn get mime => text()();
  IntColumn get size => integer()();
  TextColumn get name => text().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  BlobColumn get waveform => blob().nullable()();
  TextColumn get blurhash => text().nullable()();
  TextColumn get caption => text().nullable()();

  /// The thumbnail's `MediaPointer` as JSON.
  TextColumn get thumbnail => text().nullable()();
  TextColumn get thumbnailPath => text().nullable()();
  TextColumn get localPath => text().nullable()();
  TextColumn get transfer => textEnum<AttachmentTransfer>()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {messageRowid, position},
  ];
}
