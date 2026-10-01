// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversations_dao.dart';

// ignore_for_file: type=lint
mixin _$ConversationsDaoMixin on DatabaseAccessor<HelixDb> {
  $ConversationsTable get conversations => attachedDatabase.conversations;
  $ConversationMembersTable get conversationMembers =>
      attachedDatabase.conversationMembers;
  $MessagesTable get messages => attachedDatabase.messages;
  ConversationsDaoManager get managers => ConversationsDaoManager(this);
}

class ConversationsDaoManager {
  final _$ConversationsDaoMixin _db;
  ConversationsDaoManager(this._db);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db.attachedDatabase, _db.conversations);
  $$ConversationMembersTableTableManager get conversationMembers =>
      $$ConversationMembersTableTableManager(
        _db.attachedDatabase,
        _db.conversationMembers,
      );
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db.attachedDatabase, _db.messages);
}
