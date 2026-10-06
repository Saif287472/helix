import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/setting.dart';
import 'package:helix_remote_db/src/tables/settings.dart';

part 'settings_dao.g.dart';

/// Typed settings ([Setting]). An unset key reads as its default.
@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<HelixDb> with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  Future<T> get<T>(Setting<T> setting) async {
    final row = await _query(setting).getSingleOrNull();
    return row == null ? setting.defaultValue : setting.decode(row.value);
  }

  Stream<T> watch<T>(Setting<T> setting) => _query(setting)
      .watchSingleOrNull()
      .map(
        (row) => row == null ? setting.defaultValue : setting.decode(row.value),
      )
      .distinct();

  Future<void> set<T>(Setting<T> setting, T value, {DateTime? now}) =>
      into(settings).insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: setting.key,
          value: setting.encode(value),
          updatedAt: now ?? DateTime.now().toUtc(),
        ),
      );

  /// Back to the default.
  Future<void> reset(Setting<Object?> setting) =>
      (delete(settings)..where((s) => s.key.equals(setting.key))).go();

  SimpleSelectStatement<$SettingsTable, SettingRow> _query(
    Setting<Object?> setting,
  ) => select(settings)..where((s) => s.key.equals(setting.key));
}
