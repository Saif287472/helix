import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/values.dart';

/// Everyone this device knows about. There are no contact requests: a row
/// exists because of a phone-book match, a chat, or a lookup. Shown by
/// phone-book name, then nickname, then number, then `~helix_name`.
@DataClassName('PersonRow')
@TableIndex(name: 'people_phone_hash', columns: {#phoneHash})
class People extends Table {
  /// Bare uuid for the home server, `uuid@domain` for other servers.
  TextColumn get accountId => text()();
  TextColumn get helixName => text().nullable()();
  TextColumn get phoneNumber => text().nullable()();
  TextColumn get phoneHash => text().nullable()();
  TextColumn get phonebookName => text().nullable()();
  TextColumn get nickname => text().nullable()();

  /// From the decrypted profile (CRYPTO_V2.md §9).
  TextColumn get profileName => text().nullable()();
  BlobColumn get profileKey => blob().nullable()();
  IntColumn get profileVersion => integer().nullable()();
  BlobColumn get avatarBlob => blob().nullable()();

  /// The pinned account identity key (AIK, trust on first use).
  BlobColumn get identityKey => blob().nullable()();

  /// The user compared safety numbers; reset on a key change.
  BoolColumn get identityVerified =>
      boolean().withDefault(const Constant(false))();
  IntColumn get identityChangedAt =>
      integer().nullable().map(const EpochMs())();
  BoolColumn get blocked => boolean().withDefault(const Constant(false))();
  IntColumn get updatedAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {accountId};
}

/// Devices of an account (including this account's other devices), with
/// the keys from their certificates.
@DataClassName('PersonDeviceRow')
class PersonDevices extends Table {
  TextColumn get accountId => text()();
  TextColumn get deviceId => text()();

  /// Device identity key (DIK, X25519 public).
  BlobColumn get identityKey => blob()();

  /// Device signing key (DSK, Ed25519 public).
  BlobColumn get signingKey => blob()();
  BlobColumn get certificate => blob().nullable()();
  TextColumn get trust => textEnum<DeviceTrust>()();
  IntColumn get firstSeenAt => integer().map(const EpochMs())();
  IntColumn get updatedAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {accountId, deviceId};
}
