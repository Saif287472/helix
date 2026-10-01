import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// `messages_fts` stays in step with the messages table.
void main() {
  late HelixDb db;
  late MessagesDao messages;
  late String chat;

  setUp(() async {
    db = memoryDb();
    messages = db.messagesDao;
    chat = (await directChat(db, 'bob')).id;
  });

  Future<List<String>> search(String query, {String? conversationId}) async => [
    for (final m in await messages.search(
      query,
      conversationId: conversationId,
    ))
      m.messageId,
  ];

  /// FTS5's own check that the index matches the content table.
  Future<void> expectIndexConsistent() => db.customStatement(
    "INSERT INTO messages_fts (messages_fts, rank) VALUES ('integrity-check', 1)",
  );

  test(
    'insert, edit, delete for everyone and removal keep the index in step',
    () async {
      final m1 = await messages.insertMessage(
        textMessage(chat, 'm1', sentAt: at(1), body: 'Meet at the harbour'),
      );
      await messages.insertMessage(
        textMessage(chat, 'm2', sentAt: at(2), body: 'harbour lights tonight'),
      );
      expect(await search('harbour'), ['m2', 'm1'], reason: 'newest first');
      expect(await search('harb'), ['m2', 'm1'], reason: 'prefix match');
      expect(await search('harbour meet'), ['m1'], reason: 'all words');
      await expectIndexConsistent();

      await messages.editMessage(
        m1.localRowid,
        body: 'Meet at the station',
        editedAt: at(3),
      );
      expect(await search('harbour'), ['m2']);
      expect(await search('station'), ['m1']);
      await expectIndexConsistent();

      final m2 = (await messages.find('m2', sender: 'bob'))!;
      await messages.deleteForEveryone(m2.localRowid, deletedAt: at(4));
      expect(await search('harbour'), isEmpty);
      await expectIndexConsistent();

      await messages.removeMessages([m1.localRowid]);
      expect(await search('station'), isEmpty);
      await expectIndexConsistent();
    },
  );

  test('a conversation filter and messages without text', () async {
    final other = (await directChat(db, 'carol')).id;
    await messages.insertMessage(
      textMessage(chat, 'm1', sentAt: at(1), body: 'lunch?'),
    );
    await messages.insertMessage(
      textMessage(other, 'c1', sentAt: at(2), sender: 'carol', body: 'Lunch!'),
    );
    await messages.insertMessage(
      textMessage(chat, 'm2', sentAt: at(3)).copyWith(body: const Value(null)),
    );
    expect(await search('lunch'), ['c1', 'm1']);
    expect(await search('lunch', conversationId: chat), ['m1']);
    await expectIndexConsistent();
  });

  test('unicode: case folding, diacritics and Indic scripts', () async {
    final bodies = {
      'latin': 'Café au lait, s’il vous plaît',
      'cyrillic': 'Привет, как дела?',
      'bengali': 'আমি বাংলায় গান গাই',
      'greek': 'Καλημέρα κόσμε',
      'emoji': 'party tonight 🎉🎉',
    };
    var i = 0;
    for (final MapEntry(:key, :value) in bodies.entries) {
      await messages.insertMessage(
        textMessage(chat, key, sentAt: at(++i), body: value),
      );
    }
    expect(await search('cafe'), ['latin']);
    expect(await search('CAFÉ PLAIT'), ['latin']);
    expect(await search('привет'), ['cyrillic']);
    expect(await search('ДЕЛА'), ['cyrillic']);
    expect(await search('বাংলায়'), ['bengali']);
    expect(await search('বাং'), ['bengali'], reason: 'prefix inside a word');
    expect(await search('গান গাই'), ['bengali']);
    expect(await search('ΚΑΛΗΜΈΡΑ'), ['greek'], reason: 'case folds');
    expect(await search('party 🎉'), ['emoji']);
  });

  test('user input is never FTS syntax', () async {
    await messages.insertMessage(
      textMessage(chat, 'm1', sentAt: at(1), body: 'NOT a "quoted" thing'),
    );
    for (final query in [
      '"',
      'NOT',
      'a OR',
      '(quoted',
      'thing*',
      '-quoted',
      'body:thing',
      'NEAR(a b)',
    ]) {
      await messages.search(query);
    }
    expect(await search('"quoted"'), ['m1']);
    expect(await search('not'), ['m1']);
    expect(await search('   '), isEmpty);
    expect(await search('!!!'), isEmpty);
    expect(
      MessagesDao.ftsMatchExpression('hello, "world"'),
      '"hello"* "world"*',
    );
  });
}
