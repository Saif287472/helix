// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tombstones_dao.dart';

// ignore_for_file: type=lint
mixin _$TombstonesDaoMixin on DatabaseAccessor<HelixDb> {
  $DeleteTombstonesTable get deleteTombstones =>
      attachedDatabase.deleteTombstones;
  TombstonesDaoManager get managers => TombstonesDaoManager(this);
}

class TombstonesDaoManager {
  final _$TombstonesDaoMixin _db;
  TombstonesDaoManager(this._db);
  $$DeleteTombstonesTableTableManager get deleteTombstones =>
      $$DeleteTombstonesTableTableManager(
        _db.attachedDatabase,
        _db.deleteTombstones,
      );
}
