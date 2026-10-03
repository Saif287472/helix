import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// DAO methods added for the engine's group chats (Phase C4-G).
void main() {
  late HelixDb db;

  setUp(() => db = memoryDb());

  group('ConversationsDao.ensureGroup', () {
    test('creates the chat once and keeps its members and messages', () async {
      const id = 'group:g1';
      final first = await db.conversationsDao.ensureGroup(
        id,
        title: 'Team',
        avatar: Uint8List.fromList([1, 2]),
        now: t0,
      );
      expect(first.kind, ConversationKind.group);
      expect(first.title, 'Team');
      expect(first.avatar, [1, 2]);

      await db.conversationsDao.setMembers(id, ['alice', 'bob']);
      await db.messagesDao.insertMessage(
        textMessage(id, 'm1', sentAt: at(1), body: 'hi'),
      );

      // Again, without a title: nothing is cleared or recreated.
      final again = await db.conversationsDao.ensureGroup(id, now: at(5));
      expect(again.title, 'Team');
      expect(again.createdAt, t0);
      expect(await db.conversationsDao.membersOf(id), hasLength(2));
      expect((await db.conversationsDao.byId(id))!.unreadCount, 1);

      final renamed = await db.conversationsDao.ensureGroup(
        id,
        title: 'Crew',
        now: at(6),
      );
      expect(renamed.title, 'Crew');
      expect(renamed.avatar, [1, 2]);
    });
  });

  group('sender key lookups', () {
    Future<void> put(String dist, DateTime created, {String device = 'd1'}) =>
        db.cryptoDao.saveSenderKey(
          SenderKeysCompanion.insert(
            groupId: 'g1',
            accountId: 'a1',
            deviceId: device,
            distId: dist,
            state: Uint8List.fromList(dist.codeUnits),
            createdAt: created,
            updatedAt: created,
          ),
        );

    test('the newest key of a device wins, other devices are apart', () async {
      await put('old', at(1));
      await put('new', at(2));
      await put('other', at(3), device: 'd2');
      final latest = await db.cryptoDao.latestSenderKey(
        groupId: 'g1',
        account: 'a1',
        device: 'd1',
      );
      expect(latest!.distId, 'new');
      final all = await db.cryptoDao.senderKeysOf(
        groupId: 'g1',
        account: 'a1',
        device: 'd1',
      );
      expect([for (final k in all) k.distId], ['new', 'old']);
      expect(
        await db.cryptoDao.latestSenderKey(
          groupId: 'g2',
          account: 'a1',
          device: 'd1',
        ),
        isNull,
      );
    });

    test('deleteSenderKey removes exactly one', () async {
      await put('old', at(1));
      await put('new', at(2));
      await db.cryptoDao.deleteSenderKey(
        groupId: 'g1',
        account: 'a1',
        device: 'd1',
        distId: 'old',
      );
      final all = await db.cryptoDao.senderKeysOf(
        groupId: 'g1',
        account: 'a1',
        device: 'd1',
      );
      expect([for (final k in all) k.distId], ['new']);
    });
  });

  test('findInConversation finds a message whoever wrote it', () async {
    const id = 'group:g1';
    await db.conversationsDao.ensureGroup(id, now: t0);
    await db.messagesDao.insertMessage(
      textMessage(id, 'm1', sentAt: at(1), sender: 'carol', body: 'hi'),
    );
    expect(
      (await db.messagesDao.findInConversation(id, 'm1'))!.sender,
      'carol',
    );
    expect(await db.messagesDao.findInConversation(id, 'nope'), isNull);
    expect(await db.messagesDao.findInConversation('group:g2', 'm1'), isNull);
  });
}
