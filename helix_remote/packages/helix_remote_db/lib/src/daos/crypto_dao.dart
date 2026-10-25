import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/crypto.dart';
import 'package:helix_remote_db/src/values.dart';

part 'crypto_dao.g.dart';

/// Persistence for `helix_remote_crypto` state. The blobs are opaque here.
@DriftAccessor(tables: [Identity, Sessions, Prekeys, SenderKeys])
class CryptoDao extends DatabaseAccessor<HelixDb> with _$CryptoDaoMixin {
  CryptoDao(super.attachedDatabase);

  Future<IdentityRow?> identityKeys() => select(identity).getSingleOrNull();

  /// Writes this device's keys (the `id` is always 1).
  Future<void> saveIdentity(IdentityCompanion keys) =>
      into(identity).insertOnConflictUpdate(keys.copyWith(id: const Value(1)));

  // ---------------------------------------------------------- sessions

  /// Sessions with one peer device, active first (slot 0).
  Future<List<SessionRow>> sessionsWith(String account, String device) =>
      (select(sessions)
            ..where(
              (s) =>
                  s.peerAccountId.equals(account) &
                  s.peerDeviceId.equals(device),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.slot)]))
          .get();

  /// The revision of the record with one peer device, or 0 when there is none.
  Future<int> sessionsVersion(String account, String device) async =>
      (await sessionsWith(account, device)).firstOrNull?.version ?? 0;

  /// Replaces the sessions with one peer device: [states] in slot order,
  /// active first, at most six.
  ///
  /// A compare-and-set on [Sessions.version]: the write only lands while the
  /// stored revision is still [expectedVersion], and it stores
  /// `expectedVersion + 1`. **Returns false** when it moved under this
  /// caller - another engine wrote the same record first - leaving the stored
  /// rows untouched, so the caller must load again rather than overwrite
  /// state it derived from a version that no longer exists. Two engines on
  /// one database file (the app and its FCM isolate) taking the same sending
  /// chain would otherwise encrypt two messages under one key and nonce.
  ///
  /// An empty [states] list would lose the revision, so a record with no
  /// session in it is written as a normal one-slot record (an empty
  /// `DeviceSessions` encodes to exactly that) instead of being deleted.
  Future<bool> saveSessions(
    String account,
    String device,
    List<Uint8List> states, {
    required DateTime now,
    required int expectedVersion,
  }) {
    if (states.isEmpty) {
      throw ArgumentError.value(
        states.length,
        'states',
        'an empty record is written as a one-slot record, not an empty list',
      );
    }
    if (states.length > 6) {
      throw ArgumentError.value(states.length, 'states', 'at most 6 sessions');
    }
    return transaction(() async {
      final existing = await sessionsWith(account, device);
      if (_versionOf(existing) != expectedVersion) return false;
      final created = {for (final s in existing) s.slot: s.createdAt};
      await deleteSessions(account, device: device);
      await batch(
        (b) => b.insertAll(sessions, [
          for (final (slot, state) in states.indexed)
            SessionsCompanion.insert(
              peerAccountId: account,
              peerDeviceId: device,
              slot: slot,
              state: state,
              createdAt: created[slot] ?? now,
              updatedAt: now,
              version: Value(expectedVersion + 1),
            ),
        ]),
      );
      return true;
    });
  }

  /// The revision the slots of one record agree on: their common value, or 0
  /// for no rows. Rows that disagree (never written by this DAO) read as 0,
  /// so the first write over them is allowed rather than refused forever.
  static int _versionOf(List<SessionRow> rows) {
    if (rows.isEmpty) return 0;
    final version = rows.first.version;
    return rows.every((s) => s.version == version) ? version : 0;
  }

  /// Deletes the sessions with [account] (one [device], or all of them).
  ///
  /// This drops the revision, so it is for a full wipe (sign-out, revocation)
  /// and never for replacing a record: use [saveSessions].
  ///
  /// With [expectedVersion] it is a compare-and-set on one device's record,
  /// like [saveSessions]: the delete only lands while the stored revision is
  /// still that one, and **returns false**, changing nothing, when another
  /// engine wrote the record first. That is how one unreadable record is
  /// dropped without discarding a good one that replaced it meanwhile.
  Future<bool> deleteSessions(
    String account, {
    String? device,
    int? expectedVersion,
  }) async {
    Future<int> wipe() =>
        (delete(sessions)..where(
              (s) =>
                  s.peerAccountId.equals(account) &
                  (device == null
                      ? const Constant(true)
                      : s.peerDeviceId.equals(device)),
            ))
            .go();
    if (expectedVersion == null) {
      await wipe();
      return true;
    }
    if (device == null) {
      throw ArgumentError.value(
        device,
        'device',
        'a compare-and-set delete names one device',
      );
    }
    return transaction(() async {
      final existing = await sessionsWith(account, device);
      if (_versionOf(existing) != expectedVersion) return false;
      await wipe();
      return true;
    });
  }

  // ----------------------------------------------------------- prekeys

  Future<void> savePrekeys(Iterable<PrekeysCompanion> keys) =>
      batch((b) => b.insertAllOnConflictUpdate(prekeys, keys.toList()));

  Future<PrekeyRow?> prekey(PrekeyKind kind, int keyId) =>
      (select(prekeys)
            ..where((p) => p.kind.equalsValue(kind) & p.keyId.equals(keyId)))
          .getSingleOrNull();

  Future<List<PrekeyRow>> prekeysOf(PrekeyKind kind) =>
      (select(prekeys)
            ..where((p) => p.kind.equalsValue(kind))
            ..orderBy([(p) => OrderingTerm.asc(p.keyId)]))
          .get();

  Future<void> deletePrekey(PrekeyKind kind, int keyId) => (delete(
    prekeys,
  )..where((p) => p.kind.equalsValue(kind) & p.keyId.equals(keyId))).go();

  Future<void> retireSignedPrekey(int keyId, DateTime at) =>
      (update(prekeys)..where(
            (p) =>
                p.kind.equalsValue(PrekeyKind.signed) & p.keyId.equals(keyId),
          ))
          .write(PrekeysCompanion(retiredAt: Value(at)));

  /// Deletes signed prekeys retired before [cutoff] (30 days, §3).
  Future<int> deleteRetiredBefore(DateTime cutoff) =>
      (delete(prekeys)..where(
            (p) =>
                p.retiredAt.isSmallerThanValue(cutoff.millisecondsSinceEpoch),
          ))
          .go();

  // ------------------------------------------------------- sender keys

  Future<SenderKeyRow?> senderKey({
    required String groupId,
    required String account,
    required String device,
    required String distId,
  }) =>
      (select(senderKeys)..where(
            (k) =>
                k.groupId.equals(groupId) &
                k.accountId.equals(account) &
                k.deviceId.equals(device) &
                k.distId.equals(distId),
          ))
          .getSingleOrNull();

  /// The newest sender key of one device in a group (this device's own
  /// sending key, or the latest key received from another device).
  Future<SenderKeyRow?> latestSenderKey({
    required String groupId,
    required String account,
    required String device,
  }) =>
      (select(senderKeys)
            ..where(
              (k) =>
                  k.groupId.equals(groupId) &
                  k.accountId.equals(account) &
                  k.deviceId.equals(device),
            )
            ..orderBy([
              (k) => OrderingTerm.desc(k.createdAt),
              (k) => OrderingTerm.desc(k.updatedAt),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// Every sender key of one device in a group, newest first.
  Future<List<SenderKeyRow>> senderKeysOf({
    required String groupId,
    required String account,
    required String device,
  }) =>
      (select(senderKeys)
            ..where(
              (k) =>
                  k.groupId.equals(groupId) &
                  k.accountId.equals(account) &
                  k.deviceId.equals(device),
            )
            ..orderBy([
              (k) => OrderingTerm.desc(k.createdAt),
              (k) => OrderingTerm.desc(k.updatedAt),
            ]))
          .get();

  /// Deletes one sender key.
  Future<void> deleteSenderKey({
    required String groupId,
    required String account,
    required String device,
    required String distId,
  }) =>
      (delete(senderKeys)..where(
            (k) =>
                k.groupId.equals(groupId) &
                k.accountId.equals(account) &
                k.deviceId.equals(device) &
                k.distId.equals(distId),
          ))
          .go();

  /// Saves a sender key received from another device. Its revision stays 0:
  /// receiving never encrypts, so a lost update cannot reuse a key.
  Future<void> saveSenderKey(SenderKeysCompanion key) =>
      into(senderKeys).insertOnConflictUpdate(key);

  /// The revision of this device's own sending key in [groupId] (the
  /// highest of its rows), or 0 when it has none.
  Future<int> ownSenderKeyVersion({
    required String groupId,
    required String account,
    required String device,
  }) async => _highestVersion(
    await senderKeysOf(groupId: groupId, account: account, device: device),
  );

  /// Saves this device's own sending key [key] and drops its other keys in
  /// the group (a rotation replaces the sending key: nobody decrypts our own
  /// messages, so the old chain is not needed).
  ///
  /// A compare-and-set, like [saveSessions]: the write only lands while the
  /// stored revision is still [expectedVersion], and it stores
  /// `expectedVersion + 1`. **Returns false**, changing nothing, when another
  /// engine on this database file wrote first: the caller must load the key
  /// again rather than commit a chain step that engine may also have taken.
  Future<bool> saveOwnSenderKey(
    SenderKeysCompanion key, {
    required int expectedVersion,
  }) {
    final groupId = key.groupId.value;
    final account = key.accountId.value;
    final device = key.deviceId.value;
    return transaction(() async {
      final existing = await senderKeysOf(
        groupId: groupId,
        account: account,
        device: device,
      );
      if (_highestVersion(existing) != expectedVersion) return false;
      await into(senderKeys).insertOnConflictUpdate(
        key.copyWith(version: Value(expectedVersion + 1)),
      );
      for (final old in existing) {
        if (old.distId == key.distId.value) continue;
        await deleteSenderKey(
          groupId: groupId,
          account: account,
          device: device,
          distId: old.distId,
        );
      }
      return true;
    });
  }

  static int _highestVersion(List<SenderKeyRow> rows) => rows.fold(
    0,
    (highest, row) => row.version > highest ? row.version : highest,
  );

  /// Deletes a group's sender keys, all of them or one account's.
  Future<void> deleteSenderKeys(String groupId, {String? account}) =>
      (delete(senderKeys)..where(
            (k) =>
                k.groupId.equals(groupId) &
                (account == null
                    ? const Constant(true)
                    : k.accountId.equals(account)),
          ))
          .go();
}
