import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/local_identity.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_engine/src/groups/group_keyring.dart';
import 'package:helix_remote_engine/src/groups/group_trust.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/peers.dart';

/// The stores behind group trust and the group keys are per-entry settings
/// rows (AUD-12e-2). A document read-modify-written from four actors could
/// lose a write; a confirm landing after a roster apply released the member
/// the apply had just held back, and two rotations could drop an epoch key.
/// These drive the stores directly, which is where the interleaving is
/// deterministic: both reads are issued before either write.
void main() {
  const groupId = 'group-store-test';

  Future<({Peer peer, GroupTrust trust, GroupKeyring keyring})> start(
    Peers peers,
  ) async {
    final alice = await peers.register('alice');
    final context = EngineContext(
      api: alice.api,
      db: alice.db,
      clock: peers.clock.call,
      random: SeededRandom('group-store'),
      config: fastConfig,
    );
    context.setIdentity(await LocalIdentity.load(alice.db));
    return (
      peer: alice,
      trust: GroupTrust(context),
      keyring: GroupKeyring(context),
    );
  }

  test('a confirm cannot drop a member the roster holds back at the same '
      'time', () async {
    final peers = Peers();
    addTearDown(peers.dispose);
    final rig = await start(peers);
    await rig.trust.addPending(groupId, 'a', PendingReasons.linkJoin);

    final holdingBack = rig.trust.addPending(
      groupId,
      'b',
      PendingReasons.unattributed,
    );
    final confirming = rig.trust.confirm(groupId, 'a');
    await holdingBack;
    expect(await confirming, isTrue);

    expect(await rig.trust.pending(groupId), {
      'b': PendingReasons.unattributed,
    }, reason: 'the confirm released A and nothing else');
  });

  test('two explanations landing at once are both remembered', () async {
    final peers = Peers();
    addTearDown(peers.dispose);
    final rig = await start(peers);

    final first = rig.trust.explain(groupId, ['a']);
    final second = rig.trust.explain(groupId, ['b']);
    await first;
    await second;

    expect(await rig.trust.takeExplained(groupId, 'a'), isTrue);
    expect(await rig.trust.takeExplained(groupId, 'b'), isTrue);
  });

  test('two epoch keys stored at once both survive', () async {
    final peers = Peers();
    addTearDown(peers.dispose);
    final rig = await start(peers);
    final first = Uint8List.fromList(List.filled(32, 1));
    final second = Uint8List.fromList(List.filled(32, 2));
    final third = Uint8List.fromList(List.filled(32, 3));
    await rig.keyring.put(groupId, 1, first);

    final epochTwo = rig.keyring.put(groupId, 2, second);
    final epochThree = rig.keyring.put(groupId, 3, third);
    await epochTwo;
    await epochThree;

    final held = await rig.keyring.keys(groupId);
    expect(held.keys.toList()..sort(), [1, 2, 3]);
    expect(held[2], second);
    expect(held[3], third);
  });

  test('the newest keys are kept and the oldest dropped', () async {
    final peers = Peers();
    addTearDown(peers.dispose);
    final rig = await start(peers);
    for (var epoch = 1; epoch <= GroupLimits.keptEpochKeys + 1; epoch++) {
      await rig.keyring.put(
        groupId,
        epoch,
        Uint8List.fromList(List.filled(32, epoch)),
      );
    }
    final held = await rig.keyring.keys(groupId);
    expect(held.keys.toList()..sort(), [
      for (var e = 2; e <= GroupLimits.keptEpochKeys + 1; e++) e,
    ]);
  });

  test('the one-document trust records are migrated on first read', () async {
    final peers = Peers();
    addTearDown(peers.dispose);
    final rig = await start(peers);
    final db = rig.peer.db;
    const pending = Setting<String?>('group.pending.$groupId', null);
    const explained = Setting<String?>('group.explained.$groupId', null);
    await db.settingsDao.set(
      pending,
      jsonEncode({
        'a': PendingReasons.unattributed,
        'b': PendingReasons.linkJoin,
      }),
    );
    await db.settingsDao.set(explained, jsonEncode(['c']));

    expect(await rig.trust.pending(groupId), {
      'a': PendingReasons.unattributed,
      'b': PendingReasons.linkJoin,
    });
    expect(await rig.trust.takeExplained(groupId, 'c'), isTrue);
    expect(await rig.trust.takeExplained(groupId, 'c'), isFalse);
    expect(await db.settingsDao.get(pending), isNull);
    expect(await db.settingsDao.get(explained), isNull);
    expect(await rig.trust.confirm(groupId, 'a'), isTrue);
    expect(await rig.trust.pending(groupId), {'b': PendingReasons.linkJoin});
  });

  test('the one-document key map is migrated on first read', () async {
    final peers = Peers();
    addTearDown(peers.dispose);
    final rig = await start(peers);
    final db = rig.peer.db;
    const legacy = Setting<String?>('group.keys.$groupId', null);
    final first = Uint8List.fromList(List.filled(32, 7));
    final second = Uint8List.fromList(List.filled(32, 8));
    await db.settingsDao.set(
      legacy,
      jsonEncode({'1': encodeBytes(first), '2': encodeBytes(second)}),
    );

    final held = await rig.keyring.keys(groupId);
    expect(held[1], first);
    expect(held[2], second);
    expect(await db.settingsDao.get(legacy), isNull);
  });

  test('the one-document metadata is migrated, and its halves no longer '
      'overwrite each other', () async {
    final peers = Peers();
    addTearDown(peers.dispose);
    final rig = await start(peers);
    final db = rig.peer.db;
    const legacy = Setting<String?>('group.meta.$groupId', null);
    const old = GroupMeta(
      settings: GroupSettings(addMembers: GroupPermission.everyone),
      description: 'old',
      homeServer: 'old.example',
      avatar: {'media': 'old'},
    );
    await db.settingsDao.set(legacy, jsonEncode(old.toJson()));

    final migrated = await rig.keyring.meta(groupId);
    expect(migrated.settings.addMembers, GroupPermission.everyone);
    expect(migrated.description, 'old');
    expect(migrated.homeServer, 'old.example');
    expect(migrated.avatar, {'media': 'old'});
    expect(await db.settingsDao.get(legacy), isNull);

    // The server's fields and the state's fields are separate rows now: the
    // writers cannot restore each other's old values.
    await rig.keyring.saveServerMeta(
      groupId,
      settings: const GroupSettings(addMembers: GroupPermission.admins),
    );
    await rig.keyring.saveContentMeta(groupId, description: 'new');
    final after = await rig.keyring.meta(groupId);
    expect(after.settings.addMembers, GroupPermission.admins);
    expect(after.homeServer, isNull);
    expect(after.description, 'new');
    expect(after.avatar, isNull);
  });
}
