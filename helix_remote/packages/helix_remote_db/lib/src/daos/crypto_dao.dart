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

  /// Replaces the sessions with one peer device: [states] in slot order,
  /// active first, at most six.
  Future<void> saveSessions(
    String account,
    String device,
    List<Uint8List> states, {
    required DateTime now,
  }) {
    if (states.length > 6) {
      throw ArgumentError.value(states.length, 'states', 'at most 6 sessions');
    }
    return transaction(() async {
      final existing = {
        for (final s in await sessionsWith(account, device)) s.slot: s,
      };
      await deleteSessions(account, device: device);
      await batch(
        (b) => b.insertAll(sessions, [
          for (final (slot, state) in states.indexed)
            SessionsCompanion.insert(
              peerAccountId: account,
              peerDeviceId: device,
              slot: slot,
              state: state,
              createdAt: existing[slot]?.createdAt ?? now,
              updatedAt: now,
            ),
        ]),
      );
    });
  }

  /// Deletes the sessions with [account] (one [device], or all of them).
  Future<void> deleteSessions(String account, {String? device}) =>
      (delete(sessions)..where(
            (s) =>
                s.peerAccountId.equals(account) &
                (device == null
                    ? const Constant(true)
                    : s.peerDeviceId.equals(device)),
          ))
          .go();

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

  Future<void> saveSenderKey(SenderKeysCompanion key) =>
      into(senderKeys).insertOnConflictUpdate(key);

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
