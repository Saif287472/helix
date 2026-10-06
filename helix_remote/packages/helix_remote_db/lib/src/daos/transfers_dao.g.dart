// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transfers_dao.dart';

// ignore_for_file: type=lint
mixin _$TransfersDaoMixin on DatabaseAccessor<HelixDb> {
  $ConversationsTable get conversations => attachedDatabase.conversations;
  $MessagesTable get messages => attachedDatabase.messages;
  $AttachmentsTable get attachments => attachedDatabase.attachments;
  $TransferJobsTable get transferJobs => attachedDatabase.transferJobs;
  $TransferChunksTable get transferChunks => attachedDatabase.transferChunks;
  TransfersDaoManager get managers => TransfersDaoManager(this);
}

class TransfersDaoManager {
  final _$TransfersDaoMixin _db;
  TransfersDaoManager(this._db);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db.attachedDatabase, _db.conversations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db.attachedDatabase, _db.messages);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db.attachedDatabase, _db.attachments);
  $$TransferJobsTableTableManager get transferJobs =>
      $$TransferJobsTableTableManager(_db.attachedDatabase, _db.transferJobs);
  $$TransferChunksTableTableManager get transferChunks =>
      $$TransferChunksTableTableManager(
        _db.attachedDatabase,
        _db.transferChunks,
      );
}
