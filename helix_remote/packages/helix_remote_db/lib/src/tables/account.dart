import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/values.dart';

/// This device's own account. One row (`id = 1`).
@DataClassName('SelfAccountRow')
class SelfAccount extends Table {
  IntColumn get id => integer()();
  TextColumn get accountId => text()();
  TextColumn get deviceId => text()();

  /// The home server's authority (`helix.example.org`), as in qualified
  /// addresses `uuid@domain`.
  TextColumn get serverDomain => text()();
  TextColumn get helixName => text().nullable()();
  TextColumn get phoneNumber => text().nullable()();
  TextColumn get profileName => text().nullable()();
  BlobColumn get profileKey => blob().nullable()();
  IntColumn get profileVersion => integer().withDefault(const Constant(0))();
  IntColumn get registeredAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}

/// The account's linked devices, as the server lists them (device
/// management). Key material for messaging the account's other devices lives
/// in `person_devices` under the account's own id, like any peer.
@DataClassName('SelfDeviceRow')
class SelfDevices extends Table {
  TextColumn get deviceId => text()();
  TextColumn get name => text().nullable()();
  TextColumn get platform => text().nullable()();
  IntColumn get linkedAt => integer().nullable().map(const EpochMs())();
  IntColumn get lastActiveAt => integer().nullable().map(const EpochMs())();
  BoolColumn get isThisDevice => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {deviceId};
}
