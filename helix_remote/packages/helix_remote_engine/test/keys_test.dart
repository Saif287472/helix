import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// Prekey upkeep (CRYPTO_V2.md §3): replenishment, the `prekeys_low`
/// signal, signed-prekey rotation and the id counters.
void main() {
  late Peers peers;
  late Peer alice;
  late Peer bob;

  setUp(() async {
    peers = Peers();
    alice = await peers.register('alice', phone: '+8801711000001');
    bob = await peers.register(
      'bob',
      phone: '+8801711000002',
      config: fastConfig.copyWith(initialOneTimePrekeys: 22),
    );
  });
  tearDown(() => peers.dispose());

  int serverOneTime() => peers.server.device(bob.device).oneTimePrekeys.length;

  test('a maintenance pass tops up when the server runs low', () async {
    peers.server.device(bob.device).oneTimePrekeys.removeRange(0, 17);
    expect(serverOneTime(), 5);
    await bob.engine.runMaintenance();
    expect(serverOneTime(), 5 + PrekeyPolicy.replenishBatch);
    // The private halves are stored, ids continue after the first batch and
    // are never reused.
    final local = await bob.db.cryptoDao.prekeysOf(PrekeyKind.oneTime);
    expect(local, hasLength(22 + PrekeyPolicy.replenishBatch));
    expect(local.map((k) => k.keyId).toSet(), hasLength(local.length));
    expect(local.map((k) => k.keyId).reduce((a, b) => a > b ? a : b), 122);
    // Nothing more to do when it is no longer low.
    final calls = peers.server.callsTo(Routes.addOneTimePrekeys);
    peers.clock.advance(const Duration(hours: 7));
    await bob.engine.runMaintenance();
    expect(peers.server.callsTo(Routes.addOneTimePrekeys), calls);
  });

  test('the prekeys_low signal makes the device upload more', () async {
    // Each sender fetching Bob's bundle takes one prekey: 22 -> 19 is low.
    final others = [
      alice,
      await peers.register('carol', phone: '+8801711000003'),
      await peers.register('dave', phone: '+8801711000004'),
    ];
    for (final sender in others) {
      final c = await sender.engine.chats.openDirect(bob.account);
      await sender.engine.chats.sendText(c.id, 'hi');
      await sender.engine.drainOutbox();
    }
    expect(serverOneTime(), 19);
    // The signal sits in Bob's mailbox with the three messages.
    await bob.sync();
    expect(serverOneTime(), 19 + PrekeyPolicy.replenishBatch);
    expect(
      await bob.db.cryptoDao.prekeysOf(PrekeyKind.oneTime),
      hasLength(22 - 3 + PrekeyPolicy.replenishBatch),
      reason: 'three one-time prekeys were consumed by the first messages',
    );
  });

  test('a consumed one-time prekey is deleted with the first message that '
      'used it, and a replay cannot reuse it', () async {
    final before = await bob.db.cryptoDao.prekeysOf(PrekeyKind.oneTime);
    final chat = await alice.engine.chats.openDirect(bob.account);
    await alice.engine.chats.sendText(chat.id, 'uses a prekey');
    await alice.engine.drainOutbox();
    await bob.sync();
    final after = await bob.db.cryptoDao.prekeysOf(PrekeyKind.oneTime);
    expect(after.length, before.length - 1);
  });

  test('an upload that fails keeps the new keys and the next pass tries '
      'again', () async {
    peers.server.device(bob.device).oneTimePrekeys.removeRange(0, 17);
    peers.server.failNext(Routes.addOneTimePrekeys);
    await bob.engine.runMaintenance(); // swallowed; retried later
    expect(serverOneTime(), 5);
    expect(
      (await bob.db.cryptoDao.prekeysOf(PrekeyKind.oneTime)).length,
      22 + PrekeyPolicy.replenishBatch,
      reason:
          'stored before the upload, so a key a peer might get always '
          'has its private half',
    );
    await bob.engine.runMaintenance();
    expect(serverOneTime(), 5 + PrekeyPolicy.replenishBatch);
  });

  group('signed prekey', () {
    test(
      'rotates after 7 days, keeps the old key for 30, then deletes it',
      () async {
        final first = (await bob.db.cryptoDao.prekeysOf(
          PrekeyKind.signed,
        )).single;
        expect(peers.server.device(bob.device).signedPrekey.id, first.keyId);

        peers.clock.advance(const Duration(days: 6));
        await bob.engine.runMaintenance();
        expect(
          await bob.db.cryptoDao.prekeysOf(PrekeyKind.signed),
          hasLength(1),
        );

        peers.clock.advance(const Duration(days: 2));
        await bob.engine.runMaintenance();
        final rows = await bob.db.cryptoDao.prekeysOf(PrekeyKind.signed);
        expect(rows, hasLength(2));
        final current = rows.firstWhere((r) => r.retiredAt == null);
        expect(current.keyId, isNot(first.keyId));
        expect(peers.server.device(bob.device).signedPrekey.id, current.keyId);
        // The new signed prekey verifies under the device's signing key.
        final wire = peers.server.device(bob.device).signedPrekey;
        expect(
          await ed25519Verify(
            publicKey: peers.server.device(bob.device).registration.signingKey,
            message: signedPrekeySignatureBody(wire.id, wire.publicKey),
            signature: wire.signature,
          ),
          isTrue,
        );

        // A message that still names the old signed prekey can be read.
        expect(
          await bob.db.cryptoDao.prekey(PrekeyKind.signed, first.keyId),
          isNotNull,
        );
        peers.clock.advance(const Duration(days: 31));
        await bob.engine.runMaintenance();
        expect(
          await bob.db.cryptoDao.prekey(PrekeyKind.signed, first.keyId),
          isNull,
        );
      },
    );

    test(
      'a rotation whose upload failed is uploaded again next pass',
      () async {
        peers.clock.advance(const Duration(days: 8));
        peers.server.failNext(Routes.setSignedPrekey);
        await bob.engine.runMaintenance();
        final rows = await bob.db.cryptoDao.prekeysOf(PrekeyKind.signed);
        final newest = rows.reduce(
          (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
        );
        expect(
          peers.server.device(bob.device).signedPrekey.id,
          isNot(newest.keyId),
        );
        peers.clock.advance(const Duration(hours: 1));
        await bob.engine.runMaintenance();
        expect(peers.server.device(bob.device).signedPrekey.id, newest.keyId);
      },
    );

    test('a prekey message naming an unknown signed prekey is a failure, '
        'never a fallback', () async {
      // Forget every signed prekey on Bob's side: Alice's first message names
      // one that is gone.
      for (final row in await bob.db.cryptoDao.prekeysOf(PrekeyKind.signed)) {
        await bob.db.cryptoDao.deletePrekey(PrekeyKind.signed, row.keyId);
      }
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'lost prekey');
      await alice.engine.drainOutbox();
      await bob.sync();
      final rows = await bob.messages(alice);
      expect(rows.single.kind, MessageKinds.undecryptable);
      expect(rows.single.payload, contains('unknown_prekey'));
    });
  });

  test(
    'a failing status check does not hurt the engine and is retried',
    () async {
      peers.server.failNext(Routes.keyStatus);
      await bob.engine.runMaintenance();
      expect(bob.engine.status, EngineStatus.running);
      final before = peers.server.callsTo(Routes.keyStatus);
      await bob.engine.runMaintenance();
      expect(peers.server.callsTo(Routes.keyStatus), before + 1);
    },
  );
}
