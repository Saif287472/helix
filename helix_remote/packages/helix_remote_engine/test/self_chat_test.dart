import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// Messaging yourself: a direct chat whose peer is this account. The server
/// relays it like any other send (to the account's other devices), so the
/// engine is where a note-to-self is decided.
void main() {
  late Peers peers;
  late Peer alice;
  late Peer phone;

  setUp(() async {
    peers = Peers();
    alice = await peers.register('alice', phone: '+8801711000001');
  });
  tearDown(() => peers.dispose());

  /// Alice's second device, known to the first one.
  Future<Peer> secondDevice() async {
    final other = await peers.link(alice, 'alice-phone');
    await alice.engine.devices.refresh();
    return other;
  }

  group('a note to self', () {
    test(
      'reaches the other device as an unread row of the same chat',
      () async {
        phone = await secondDevice();
        final chat = await alice.engine.chats.openDirect(alice.account);
        expect(chat.id, directConversationId(alice.account));

        await alice.engine.chats.sendText(chat.id, 'buy milk');
        await alice.engine.drainOutbox();
        final summary = await phone.sync();

        // Your own note is not a reason to make noise where it lands: the
        // unread count is what tells you.
        expect(summary.notices, isEmpty);
        final rows = await phone.db.messagesDao.pageOlder(chat.id, limit: 10);
        final note = rows.messages.single;
        expect(note.body, 'buy milk');
        expect(note.outgoing, isTrue);
        expect(note.status, MessageStatus.received);
        expect((await phone.db.conversationsDao.byId(chat.id))!.unreadCount, 1);
        // Writing here, the sender's own device has nothing unread.
        expect((await alice.db.conversationsDao.byId(chat.id))!.unreadCount, 0);
        expect(
          (await alice.db.messagesDao.pageOlder(
            chat.id,
            limit: 10,
          )).messages.single.status,
          MessageStatus.sent,
        );
      },
    );

    test('never writes a people row for this account', () async {
      phone = await secondDevice();
      final chat = await alice.engine.chats.openDirect(alice.account);
      await alice.engine.chats.sendText(chat.id, 'a note');
      await alice.engine.drainOutbox();
      await phone.sync();
      for (final device in [alice, phone]) {
        expect(await device.db.peopleDao.byAccount(alice.account), isNull);
      }
    });

    test('read on one device stays read for the author', () async {
      phone = await secondDevice();
      final chat = await alice.engine.chats.openDirect(alice.account);
      await alice.engine.chats.sendText(chat.id, 'one');
      await alice.engine.chats.sendText(chat.id, 'two');
      await alice.engine.drainOutbox();
      await phone.sync();
      expect((await phone.db.conversationsDao.byId(chat.id))!.unreadCount, 2);

      await phone.engine.chats.markRead(chat.id);
      expect((await phone.db.conversationsDao.byId(chat.id))!.unreadCount, 0);
      // The other device learns the note was read and its own row keeps the
      // state it was written with.
      await phone.engine.drainOutbox();
      await alice.sync();
      expect(
        (await alice.db.messagesDao.pageOlder(
          chat.id,
          limit: 10,
        )).messages.map((m) => m.status).toSet(),
        {MessageStatus.sent},
      );
    });

    test('an action on a note reaches the device that wrote it', () async {
      phone = await secondDevice();
      final chat = await alice.engine.chats.openDirect(alice.account);
      await alice.engine.chats.sendText(chat.id, 'scratch');
      await alice.engine.drainOutbox();
      await phone.sync();

      // Each device has its own row of the same message.
      await phone.engine.chats.deleteForEveryone(
        (await phone.db.messagesDao.pageOlder(
          chat.id,
          limit: 10,
        )).messages.single.localRowid,
      );
      await phone.engine.drainOutbox();
      await alice.sync();
      for (final device in [alice, phone]) {
        final seen = (await device.db.messagesDao.pageOlder(
          chat.id,
          limit: 10,
        )).messages.single;
        expect(seen.deletedAt, isNotNull);
      }
    });

    test(
      'a device with no peer device sends nothing and keeps the note',
      () async {
        final chat = await alice.engine.chats.openDirect(alice.account);
        final row = await alice.engine.chats.sendText(chat.id, 'only here');
        await alice.engine.drainOutbox();
        expect(
          (await alice.db.messagesDao.byRowid(row.localRowid))!.status,
          MessageStatus.sent,
        );
        // There was nobody to send to: not one request went on the wire.
        expect(peers.server.sends, isEmpty);
      },
    );
  });
}
