import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_engine/src/groups/group_keyring.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What an arriving group master key did.
enum GroupKeyVerdict {
  /// It opens the stored state, or there is no state to contradict it.
  accepted,

  /// The stored state cannot decide yet: the key is kept beside the held one.
  tentative,

  /// Already held for the epoch.
  known,

  /// A held key demonstrably opens the stored state; the arrival does not.
  refused,
}

/// Decides which key is a group epoch's master key (AUD-12f-3, AUD-12e-1).
///
/// Three writers stored epoch keys: group creation, the rotation op and the
/// inbound `group_key`. The keyring only stores whatever it is handed, so
/// without one arbiter the first arrival won: a wrong key kept a later,
/// correct one out whenever the stored state could not open under it (no
/// state yet, or a blob sealed under an older epoch), and a rotation then
/// re-used the wrong key and sealed the state under it for good.
///
/// The stored state decides whenever it can:
/// - a key that opens it replaces whatever is held (and the replaced key
///   stays as the second candidate);
/// - a held key that opens it refuses a key that does not;
/// - when it opens under neither, the arrival is kept beside the held key,
///   and whichever key a later state write seals under is promoted then.
///
/// Two keys per epoch are enough: a key whose state write lands is promoted
/// on the first read, and a key whose state write never lands never becomes
/// the group's. [GroupKeyring] stays storage.
final class GroupKeyAuthority {
  GroupKeyAuthority(this._keyring);

  final GroupKeyring _keyring;

  /// Takes [key] as the master key of [epoch].
  Future<GroupKeyVerdict> accept({
    required String groupId,
    required int epoch,
    required List<int>? state,
    required int version,
    required List<int> key,
  }) async {
    final primary = await _keyring.keyFor(groupId, epoch);
    final candidate = await _keyring.candidateFor(groupId, epoch);
    if (_same(primary, key) || _same(candidate, key)) {
      return GroupKeyVerdict.known;
    }
    if (state != null) {
      if (await _keyring.tryOpen(groupId, state, epoch, version, key) != null) {
        await _keyring.promote(groupId, epoch, key);
        return GroupKeyVerdict.accepted;
      }
      for (final held in [primary, candidate]) {
        if (held != null &&
            await _keyring.tryOpen(groupId, state, epoch, version, held) !=
                null) {
          return GroupKeyVerdict.refused;
        }
      }
    }
    if (primary == null && candidate == null) {
      await _keyring.put(groupId, epoch, key);
      return GroupKeyVerdict.accepted;
    }
    // The state cannot say which of the two is the group's: it is sealed
    // under another epoch, has not been written yet, or (when the blob is a
    // rollback) opens under neither. Keep both; a later write decides.
    await _keyring.putCandidate(groupId, epoch, key);
    return GroupKeyVerdict.tentative;
  }

  /// The key held for [epoch] that opens [blob], primary first. The second
  /// key is promoted when it is the one that opens it, so the next state
  /// write and the next share use the right key. Null when neither does.
  Future<Uint8List?> keyThatOpens(
    String groupId,
    List<int> blob, {
    required int epoch,
    required int version,
  }) async {
    final primary = await _keyring.keyFor(groupId, epoch);
    if (primary != null &&
        await _keyring.tryOpen(groupId, blob, epoch, version, primary) !=
            null) {
      return primary;
    }
    final candidate = await _keyring.candidateFor(groupId, epoch);
    if (candidate != null &&
        await _keyring.tryOpen(groupId, blob, epoch, version, candidate) !=
            null) {
      await _keyring.promote(groupId, epoch, candidate);
      return candidate;
    }
    return null;
  }

  /// The key a state write for [epoch] must be sealed under: the held key
  /// that opens the stored state, else the primary (nothing has confirmed a
  /// better one yet). Null when this device holds no key for [epoch].
  Future<Uint8List?> keyForWrite(
    String groupId, {
    required int epoch,
    required List<int>? state,
    required int version,
  }) async {
    if (state != null) {
      final opened = await keyThatOpens(
        groupId,
        state,
        epoch: epoch,
        version: version,
      );
      if (opened != null) return opened;
    }
    return _keyring.keyFor(groupId, epoch);
  }

  /// Opens [blob] with every held epoch, primary and second keys alike, and
  /// promotes the key that opens it.
  Future<GroupStateContent?> openState(
    String groupId,
    List<int> blob, {
    required int epoch,
    required int version,
  }) async {
    final opened = await _keyring.openStateWithKey(
      groupId,
      blob,
      epoch: epoch,
      version: version,
    );
    if (opened == null) return null;
    await _keyring.promote(groupId, opened.epoch, opened.key);
    return opened.content;
  }

  /// Stores a key this device minted for [epoch] (create, rotation); a key
  /// already held for the epoch stays as the second one.
  Future<void> storeMinted(String groupId, int epoch, List<int> key) =>
      _keyring.promote(groupId, epoch, key);

  static bool _same(List<int>? held, List<int> key) =>
      held != null && bytesEqual(held, key);
}
