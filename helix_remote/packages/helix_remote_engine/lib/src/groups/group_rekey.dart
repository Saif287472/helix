import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_engine/src/groups/group_keyring.dart';
import 'package:helix_remote_engine/src/groups/group_roster.dart';
import 'package:helix_remote_engine/src/groups/group_trust.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Hands the group master key to members (`group_key` content over their
/// pairwise sessions, CRYPTO_V2.md §9) and rotates it.
///
/// A new member needs the key of the current epoch to read the group's name
/// and picture; it comes from whoever added them (or, for a link join, the
/// first admin by account id). After a removal, a leave or a ban the epoch
/// is bumped by the server and the key must change: the removed member held
/// the old one. The member responsible (the remover, else the first admin)
/// makes a new key, queues it to every remaining member and re-seals the
/// state under it. A removed member still holding the old key can read the
/// old state but nothing written after.
final class GroupKeyDistributor {
  GroupKeyDistributor(
    this._ctx,
    this._keyring,
    this._outbox,
    this._roster,
    this._trust,
  );

  final EngineContext _ctx;
  final GroupKeyring _keyring;
  final OutboxService _outbox;
  final GroupRosterSync _roster;
  final GroupTrust _trust;

  HelixDb get _db => _ctx.db;

  /// Queues the key of [epoch] (default: the group's current epoch) for
  /// [accounts]. Returns false when this device holds no such key.
  Future<bool> share(
    String groupId,
    Iterable<String> accounts, {
    int? epoch,
  }) async {
    // Members this account has not confirmed get no key (GroupTrust).
    final withheld = (await _trust.pending(groupId)).keys;
    final audience = accounts.toSet()..removeAll(withheld);
    if (audience.isEmpty) return true;
    final group = await _db.groupsDao.byId(groupId);
    final at = epoch ?? group?.epoch;
    if (at == null) return false;
    final key = await _keyring.keyFor(groupId, at);
    if (key == null) return false;
    final profileKey = (await _db.accountDao.current())?.profileKey;
    await _outbox.enqueueContent(
      content: ContentMessage(
        id: _ctx.ids.next(),
        sentAt: _ctx.now(),
        conversation: GroupConversation(group: groupId),
        body: GroupKeyBody(groupId: groupId, epoch: at, key: key),
        profileKey: profileKey == null ? null : Uint8List.fromList(profileKey),
      ),
      // This account's own account id reaches its other devices.
      audience: audience,
      urgent: false,
    );
    return true;
  }

  /// Hands every held current key to this account's other devices (a device
  /// was linked: it has no group keys, and the other devices are the only
  /// ones that can give them).
  Future<void> shareAllWithOwnDevices() async {
    final self = _ctx.identity.accountId;
    for (final archived in [false, true]) {
      for (final group in await _db.groupsDao.all(archived: archived)) {
        await share(group.id, [self]);
      }
    }
  }

