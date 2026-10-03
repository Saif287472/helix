import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
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
final class DbSenderKeyStore implements SenderKeyStore {
  DbSenderKeyStore(this._ctx);

  final EngineContext _ctx;

  HelixDb get _db => _ctx.db;

  @override
  Future<SenderKeyState?> ownKey(String groupId) async {
    final self = _ctx.identity;
    final row = await _db.cryptoDao.latestSenderKey(
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
    await _db.transaction(() async {
      await _db.cryptoDao.saveSenderKey(
        SenderKeysCompanion.insert(
          groupId: state.groupId,
          accountId: self.accountId,
          deviceId: self.deviceId,
          distId: state.distributionId,
          state: state.encode(),
          createdAt: state.createdAt,
          updatedAt: now,
        ),
      );
      // A rotation replaces the sending key: nobody decrypts our own
      // messages, so the old chain is not needed any more.
      for (final old in await _db.cryptoDao.senderKeysOf(
        groupId: state.groupId,
        account: self.accountId,
        device: self.deviceId,
      )) {
        if (old.distId != state.distributionId) {
          await _db.cryptoDao.deleteSenderKey(
            groupId: state.groupId,
            account: self.accountId,
            device: self.deviceId,
            distId: old.distId,
          );
        }
      }
    });
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
  Future<void> forgetGroup(String groupId) =>
      _db.cryptoDao.deleteSenderKeys(groupId);

  /// Forgets the keys received from [account] (it was removed: its devices
  /// must not be sending into the group any more).
  Future<void> forgetMember(String groupId, String account) =>
      _db.cryptoDao.deleteSenderKeys(groupId, account: account);
}
