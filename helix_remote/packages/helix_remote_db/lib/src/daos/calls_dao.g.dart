// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'calls_dao.dart';

// ignore_for_file: type=lint
mixin _$CallsDaoMixin on DatabaseAccessor<HelixDb> {
  $CallLogTable get callLog => attachedDatabase.callLog;
  CallsDaoManager get managers => CallsDaoManager(this);
}

class CallsDaoManager {
  final _$CallsDaoMixin _db;
  CallsDaoManager(this._db);
  $$CallLogTableTableManager get callLog =>
      $$CallLogTableTableManager(_db.attachedDatabase, _db.callLog);
}
