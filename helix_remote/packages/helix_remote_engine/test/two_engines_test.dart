import 'dart:io';

import 'package:helix_remote_crypto/v2.dart'
    show DeviceAddress, OwnSenderKeyWrite;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/db_stores.dart';
import 'package:helix_remote_engine/src/crypto/local_identity.dart';
import 'package:helix_remote_engine/src/crypto/pairwise_crypto.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:helix_remote_engine/src/groups/sender_key_store.dart';
import 'package:test/test.dart';

import 'support/fake_groups.dart';
import 'support/peers.dart';

/// Two engines over one database file (review finding C-01).
///
/// The app and its FCM background isolate are two engines on the same SQLCipher
/// file. The per-device locks are per engine, so nothing stopped them from
/// reading the same ratchet state and both committing it: a lost update
/// corrupts the ratchet, and two sends from the same sending chain encrypt
/// under one AES-GCM key and nonce, which leaks their XOR and the GHASH key.
/// `sessions.version` (a compare-and-set, see `CryptoDao.saveSessions`) turns
/// the second commit into a refusal the engine retries from the state the
/// winner committed.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('helix_two_engines');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on Object {
      // A file still held by the run is not worth failing for.
    }
  });

  /// The same account and device, registered once, then driven by two engines
  /// that each open the file on their own. Both talk to one fake server as the
  /// same device, which is what the app and its push isolate do.
  Future<(Peers, Peer, Peer, Peer)> withTwoEnginesOnOneFile() async {
    final peers = Peers();
    final bob = await peers.register('bob', phone: '+8801711000002');

    final file = File('${tmp.path}/helix.db');
    final key = DatabaseKey.generate();
    // Background opening, like the app: each engine then has its own drift
    // isolate, so the two really are two connections on one file (two engines
    // in one isolate could not interleave writes at all).
    final aliceDb = await HelixDb.open(file, key: key);
    final alice = await peers.create('alice', db: aliceDb);
    final challenge = await alice.engine.account.requestPhoneCode(
      '+8801711000001',
    );
    final verified = await alice.engine.account.verifyPhone(
      challenge.challengeId,
      '123456',
    );
    await alice.engine.account.register(
      verificationToken: verified.verificationToken,
      phoneNumber: '+8801711000001',
    );

    // The second engine opens the same file with the same key.
    final secondDb = await HelixDb.open(file, key: key);
    final other = await peers.create('alice-again', db: secondDb);
    expect(other.account, alice.account);
    expect(other.device, alice.device);
    return (peers, alice, other, bob);
  }

  test(
    'both engines can send to the same peer device, and both arrive',
    () async {
      final (peers, alice, other, bob) = await withTwoEnginesOnOneFile();
      addTearDown(peers.dispose);

      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'from the app');
      await alice.engine.drainOutbox();

      // The push isolate's engine, over the same database file: it loads the
      // state the first engine committed and sends on from it.
      final otherChat = await other.engine.chats.openDirect(bob.account);
      await other.engine.chats.sendText(otherChat.id, 'from the push isolate');
      await other.engine.drainOutbox();

      await bob.sync();
      expect(await bob.texts(alice), ['from the app', 'from the push isolate']);
    },
  );

  test(
    'two engines encrypting at once do not commit the same ratchet state',
    () async {
      final (peers, alice, other, bob) = await withTwoEnginesOnOneFile();
      addTearDown(peers.dispose);

      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'first');
      await alice.engine.drainOutbox();
      final remote = DeviceAddress(bob.account, bob.device);
      final before = await alice.db.cryptoDao.sessionsVersion(
        remote.account,
        remote.device,
      );

      // Both engines queue a send and are drained together: each reads the
      // stored state, encrypts and commits, and whichever loses the
      // compare-and-set retries from the state the winner committed. The
      // revision therefore rises by one per committed send, never less.
      await alice.engine.chats.sendText(chat.id, 'from the app');
      await other.engine.chats.sendText(chat.id, 'from the isolate');
      await Future.wait([
        alice.engine.drainOutbox(),
        other.engine.drainOutbox(),
      ]);

      final after = await alice.db.cryptoDao.sessionsVersion(
        remote.account,
        remote.device,
      );
      expect(
        after - before,
        2,
        reason: 'two sends, two committed ratchet states',
      );

      // Both messages decrypt at the peer: nothing was sent under a reused
      // key and nonce, and nothing was lost.
      await bob.sync();
      final texts = await bob.texts(alice);
      expect(texts, containsAll(['from the app', 'from the isolate']));
      final rows = (await bob.db.messagesDao.pageOlder(
        bob.chatWith(alice),
        limit: 50,
      )).messages;
      expect(
        rows.where((m) => m.kind == MessageKinds.undecryptable),
        isEmpty,
        reason: 'the ratchet stayed consistent on both sides',
      );
    },
  );

  test(
    'a locked block retries from the state the other engine committed',
    () async {
      final peers = Peers();
      addTearDown(peers.dispose);
      final alice = await peers.register('alice');
      final bob = await peers.register('bob');
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'first');
      await alice.engine.drainOutbox();

      // The retry loop of `PairwiseCrypto.locked`, driven the way a second
      // engine would drive it: the first attempt is made to lose, the second
      // must work from what the winner committed.
      final remote = DeviceAddress(bob.account, bob.device);
      final store = DbSessionStore(alice.db);
      final other = DbSessionStore(alice.db);
      final context = EngineContext(
        api: alice.api,
        db: alice.db,
        clock: peers.clock.call,
        random: SeededRandom('two-engines'),
        config: fastConfig,
      );
      context.setIdentity(await LocalIdentity.load(alice.db));
      final pairwise = PairwiseCrypto(context, PeerDirectory(context));
      var attempts = 0;
      final firstVersion = await pairwise.locked(remote, () async {
        attempts++;
        final current = (await store.load(remote))!;
        if (attempts == 1) {
          // Another engine commits while this attempt is in flight.
          final winner = (await other.load(remote))!;
          await other.save(
            winner.withUpdated(0, winner.active!),
            now: DateTime.utc(2026, 10, 9),
          );
        }
        await store.save(current, now: DateTime.utc(2026, 10, 9));
        return current.version;
      });

      expect(attempts, 2, reason: 'the first attempt lost, the second landed');
      // The second attempt started from the winner's state, so it read a
      // version one higher than the attempt that lost.
      expect(firstVersion, greaterThan(0));
      final stored = (await store.load(remote))!;
      expect(stored.version, greaterThan(firstVersion));
    },
  );

  test('two engines sending to a group at once never send from one sender-key '
      'step', () async {
    final (peers, alice, other, bob) = await withTwoEnginesOnOneFile();
    addTearDown(peers.dispose);
    FakeGroups(peers.server);

    final created = await alice.engine.groups.create(
      name: 'Weekend',
      members: [bob.account],
    );
    final groupId = created.groupId;
    final conversation = GroupIds.conversationId(groupId);
    await alice.engine.chats.sendText(conversation, 'first');
    await alice.engine.drainOutbox();
    await bob.sync();
    Future<int> revision() => alice.db.cryptoDao.ownSenderKeyVersion(
      groupId: groupId,
      account: alice.account,
      device: alice.device,
    );
    final before = await revision();
    expect(before, greaterThan(0));

    // Both engines queue a group send and are drained together. The sender
    // key's chain is one sequence: whichever commits second is refused
    // (`StaleSenderKeyState`) and encrypts again from the step the first
    // one stored.
    await alice.engine.chats.sendText(conversation, 'from the app');
    await other.engine.chats.sendText(conversation, 'from the isolate');
    await Future.wait([alice.engine.drainOutbox(), other.engine.drainOutbox()]);
    expect(
      await revision() - before,
      greaterThanOrEqualTo(2),
      reason: 'one committed step per send, never one for both',
    );

    await bob.sync();
    final rows = (await bob.db.messagesDao.pageOlder(
      conversation,
      limit: 50,
    )).messages;
    expect([
      for (final m in rows)
        if (m.kind == 'text') m.body,
    ], containsAll(['first', 'from the app', 'from the isolate']));
    expect(
      rows.where((m) => m.kind == MessageKinds.undecryptable),
      isEmpty,
      reason: 'both arrived under their own key and nonce',
    );
  });

  test(
    'a stale own sender key write is refused, and nothing changes',
    () async {
      final (peers, alice, other, bob) = await withTwoEnginesOnOneFile();
      addTearDown(peers.dispose);
      FakeGroups(peers.server);
      final created = await alice.engine.groups.create(
        name: 'Weekend',
        members: [bob.account],
      );
      final groupId = created.groupId;
      final conversation = GroupIds.conversationId(groupId);
      await alice.engine.chats.sendText(conversation, 'hello');
      await alice.engine.drainOutbox();

      // Two stores over one file: what two engines have.
      Future<DbSenderKeyStore> storeOn(Peer peer) async {
        final context = EngineContext(
          api: peer.api,
          db: peer.db,
          clock: peers.clock.call,
          random: SeededRandom('two-engines'),
          config: fastConfig,
        );
        context.setIdentity(await LocalIdentity.load(peer.db));
        return DbSenderKeyStore(context);
      }

      final first = await storeOn(alice);
      final second = await storeOn(other);
      final stale = (await first.ownKey(groupId))!;
      final current = (await second.ownKey(groupId))!;
      await second.commit([OwnSenderKeyWrite(current)]);

      await expectLater(
        first.commit([OwnSenderKeyWrite(stale)]),
        throwsA(
          isA<StaleSenderKeyState>().having(
            (e) => e.groupId,
            'groupId',
            groupId,
          ),
        ),
      );
      // After a fresh read the same store writes again.
      final reread = (await first.ownKey(groupId))!;
      await first.commit([OwnSenderKeyWrite(reread)]);
    },
  );

  test('a stale write is refused, and the state that won is kept', () async {
    final (peers, alice, _, bob) = await withTwoEnginesOnOneFile();
    addTearDown(peers.dispose);

    final chat = await alice.engine.chats.openDirect(bob.account);
    await alice.engine.chats.sendText(chat.id, 'hello');
    await alice.engine.drainOutbox();

    final remote = DeviceAddress(bob.account, bob.device);
    // Two stores over the same database: what two engines have.
    final first = DbSessionStore(alice.db);
    final second = DbSessionStore(alice.db);
    final stale = (await first.load(remote))!;

    final current = (await second.load(remote))!;
    final advanced = current.withUpdated(0, current.active!);
    await second.save(advanced, now: DateTime.utc(2026, 10, 9));

    await expectLater(
      first.save(stale, now: DateTime.utc(2026, 10, 9)),
      throwsA(
        isA<StaleSessionState>().having((e) => e.remote, 'remote', remote),
      ),
    );
    expect((await first.load(remote))!.encode(), advanced.encode());
  });
}