  /// The `group_rekey` op: reads the group, makes (or reuses) the key of its
  /// current epoch, queues it to the members and re-seals the state.
  /// Idempotent: a repeated run finds the state already sealed under the
  /// key and stops.
  Future<void> rekey(String groupId) async {
    var attempts = GroupLimits.stateRetries;
    while (true) {
      final update = await _roster.refresh(groupId);
      if (update == null) return; // Not a member any more: nothing to do.
      final group = update.group;
      final epoch = group.epoch;
      var key = await _keyring.keyFor(groupId, epoch);
      final blob = group.state;
      if (key != null &&
          blob != null &&
          await _keyring.tryOpen(
                groupId,
                blob,
                epoch,
                group.stateVersion,
                key,
              ) !=
              null) {
        return; // Already rotated and sealed.
      }
      var state = blob == null
          ? null
          : await _keyring.openState(
              groupId,
              blob,
              epoch: epoch,
              version: group.stateVersion,
            );
      if (state == null) {
        // The previous key never reached this device: the name cannot be
        // carried over, and an empty one must not replace it.
        if (group.title.isEmpty) {
          throw const GroupException(GroupFailure.noGroupKey);
        }
        state = GroupStateContent(name: group.title);
      }
      if (key == null) {
        key = newSymmetricKey(_ctx.random);
        await _keyring.put(groupId, epoch, key);
      }
      final members = [
        for (final m in await _db.groupsDao.members(groupId)) m.accountId,
      ];
      // Queue the key first: if the state write fails, a retry re-seals
      // and members already hold the key.
      await share(groupId, members, epoch: epoch);
      final next = group.stateVersion + 1;
      final sealed = await _keyring.sealState(groupId, epoch, next, key, state);
      try {
        final result = await _ctx.api.groups.setState(
          groupId,
          SetGroupStateRequest(
            encryptedState: sealed,
            expectedVersion: group.stateVersion,
          ),
        );
        if (result.stateVersion != next) {
          // Numbered differently by the server: unreadable, so not stored;
          // the next pass reads the group again and re-seals.
          if (--attempts <= 0) {
            throw const GroupException(GroupFailure.versionConflict);
          }
          continue;
        }
        await _db.groupsDao.saveState(
          groupId,
          state: sealed,
          version: result.stateVersion,
        );
        return;
      } on ApiException catch (e) {
        if (e.code != ErrorCode.versionConflict || --attempts <= 0) rethrow;
      }
    }
  }

  /// Whether this account is the one that owes a group its key work: the first
  /// admin (or owner) by account id, ignoring [exclude] - whoever a roster
  /// change is about, before the local roster has caught up. One rule for the
  /// duty a roster envelope triggers and the one maintenance re-derives.
  Future<bool> isFirstAdmin(
    String groupId, {
    required Set<String> exclude,
  }) async {
    final self = _ctx.identity.accountId;
    final admins = [
      for (final m in await _db.groupsDao.members(groupId))
        if ((m.role == GroupRole.owner.wire ||
                m.role == GroupRole.admin.wire) &&
            !exclude.contains(m.accountId))
          m.accountId,
    ]..sort();
    return admins.isNotEmpty && admins.first == self;
  }

  /// The rotation duty re-derived from state (AUD-12b-1). A removal bumps the
  /// epoch and one device rotates the key and re-seals the group's state under
  /// it; when that op is lost - given up before the retry policy existed,
  /// dropped by a crash at the wrong moment, or never queued because this
  /// device was not running when the roster envelope arrived - the group's name
  /// and picture stay unwriteable for every member and the state the removed
  /// member can still read is never replaced.
  ///
  /// So the duty is read back from what it is supposed to achieve: a group
  /// whose stored state does not open under a key this device holds for the
  /// current epoch, and which this account owes, is asked for a rotation again.
  /// [OutboxService.enqueueRekey] keys the duty by group and epoch, so a pass
  /// that finds it queued changes nothing and one that finds it failed puts it
  /// back; when the rotation lands the state opens and the pass stops asking.
  /// A duty that keeps failing is re-asked [GroupLimits.rekeyDutyRetries]
  /// times and then left for an admin, so a server that refuses this account
  /// costs one request per pass up to that bound instead of forever. Archived
  /// groups count too: archiving is this device's list, not the roster.
  Future<void> reconcileRekeyDuties() async {
    for (final archived in [false, true]) {
      for (final group in await _db.groupsDao.all(archived: archived)) {
        final blob = group.state;
        // Nothing has ever been sealed: the name is the server's plain column
        // and no reader is holding a key that has to be replaced.
        if (blob == null) continue;
        final key = await _keyring.keyFor(group.id, group.epoch);
        if (key != null &&
            await _keyring.tryOpen(
                  group.id,
                  blob,
                  group.epoch,
                  group.stateVersion,
                  key,
                ) !=
                null) {
          continue; // Rotated and sealed: the duty is done.
        }
        if (!await isFirstAdmin(group.id, exclude: const {})) continue;
        await _outbox.enqueueRekey(
          group.id,
          group.epoch,
          reaskMaxAttempts: GroupLimits.rekeyDutyRetries,
        );
      }
    }
  }
}
