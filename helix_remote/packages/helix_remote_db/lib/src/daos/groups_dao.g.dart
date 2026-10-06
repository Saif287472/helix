// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'groups_dao.dart';

// ignore_for_file: type=lint
mixin _$GroupsDaoMixin on DatabaseAccessor<HelixDb> {
  $GroupsTable get groups => attachedDatabase.groups;
  $GroupMembersTable get groupMembers => attachedDatabase.groupMembers;
  $GroupBansTable get groupBans => attachedDatabase.groupBans;
  GroupsDaoManager get managers => GroupsDaoManager(this);
}

class GroupsDaoManager {
  final _$GroupsDaoMixin _db;
  GroupsDaoManager(this._db);
  $$GroupsTableTableManager get groups =>
      $$GroupsTableTableManager(_db.attachedDatabase, _db.groups);
  $$GroupMembersTableTableManager get groupMembers =>
      $$GroupMembersTableTableManager(_db.attachedDatabase, _db.groupMembers);
  $$GroupBansTableTableManager get groupBans =>
      $$GroupBansTableTableManager(_db.attachedDatabase, _db.groupBans);
}
