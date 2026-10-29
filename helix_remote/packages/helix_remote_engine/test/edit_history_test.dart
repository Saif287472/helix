import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/messaging/content_codec.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// An edited message keeps its earlier versions on both sides, and they never
/// travel again.
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

  test(
    'the author and the reader both keep what the message said before',
    () async {
      final chat = await alice.engine.chats.openDirect(bob.account);
      final mine = await alice.engine.chats.sendText(chat.id, 'meet at fiev');
      await alice.engine.drainOutbox();
      await bob.sync();

      peers.clock.advance(const Duration(minutes: 1));
      await alice.engine.chats.edit(mine.localRowid, 'meet at five');
      await alice.engine.drainOutbox();
      await bob.sync();

      final aliceRow = (await alice.db.messagesDao.byRowid(mine.localRowid))!;
      final bobRow = (await bob.messages(alice)).single;
      for (final row in [aliceRow, bobRow]) {
        expect(row.body, 'meet at five');
        expect([for (final r in revisionsOf(row)) r.body], ['meet at fiev']);
      }
    },
  );

  test('a message sent again is the current text only', () async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    final mine = await alice.engine.chats.sendText(chat.id, 'first');
    peers.clock.advance(const Duration(minutes: 1));
    await alice.engine.chats.edit(mine.localRowid, 'second');
    final row = (await alice.db.messagesDao.byRowid(mine.localRowid))!;
    expect(revisionsOf(row), hasLength(1));

    final body = ContentCodec.join(row);
    expect(body, isA<TextBody>().having((b) => b.text, 'text', 'second'));
    expect(body.toJson().containsKey('revisions'), isFalse);
    expect(body.toJson().toString(), isNot(contains('first')));
  });
}
