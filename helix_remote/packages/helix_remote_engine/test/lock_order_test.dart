import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart' show DeviceAddress;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/db_stores.dart';
import 'package:helix_remote_engine/src/crypto/local_identity.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// A device lock and a database transaction: locks outermost, transactions
/// innermost, never the other way round (AUD-12d-1).
///
/// `PeerDirectory` used to clear a device's sessions *while its caller's
/// transaction was open* - a key change and a device drop took the per-device
/// lock inside that transaction. Every hot path does the opposite: a send
/// (`PairwiseCrypto.encryptFor`) and an inbound apply hold the device's lock
/// and open their transaction after, and drift serializes transactions on this
/// engine's single connection. So the two could wait on each other with no
/// timeout - the inbound queue stalls on one envelope, the outbox worker's op
/// never returns and the chat shows "sending" until the app is killed. The same
/// wait also happened inside a single task, because the engine's `KeyedLock` is
/// not re-entrant: an inbound prekey message from an account whose key just
/// changed is applied under that device's lock, and resolving its identity
/// reaches the same clearing.
///
/// Each test is the overlapping pair: a task that holds a device's lock and
/// then writes through a transaction (the order of a send), and a directory
/// call that retires that device's sessions. Both must finish.

/// One peer's engine plus the parts of it these tests drive by hand.
final class Rig {
  Rig(this.peers, this.alice, this.bob, this.context, this.store, this.remote);

  final Peers peers;
  final Peer alice;
  final Peer bob;
  final EngineContext context;
  final DbSessionStore store;
  final DeviceAddress remote;

  late final PeerDirectory directory = PeerDirectory(context);
}

void main() {
  Future<Rig> startRig(Peers peers) async {
    final alice = await peers.register('alice', phone: '+8801711000001');
    final bob = await peers.register('bob', phone: '+8801711000002');
    final chat = await alice.engine.chats.openDirect(bob.account);
    await alice.engine.chats.sendText(chat.id, 'hi');
    await alice.engine.drainOutbox();
    final remote = DeviceAddress(bob.account, bob.device);
    final context = EngineContext(
      api: alice.api,
      db: alice.db,
      clock: peers.clock.call,
      random: SeededRandom('lock-order'),
      config: fastConfig,
    );
    context.setIdentity(await LocalIdentity.load(alice.db));
    return Rig(peers, alice, bob, context, DbSessionStore(alice.db), remote);
  }

  /// The send-shaped task: it holds [remote]'s lock, waits until the directory
  /// call is under way, and only then reads and writes through the database -
  /// which is where the two orders meet.
  Future<void> lockHolder(
    Rig rig, {
    required Completer<void> holds,
    required Completer<void> released,
  }) => rig.context.deviceLocks.run(rig.remote, () async {
    holds.complete();
    await released.future;
    final sessions = await rig.store.load(rig.remote);
    if (sessions != null) {
      await rig.context.db.transaction(
        () => rig.store.save(sessions, now: DateTime.utc(2026, 10, 25)),
      );
    }
  });

  /// Releases the holder and waits for both tasks: a pair that waits on each
  /// other never returns, so this is the assertion.
  Future<void> bothFinish(
    Future<void> directoryCall,
    Future<void> holder,
    Completer<void> released,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    released.complete();
    await Future.wait([directoryCall, holder]).timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw StateError(
        'the device lock and the open transaction waited on each other '
        '(AUD-12d-1)',
      ),
    );
  }

  test(
    'a key change and a session write on one device finish together',
    () async {
      final peers = Peers();
      addTearDown(peers.dispose);
      final rig = await startRig(peers);
      expect(
        await rig.store.load(rig.remote),
        isNotNull,
        reason: 'a session with the peer exists first',
      );

      // The pinned key is no longer the one the server serves, so the next
      // fetch of Bob's keys is a key change - and a key change retires every
      // session with his devices.
      await rig.alice.db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: rig.bob.account,
          identityKey: Value(Uint8List(32)),
          updatedAt: peers.clock.call(),
        ),
      );

      final holds = Completer<void>();
      final released = Completer<void>();
      final holder = lockHolder(rig, holds: holds, released: released);
      await holds.future;
      final fetching = rig.directory.fetch(rig.bob.account);
      // The fetch is past its network call, so it is inside the transaction that
      // used to take the lock here.
      while (!peers.server.calls.any((c) => c.contains('/keys/'))) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await bothFinish(fetching, holder, released);

      // The key change did all of its work: the new key is pinned, the session
      // is gone, and the chat says so.
      expect(
        peers.server.accounts[rig.bob.account]!.identityKey,
        (await rig.alice.db.peopleDao.byAccount(rig.bob.account))!.identityKey,
      );
      expect((await rig.store.load(rig.remote))?.active, isNull);
      final rows = (await rig.alice.db.messagesDao.pageOlder(
        rig.alice.chatWith(rig.bob),
        limit: 50,
      )).messages;
      expect(
        rows.where(
          (m) => (m.payload ?? '').contains(MessageKinds.safetyNumberChanged),
        ),
        isNotEmpty,
      );
    },
  );

  test('a dropped device and a session write on it finish together', () async {
    final peers = Peers();
    addTearDown(peers.dispose);
    final rig = await startRig(peers);

    final holds = Completer<void>();
    final released = Completer<void>();
    final holder = lockHolder(rig, holds: holds, released: released);
    await holds.future;
    // A `device_list_stale` answer forgets a device that is gone - which also
    // means its sessions.
    final dropping = rig.directory.dropDevice(rig.bob.account, rig.bob.device);
    await bothFinish(dropping, holder, released);

    expect(await rig.alice.db.peopleDao.devicesOf(rig.bob.account), isEmpty);
    expect((await rig.store.load(rig.remote))?.active, isNull);
  });
}
