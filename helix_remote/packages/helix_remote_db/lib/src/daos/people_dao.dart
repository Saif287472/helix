import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/people.dart';
import 'package:helix_remote_db/src/values.dart';

part 'people_dao.g.dart';

/// People and their devices.
@DriftAccessor(tables: [People, PersonDevices])
class PeopleDao extends DatabaseAccessor<HelixDb> with _$PeopleDaoMixin {
  PeopleDao(super.attachedDatabase);

  /// Inserts or updates; only the columns present in [person] change on
  /// update.
  Future<void> upsertPerson(PeopleCompanion person) =>
      into(people).insertOnConflictUpdate(person);

  Future<PersonRow?> byAccount(String accountId) => (select(
    people,
  )..where((p) => p.accountId.equals(accountId))).getSingleOrNull();

  Stream<PersonRow?> watchByAccount(String accountId) => (select(
    people,
  )..where((p) => p.accountId.equals(accountId))).watchSingleOrNull();

  Future<List<PersonRow>> byAccounts(Iterable<String> accountIds) => (select(
    people,
  )..where((p) => p.accountId.isIn(accountIds.toList()))).get();

  Future<PersonRow?> byPhoneHash(String phoneHash) => (select(
    people,
  )..where((p) => p.phoneHash.equals(phoneHash))).getSingleOrNull();

  /// People whose phone-book name, nickname, profile name, `~helix_name` or
  /// number contains [query] (case-insensitive for ASCII), blocked people
  /// excluded.
  Future<List<PersonRow>> search(String query, {int limit = 50}) {
    final pattern = '%${_escapeLike(query.trim())}%';
    Expression<bool> like(GeneratedColumn<String> column) =>
        column.like(pattern, escapeChar: r'\');
    return (select(people)
          ..where(
            (p) =>
                p.blocked.equals(false) &
                (like(p.phonebookName) |
                    like(p.nickname) |
                    like(p.profileName) |
                    like(p.helixName) |
                    like(p.phoneNumber)),
          )
          ..orderBy([
            (p) => OrderingTerm.asc(
              coalesce([
                p.phonebookName,
                p.nickname,
                p.phoneNumber,
                p.helixName,
              ]),
            ),
          ])
          ..limit(limit))
        .get();
  }

  Future<void> setBlocked(
    String accountId,
    bool blocked, {
    required DateTime now,
  }) => into(people).insertOnConflictUpdate(
    PeopleCompanion.insert(
      accountId: accountId,
      blocked: Value(blocked),
      updatedAt: now,
    ),
  );

  Future<List<String>> blockedAccounts() => (select(
    people,
  )..where((p) => p.blocked.equals(true))).map((p) => p.accountId).get();

  // ----------------------------------------------------------- devices

  Future<void> upsertDevice(PersonDevicesCompanion device) =>
      into(personDevices).insertOnConflictUpdate(device);

  /// Devices of [accountId], trusted ones only unless [includeStale].
  Future<List<PersonDeviceRow>> devicesOf(
    String accountId, {
    bool includeStale = false,
  }) =>
      (select(personDevices)..where(
            (d) =>
                d.accountId.equals(accountId) &
                (includeStale
                    ? const Constant(true)
                    : d.trust.equalsValue(DeviceTrust.trusted)),
          ))
          .get();

  Future<void> removeDevice(String accountId, String deviceId) =>
      (delete(personDevices)..where(
            (d) => d.accountId.equals(accountId) & d.deviceId.equals(deviceId),
          ))
          .go();

  /// After a key change: every device of [accountId] is stale until it is
  /// seen again under the new identity key.
  Future<void> markDevicesStale(String accountId) =>
      (update(personDevices)..where((d) => d.accountId.equals(accountId)))
          .write(const PersonDevicesCompanion(trust: Value(DeviceTrust.stale)));

  static String _escapeLike(String input) => input
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
