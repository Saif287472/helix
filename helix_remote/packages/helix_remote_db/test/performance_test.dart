import 'package:drift/drift.dart' show Variable;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Sanity check for the plan's budget (§6.4): opening a conversation with
/// 100k messages shows its first page in under 150 ms. Runs on an encrypted
/// file database on the background isolate, as the app does. The budget
/// test on real UI lands with Phase A2.
void main() {
  test(
    'first page of a 100k-message conversation is fast',
    () async {
      final db = await HelixDb.open(
        dbFile(tempDir()),
        key: DatabaseKey.generate(),
      );
      addTearDown(db.close);
      final chat = (await directChat(db, 'bob')).id;
      await directChat(db, 'carol');

      // 100k messages in the chat plus 20k elsewhere, inserted in one
      // statement (the FTS trigger runs for each row).
      Future<void> fill(
        String conversation,
        String sender,
        int count,
      ) => db.customStatement(
        'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n '
        'WHERE i < ?) '
        'INSERT INTO messages (message_id, conversation_id, sender, outgoing, '
        'sort_key, sent_at, received_at, kind, body, status) '
        "SELECT ? || i, ?, ?, 0, printf('%012x:%s%d', ? + i * 1000, ?, i), "
        "? + i * 1000, ? + i * 1000, 'text', 'message number ' || i, 'read' "
        'FROM n',
        [
          count,
          sender,
          conversation,
          sender,
          t0.millisecondsSinceEpoch,
          sender,
          t0.millisecondsSinceEpoch,
          t0.millisecondsSinceEpoch,
        ],
      );
      await fill(chat, 'bob', 100000);
      await fill('direct:carol', 'carol', 20000);
      await db.messagesDao.refreshSummary(chat);

      final watch = Stopwatch()..start();
      final first = await db.messagesDao.pageOlder(chat, limit: 50);
      final firstMs = watch.elapsedMilliseconds;
      expect(first.messages, hasLength(50));
      expect(first.messages.last.messageId, 'bob100000');
      expect(first.hasMore, isTrue);
      expect(firstMs, lessThan(150), reason: 'first page took $firstMs ms');

      // Paging back stays index-driven deep into history.
      watch.reset();
      var page = first;
      for (var i = 0; i < 20; i++) {
        page = await db.messagesDao.pageOlder(
          chat,
          before: page.oldestSortKey,
          limit: 50,
        );
      }
      expect(page.messages.first.messageId, 'bob98951');
      expect(watch.elapsedMilliseconds, lessThan(1000));

      final plan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT * FROM messages WHERE conversation_id = ? '
            'AND sort_key < ? ORDER BY sort_key DESC LIMIT 51',
            variables: [Variable.withString(chat), Variable.withString('f')],
          )
          .get();
      expect(
        plan.map((r) => r.data['detail']).join(' | '),
        allOf(contains('USING INDEX'), isNot(contains('TEMP B-TREE'))),
      );

      // Search over the whole history is also quick.
      watch.reset();
      final hits = await db.messagesDao.search('number 99999');
      expect(hits.map((m) => m.messageId), contains('bob99999'));
      expect(watch.elapsedMilliseconds, lessThan(1000));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
