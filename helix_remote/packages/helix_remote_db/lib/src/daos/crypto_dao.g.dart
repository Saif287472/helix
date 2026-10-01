// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crypto_dao.dart';

// ignore_for_file: type=lint
mixin _$CryptoDaoMixin on DatabaseAccessor<HelixDb> {
  $IdentityTable get identity => attachedDatabase.identity;
  $SessionsTable get sessions => attachedDatabase.sessions;
  $PrekeysTable get prekeys => attachedDatabase.prekeys;
  $SenderKeysTable get senderKeys => attachedDatabase.senderKeys;
  CryptoDaoManager get managers => CryptoDaoManager(this);
}

class CryptoDaoManager {
  final _$CryptoDaoMixin _db;
  CryptoDaoManager(this._db);
  $$IdentityTableTableManager get identity =>
      $$IdentityTableTableManager(_db.attachedDatabase, _db.identity);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$PrekeysTableTableManager get prekeys =>
      $$PrekeysTableTableManager(_db.attachedDatabase, _db.prekeys);
  $$SenderKeysTableTableManager get senderKeys =>
      $$SenderKeysTableTableManager(_db.attachedDatabase, _db.senderKeys);
}
