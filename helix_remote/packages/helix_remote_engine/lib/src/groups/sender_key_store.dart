import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';

/// [SenderKeyStore] over the `sender_keys` table: this device's own sending
/// key per group (one row; replaced on rotation) and the keys received from
/// other member devices (the newest [GroupLimits.keptReceivedSenderKeys]
/// per device, so late messages of the previous key still open).
///
/// Like the pairwise stores it only reads through the crypto interface; the
/// engine commits what the crypto layer returns with [commit], inside the
/// transaction of the message's effect, and before an outgoing ciphertext
/// leaves the device (CRYPTO_V2.md §14).
///
/// **Revisions of the own key.** [ownKey] remembers the `sender_keys.version`
/// it read for the group, and committing an [OwnSenderKeyWrite] writes only
/// while the stored revision is still that one
/// (`CryptoDao.saveOwnSenderKey`). A refused write throws
/// [StaleSenderKeyState] and the sender encrypts again from the stored key:
/// two engines on one database file would otherwise send two messages from
/// one chain iteration, under one key and nonce. Every own-key read and write
/// happens under the group's send lock (`GroupMessageSender`), so the
/// remembered revision belongs to the write that follows it.
final class DbSenderKeyStore implements SenderKeyStore {
  DbSenderKeyStore(this._ctx);

  final EngineContext _ctx;

  /// The revision [ownKey] last read per group. A write that no read of this
  /// engine preceded compares with 0 (no key), so it lands only on a group
  /// with no key yet and is refused otherwise.
  final Map<String, int> _ownVersions = {};

  HelixDb get _db => _ctx.db;

  @override
  Future<SenderKeyState?> ownKey(String groupId) async {
    final self = _ctx.identity;
    final row = await _db.cryptoDao.latestSenderKey(
      groupId: groupId,
      account: self.accountId,
      device: self.deviceId,
    );
    _ownVersions[groupId] = await _db.cryptoDao.ownSenderKeyVersion(
      groupId: groupId,
      account: self.accountId,
      device: self.deviceId,
    );
    return row == null ? null : SenderKeyState.decode(row.state);
  }

  @override
  Future<ReceivedSenderKey?> receivedKey(
    DeviceAddress sender,
    String groupId,
    String distributionId,
  ) async {
    final row = await _db.cryptoDao.senderKey(
      groupId: groupId,
      account: sender.account,
      device: sender.device,
      distId: distributionId,
    );
    return row == null ? null : ReceivedSenderKey.decode(row.state);
  }

  /// Writes the state changes a crypto call returned.
  Future<void> commit(Iterable<GroupCryptoWrite> writes) async {
    final now = _ctx.now();
    for (final write in writes) {
      switch (write) {
        case OwnSenderKeyWrite(:final state):
          await _saveOwn(state, now);
        case ReceivedSenderKeyWrite(:final key):
          await _saveReceived(key, now);
        default:
          throw ArgumentError('unknown group crypto write');
      }
    }
  }

  Future<void> _saveOwn(SenderKeyState state, DateTime now) async {
    final self = _ctx.identity;
    final expected = _ownVersions[state.groupId] ?? 0;
    final landed = await _db.cryptoDao.saveOwnSenderKey(
      SenderKeysCompanion.insert(
        groupId: state.groupId,
        accountId: self.accountId,
        deviceId: self.deviceId,
        distId: state.distributionId,
        state: state.encode(),
        createdAt: state.createdAt,
        updatedAt: now,
      ),
      expectedVersion: expected,
    );
    if (!landed) {
      _ownVersions.remove(state.groupId);
      throw StaleSenderKeyState(state.groupId);
    }
    _ownVersions[state.groupId] = expected + 1;
  }

  Future<void> _saveReceived(ReceivedSenderKey key, DateTime now) async {
    final from = key.sender;
    await _db.transaction(() async {
      await _db.cryptoDao.saveSenderKey(
        SenderKeysCompanion.insert(
          groupId: key.groupId,
          accountId: from.account,
          deviceId: from.device,
          distId: key.distributionId,
          state: key.encode(),
          createdAt: key.receivedAt,
          updatedAt: now,
        ),
      );
      final all = await _db.cryptoDao.senderKeysOf(
        groupId: key.groupId,
        account: from.account,
        device: from.device,
      );
      for (final old in all.skip(GroupLimits.keptReceivedSenderKeys)) {
        if (old.distId == key.distributionId) continue;
        await _db.cryptoDao.deleteSenderKey(
          groupId: key.groupId,
          account: from.account,
          device: from.device,
          distId: old.distId,
        );
      }
    });
  }

  /// Forgets every sender key of a group (this device left it).
  Future<void> forgetGroup(String groupId) {
    _ownVersions.remove(groupId);
    return _db.cryptoDao.deleteSenderKeys(groupId);
  }

  /// Forgets the keys received from [account] (it was removed: its devices
  /// must not be sending into the group any more).
  Future<void> forgetMember(String groupId, String account) =>
      _db.cryptoDao.deleteSenderKeys(groupId, account: account);
}
