import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/values.dart';

/// Typed key/value settings. Values are JSON; `Setting<T>` gives each key its
/// type and default.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {key};
}
