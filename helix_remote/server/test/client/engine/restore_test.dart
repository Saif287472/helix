import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:test/test.dart';

import '../../support/flows.dart';
import '../../support/harness.dart';
import '../../support/test_database.dart';
import 'support.dart';

/// A phone whose mailbox cursor is ahead of a server restored from a backup
/// still gets new messages (review H-01, batch 9), by REST and by socket.
void main() {
  group('engine after a server restore', skip: databaseTestSkipReason, () {
    late Harness h;
    late EngineWorld world;

    setUp(() async {
      h = await Harness.start();
      world = EngineWorld(h);
    });
    tearDown(() async {
      await world.dispose();
      await h.stop();
    });

    /// Alice sends Bob two texts, which Bob (REST only) receives; then the
    /// database goes back to before Bob was ever given a `seq`.
    Future<(EngineUser, EngineUser, int)> receiveThenRestore() async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber, realtime: false);
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'one');
      await alice.engine.chats.sendText(chat.id, 'two');
      await settle(() async {
        await bob.engine.syncOnce();
        expect([
          for (final m in await messagesWith(bob, alice)) m.body,
        ], containsAll(['one', 'two']));
      });
      final cursor = (await bob.db.inboxDao.cursor())!.lastProcessedSeq;
      expect(cursor, greaterThanOrEqualTo(2));
      await h.env.platform.db.execute(
        'UPDATE ${h.env.platform.schemas.of('messaging')}.device_seq '
        'SET last_seq = 0 WHERE device_id = @d:uuid',
        {'d': bob.device},
      );
      await alice.engine.chats.sendText(chat.id, 'after the restore');
      return (alice, bob, cursor);
    }

    test('by REST: the cursor goes back and the new message arrives', () async {
      final (alice, bob, _) = await receiveThenRestore();
      await settle(() async {
        await bob.engine.syncOnce();
        expect([
          for (final m in await messagesWith(bob, alice)) m.body,
        ], contains('after the restore'));
      });
      expect(
        (await bob.db.inboxDao.cursor())!.lastProcessedSeq,
        lessThanOrEqualTo(1),
        reason: 'reset, then moved to the new seq only',
      );
      expect(
        [for (final m in await messagesWith(bob, alice)) m.body],
        hasLength(3),
        reason: 'nothing processed twice',
      );
    });

    test('by socket: hello resets the cursor and the replay arrives', () async {
      final (alice, bob, cursor) = await receiveThenRestore();
      // The same phone, now with the socket (as after the server restart).
      await bob.engine.stop();
      final again = await world.create('bob-again', db: bob.db, key: bob.key);
      expect(again.engine.status, EngineStatus.running);
      final text = await waitForText(again, alice, 'after the restore');
      expect(text.status, MessageStatus.received);
      expect(
        (await again.db.inboxDao.cursor())!.lastProcessedSeq,
        lessThan(cursor),
      );
    });
  });
}
