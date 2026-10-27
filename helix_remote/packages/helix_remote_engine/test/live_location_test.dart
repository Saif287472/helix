import 'dart:convert';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// Live location: a `start` message, then quiet updates and a stop that move
/// or end the place in it.
void main() {
  late Peers peers;
  late Peer alice;
  late Peer bob;

  setUp(() async {
    peers = Peers();
    alice = await peers.register('alice', phone: '+8801711000001');
    bob = await peers.register('bob', phone: '+8801711000002');
  });
  tearDown(() => peers.dispose());

  Future<({MessageRow mine, MessageRow theirs})> start({
    Duration duration = const Duration(minutes: 15),
  }) async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    final mine = await alice.engine.chats.startLiveLocation(
      chat.id,
      latE7: 236810000,
      lngE7: 903560000,
      accuracyM: 12,
      duration: duration,
    );
    await alice.engine.drainOutbox();
    await bob.sync();
    final theirs = (await bob.messages(alice)).single;
    return (mine: mine, theirs: theirs);
  }

  Future<Map<String, Object?>> payload(Peer peer, int rowid) async {
    final row = (await peer.db.messagesDao.byRowid(rowid))!;
    return (jsonDecode(row.payload!) as Map).cast<String, Object?>();
  }

  test('the start is one bubble whose id is the session id', () async {
    final m = await start();
    expect(m.theirs.kind, 'live_location');
    final p = await payload(bob, m.theirs.localRowid);
    expect(p['session_id'], m.mine.messageId);
    expect(p['lat_e7'], 236810000);
  });

  test('updates move the place and add no bubble', () async {
    final m = await start();
    peers.clock.advance(const Duration(seconds: 30));
    expect(
      await alice.engine.chats.updateLiveLocation(
        m.mine.localRowid,
        latE7: 236820000,
        lngE7: 903570000,
        accuracyM: 8,
      ),
      isTrue,
    );
    await alice.engine.drainOutbox();
    await bob.sync();
    final p = await payload(bob, m.theirs.localRowid);
    expect(p['lat_e7'], 236820000);
    expect(p['accuracy_m'], 8);
    expect((await bob.messages(alice)).length, 1);
    expect((await payload(alice, m.mine.localRowid))['lat_e7'], 236820000);
  });

  test('a stop takes the place out on both sides', () async {
    final m = await start();
    await alice.engine.chats.stopLiveLocation(m.mine.localRowid);
    await alice.engine.drainOutbox();
    await bob.sync();
    for (final (peer, rowid) in [
      (alice, m.mine.localRowid),
      (bob, m.theirs.localRowid),
    ]) {
      final p = await payload(peer, rowid);
      expect(p['ended'], isTrue);
      expect(p['lat_e7'], 0);
      expect(p['lng_e7'], 0);
    }
    expect(
      await alice.engine.chats.updateLiveLocation(
        m.mine.localRowid,
        latE7: 1,
        lngE7: 1,
        accuracyM: 1,
      ),
      isFalse,
    );
    expect(await alice.engine.chats.activeLiveShares(), isEmpty);
  });

  test('an update and a stop both go out, and the stop wins', () async {
    final m = await start();
    final before = peers.server.sends.length;
    await alice.engine.chats.updateLiveLocation(
      m.mine.localRowid,
      latE7: 5,
      lngE7: 5,
      accuracyM: 5,
    );
    await alice.engine.chats.stopLiveLocation(m.mine.localRowid);
    await alice.engine.drainOutbox();
    expect(peers.server.sends.length, before + 2);
    await bob.sync();
    expect((await payload(bob, m.theirs.localRowid))['ended'], isTrue);
  });

  test('only the sender can move a share', () async {
    final m = await start();
    expect(
      await bob.engine.chats.updateLiveLocation(
        m.theirs.localRowid,
        latE7: 1,
        lngE7: 1,
        accuracyM: 1,
      ),
      isFalse,
    );
  });

  test('a share ends by itself, and its place is scrubbed', () async {
    final m = await start(duration: const Duration(minutes: 15));
    expect(await alice.engine.chats.activeLiveShares(), hasLength(1));
    peers.clock.advance(const Duration(minutes: 16));
    expect(await alice.engine.chats.activeLiveShares(), isEmpty);
    expect(await alice.db.messagesDao.endLiveLocations(peers.clock.now), 1);
    expect((await payload(alice, m.mine.localRowid))['lat_e7'], 0);
    await bob.db.messagesDao.endLiveLocations(peers.clock.now);
    expect((await payload(bob, m.theirs.localRowid))['ended'], isTrue);
    // Nothing more to scrub.
    expect(await alice.db.messagesDao.endLiveLocations(peers.clock.now), 0);
  });

  test('a duration that is not 0 to 8 hours is refused', () async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    for (final d in [Duration.zero, const Duration(hours: 9)]) {
      expect(
        () => alice.engine.chats.startLiveLocation(
          chat.id,
          latE7: 1,
          lngE7: 1,
          accuracyM: 1,
          duration: d,
        ),
        throwsArgumentError,
      );
    }
  });
}
