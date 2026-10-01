// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'messages_dao.dart';

// ignore_for_file: type=lint
mixin _$MessagesDaoMixin on DatabaseAccessor<HelixDb> {
  $ConversationsTable get conversations => attachedDatabase.conversations;
  $MessagesTable get messages => attachedDatabase.messages;
  $MessageReactionsTable get messageReactions =>
      attachedDatabase.messageReactions;
  $MessageReceiptsTable get messageReceipts => attachedDatabase.messageReceipts;
  $AttachmentsTable get attachments => attachedDatabase.attachments;
  MessagesDaoManager get managers => MessagesDaoManager(this);
}

class MessagesDaoManager {
  final _$MessagesDaoMixin _db;
  MessagesDaoManager(this._db);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db.attachedDatabase, _db.conversations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db.attachedDatabase, _db.messages);
  $$MessageReactionsTableTableManager get messageReactions =>
      $$MessageReactionsTableTableManager(
        _db.attachedDatabase,
        _db.messageReactions,
      );
  $$MessageReceiptsTableTableManager get messageReceipts =>
      $$MessageReceiptsTableTableManager(
        _db.attachedDatabase,
        _db.messageReceipts,
      );
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db.attachedDatabase, _db.attachments);
}
