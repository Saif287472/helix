import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/values.dart';

/// This device's key material (CRYPTO_V2.md §2). One row (`id = 1`).
/// Private keys are protected at rest by SQLCipher.
@DataClassName('IdentityRow')
class Identity extends Table {
  IntColumn get id => integer()();
  TextColumn get accountId => text()();
  TextColumn get deviceId => text()();
  BlobColumn get aikPublic => blob()();
  BlobColumn get aikPrivate => blob()();
  BlobColumn get dikPublic => blob()();
  BlobColumn get dikPrivate => blob()();
  BlobColumn get dskPublic => blob()();
  BlobColumn get dskPrivate => blob()();
  BlobColumn get deviceCertificate => blob()();
  IntColumn get createdAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}

/// Double Ratchet sessions per device pair (CRYPTO_V2.md §4–5): slot 0 is
/// the active session, slots 1–5 the previous ones tried on decrypt. The
/// state blob is owned by `helix_remote_crypto`.
@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get peerAccountId => text()();
  TextColumn get peerDeviceId => text()();
  IntColumn get slot => integer()();
  BlobColumn get state => blob()();
  IntColumn get createdAt => integer().map(const EpochMs())();
  IntColumn get updatedAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {peerAccountId, peerDeviceId, slot};

  @override
  List<String> get customConstraints => ['CHECK (slot BETWEEN 0 AND 5)'];
}

/// This device's signed and one-time prekeys (CRYPTO_V2.md §3). A rotated
/// signed prekey keeps its private part for 30 days ([retiredAt]).
@DataClassName('PrekeyRow')
class Prekeys extends Table {
  TextColumn get kind => textEnum<PrekeyKind>()();
  IntColumn get keyId => integer()();
  BlobColumn get publicKey => blob()();
  BlobColumn get privateKey => blob()();
  BlobColumn get signature => blob().nullable()();
  IntColumn get createdAt => integer().map(const EpochMs())();
  IntColumn get retiredAt => integer().nullable().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {kind, keyId};
}

/// Sender keys per `(group, account, device, dist_id)` (CRYPTO_V2.md §7),
/// this device's own sending keys included. The state blob is owned by
/// `helix_remote_crypto`.
@DataClassName('SenderKeyRow')
class SenderKeys extends Table {
  TextColumn get groupId => text()();
  TextColumn get accountId => text()();
  TextColumn get deviceId => text()();
  TextColumn get distId => text()();
  BlobColumn get state => blob()();
  IntColumn get createdAt => integer().map(const EpochMs())();
  IntColumn get updatedAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {groupId, accountId, deviceId, distId};
}
