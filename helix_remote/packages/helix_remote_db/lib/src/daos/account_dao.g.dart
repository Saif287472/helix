// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_dao.dart';

// ignore_for_file: type=lint
mixin _$AccountDaoMixin on DatabaseAccessor<HelixDb> {
  $SelfAccountTable get selfAccount => attachedDatabase.selfAccount;
  $SelfDevicesTable get selfDevices => attachedDatabase.selfDevices;
  AccountDaoManager get managers => AccountDaoManager(this);
}

class AccountDaoManager {
  final _$AccountDaoMixin _db;
  AccountDaoManager(this._db);
  $$SelfAccountTableTableManager get selfAccount =>
      $$SelfAccountTableTableManager(_db.attachedDatabase, _db.selfAccount);
  $$SelfDevicesTableTableManager get selfDevices =>
      $$SelfDevicesTableTableManager(_db.attachedDatabase, _db.selfDevices);
}
