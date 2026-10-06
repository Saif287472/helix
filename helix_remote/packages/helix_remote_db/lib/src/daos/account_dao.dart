import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/account.dart';

part 'account_dao.g.dart';

/// This device's account and the account's linked devices.
@DriftAccessor(tables: [SelfAccount, SelfDevices])
class AccountDao extends DatabaseAccessor<HelixDb> with _$AccountDaoMixin {
  AccountDao(super.attachedDatabase);

  Future<SelfAccountRow?> current() => select(selfAccount).getSingleOrNull();

  Stream<SelfAccountRow?> watchCurrent() =>
      select(selfAccount).watchSingleOrNull();

  /// Writes the account row (the `id` is always 1).
  Future<void> save(SelfAccountCompanion account) => into(
    selfAccount,
  ).insertOnConflictUpdate(account.copyWith(id: const Value(1)));

  Future<List<SelfDeviceRow>> devices() => select(selfDevices).get();

  Stream<List<SelfDeviceRow>> watchDevices() =>
      (select(selfDevices)..orderBy([
            (d) => OrderingTerm.desc(d.isThisDevice),
            (d) => OrderingTerm.desc(d.lastActiveAt),
          ]))
          .watch();

  /// Replaces the device list with the server's.
  Future<void> replaceDevices(Iterable<SelfDevicesCompanion> devices) =>
      transaction(() async {
        await delete(selfDevices).go();
        await batch((b) => b.insertAll(selfDevices, devices.toList()));
      });
}
