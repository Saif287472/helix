import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Schema 7: the person's own lists of chats.
void main() {
  late HelixDb db;
  late ConversationRow bob;
  late ConversationRow cara;
  setUp(() async {
    db = memoryDb();
    bob = await directChat(db, 'bob');
    cara = await directChat(db, 'cara');
  });

  ConversationsDao dao() => db.conversationsDao;

  test('lists come back in the order they were made', () async {
    await dao().createList('a', 'Work', at(1));
    await dao().createList('b', 'Family', at(2));
    await dao().createList('c', 'Gym', at(3));
    expect(
      [for (final l in await dao().lists()) l.name],
      ['Work', 'Family', 'Gym'],
    );
    await dao().renameList('b', 'Home');
    expect((await dao().watchLists().first)[1].name, 'Home');
  });

  test('a chat is on several lists, and a list holds several chats', () async {
    await dao().createList('a', 'Work', at(1));
    await dao().createList('b', 'Family', at(2));
    await dao().addToList('a', bob.id);
    await dao().addToList('b', bob.id);
    await dao().addToList('b', cara.id);
    await dao().addToList('b', cara.id);
    final members = await dao().watchListMembers().first;
    expect(
      {for (final m in members) '${m.listId}:${m.conversationId}'},
      {'a:${bob.id}', 'b:${bob.id}', 'b:${cara.id}'},
    );
    await dao().removeFromList('b', bob.id);
    expect(await dao().listMembers(), hasLength(2));
  });

  test('a list or chat that does not exist is ignored', () async {
    await dao().createList('a', 'Work', at(1));
    await dao().addToList('a', 'direct:nobody');
    await dao().addToList('nolist', bob.id);
    expect(await dao().listMembers(), isEmpty);
  });

  test(
    'deleting a list keeps its chats; deleting a chat leaves its lists',
    () async {
      await dao().createList('a', 'Work', at(1));
      await dao().addToList('a', bob.id);
      await dao().addToList('a', cara.id);
      await db.customStatement(
        "DELETE FROM conversations WHERE id = '${cara.id}'",
      );
      expect(await dao().listMembers(), hasLength(1));
      await dao().deleteList('a');
      expect(await dao().listMembers(), isEmpty);
      expect(await dao().byId(bob.id), isNotNull);
    },
  );

  test('a wipe empties the lists too', () async {
    await dao().createList('a', 'Work', at(1));
    await dao().addToList('a', bob.id);
    await db.wipeAll();
    expect(await dao().lists(), isEmpty);
    expect(await dao().listMembers(), isEmpty);
  });
}
