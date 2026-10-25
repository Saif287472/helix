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

  /// Deletes [setting], reporting whether a row was there (a consume that
  /// two callers may attempt at once).
  Future<bool> remove(Setting<Object?> setting) async =>
      await (delete(settings)..where((s) => s.key.equals(setting.key))).go() >
      0;

  /// Every row whose key starts with [prefix], key to stored value.
  Future<Map<String, String>> entriesWithPrefix(String prefix) async {
    final rows = await _rowsWithPrefix(prefix).get();
    return {for (final row in rows) row.key: row.value};
  }

  /// [entriesWithPrefix], live.
  Stream<Map<String, String>> watchEntriesWithPrefix(String prefix) =>
      _rowsWithPrefix(prefix)
          .watch()
          .map((rows) => {for (final row in rows) row.key: row.value})
          .distinct(_sameEntries);

  /// Deletes every row whose key starts with [prefix].
  Future<void> resetWithPrefix(String prefix) => (delete(
    settings,
  )..where((s) => s.key.like(_pattern(prefix), escapeChar: '\\'))).go();

  /// Keeps the [keepNewest] most recently written rows under [prefix].
  Future<void> pruneWithPrefix(String prefix, {required int keepNewest}) async {
    final query = _rowsWithPrefix(prefix);
    query.orderBy([(s) => OrderingTerm.desc(s.updatedAt)]);
    final rows = await query.get();
    if (rows.length <= keepNewest) return;
    final stale = [for (final row in rows.skip(keepNewest)) row.key];
    await (delete(settings)..where((s) => s.key.isIn(stale))).go();
  }

  SimpleSelectStatement<$SettingsTable, SettingRow> _query(
    Setting<Object?> setting,
  ) => select(settings)..where((s) => s.key.equals(setting.key));

  SimpleSelectStatement<$SettingsTable, SettingRow> _rowsWithPrefix(
    String prefix,
  ) =>
      select(settings)
        ..where((s) => s.key.like(_pattern(prefix), escapeChar: '\\'));

  /// [prefix] as a LIKE pattern, for any characters a key may hold.
  static String _pattern(String prefix) =>
      '${prefix.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%';

  static bool _sameEntries(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length &&
      a.entries.every((entry) => b[entry.key] == entry.value);
}
