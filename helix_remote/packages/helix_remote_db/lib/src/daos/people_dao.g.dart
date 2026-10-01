// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'people_dao.dart';

// ignore_for_file: type=lint
mixin _$PeopleDaoMixin on DatabaseAccessor<HelixDb> {
  $PeopleTable get people => attachedDatabase.people;
  $PersonDevicesTable get personDevices => attachedDatabase.personDevices;
  PeopleDaoManager get managers => PeopleDaoManager(this);
}

class PeopleDaoManager {
  final _$PeopleDaoMixin _db;
  PeopleDaoManager(this._db);
  $$PeopleTableTableManager get people =>
      $$PeopleTableTableManager(_db.attachedDatabase, _db.people);
  $$PersonDevicesTableTableManager get personDevices =>
      $$PersonDevicesTableTableManager(_db.attachedDatabase, _db.personDevices);
}
