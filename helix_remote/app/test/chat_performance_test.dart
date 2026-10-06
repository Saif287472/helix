import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/chats/presentation/chats_tab.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote/features/conversation/presentation/timeline_row.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/chat_harness.dart';

/// The plan's §6.4 budgets, as relative and build-count checks (never a
/// wall-clock figure, which would be a flaky test): what is built and read
/// must depend on what is on screen, not on how much is stored.
void main() {
  /// [count] messages in [chat], inserted by SQL so setup stays fast.
  Future<void> bulkMessages(
    TestChatGateway gateway,
    String chat,
    int count,
  ) async {
    final base = testNow.toUtc().millisecondsSinceEpoch - count * 1000;
    await gateway.db.customStatement('''
      WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < $count)
      INSERT INTO messages (message_id, conversation_id, sender, outgoing, sort_key,
        sent_at, received_at, kind, body, status)
      SELECT '$chat:bulk' || i, '$chat', 'bob', 0,
        printf('%012x', $base + i * 1000) || ':$chat:bulk' || i,
        $base + i * 1000, $base + i * 1000, 'text', 'message ' || i, 'read'
      FROM n
    ''');
    await gateway.db.messagesDao.refreshSummary(chat);
  }

  chatTest('the chat list with 5,000 chats builds only the rows on screen', (
    tester,
    gateway,
  ) async {
    await tester.runAsync(() async {
      await gateway.db.customStatement('''
        WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 5000)
        INSERT INTO conversations (id, kind, created_at, last_message_at,
          last_message_preview, unread_count, mention_count, archived)
        SELECT 'direct:p' || i, 'direct', ${testNow.millisecondsSinceEpoch} - i * 1000,
          ${testNow.millisecondsSinceEpoch} - i * 1000, 'hello ' || i, i % 3, 0, 0
        FROM n
      ''');
    });
    await tester.pumpWidget(chatApp(gateway, const ChatsTab()));
    await settle(tester, rounds: 12);

    final built = find.byType(HelixChatListTile).evaluate().length;
    expect(built, greaterThan(3));
    expect(
      built,
      lessThan(40),
      reason: 'only the rows on screen exist, not 5,000',
    );
    // Rows have one fixed height, so nothing was measured to place them.
    final list = tester.widget<SliverFixedExtentList>(
      find.byType(SliverFixedExtentList),
    );
    expect(list.itemExtent, isNotNull);
    expect(tester.takeException(), isNull);
  });

  chatTest('the first page of a 100,000-message conversation is small and fast '
      'compared with a short one', (tester, gateway) async {
    final big = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    final small = (await tester.runAsync(
      () => gateway.chatWith('amy', name: 'Amy'),
    ))!;
    final (bigTime, smallTime, rows) = (await tester.runAsync(() async {
      await bulkMessages(gateway, big, 100000);
      await bulkMessages(gateway, small, 100);
      Future<int> firstPage(String chat) async {
        final w = Stopwatch()..start();
        for (var i = 0; i < 5; i++) {
          await gateway.watchLatest(chat, 50).first;
        }
        return w.elapsedMicroseconds;
      }

      final s = await firstPage(small);
      final b = await firstPage(big);
      final page = await gateway.watchLatest(big, 50).first;
      return (b, s, page.length);
    }))!;
    expect(rows, 50);
    // The keyset query reads a window: 1,000x the data must not cost 1,000x.
    expect(
      bigTime,
      lessThan(smallTime * 40 + 200000),
      reason: 'reading 50 rows of 100,000 must not scan them',
    );

    timelineRowBuilds = 0;
    await tester.pumpWidget(
      chatApp(gateway, ConversationScreen(conversationId: big)),
    );
    await settle(tester, rounds: 12);
    expect(find.byType(HelixMessageBubble).evaluate().length, lessThan(60));
    expect(
      timelineRowBuilds,
      lessThan(200),
      reason: 'the first frame builds a screenful of rows, not 100,000',
    );
  });

  chatTest('a 1,000-message burst rebuilds the rows that changed', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() => bulkMessages(gateway, chat, 60));
    await tester.pumpWidget(
      chatApp(gateway, ConversationScreen(conversationId: chat)),
    );
    await settle(tester, rounds: 10);

    timelineRowBuilds = 0;
    // One write per message, a few milliseconds apart - faster than frames,
    // so the screen is told about several at a time. (Each write needs its
    // own turn of the real event loop, because the screen's own streams read
    // the same database from the test's fake clock.)
    for (var n = 0; n < 1000; n++) {
      await tester.runAsync(
        () => gateway.incoming(
          chat,
          'burst $n',
          at: testNow.add(Duration(milliseconds: n)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 4));
    }
    await settle(tester, rounds: 12);

    expect(
      find.textContaining('burst 999', findRichText: true),
      findsOneWidget,
    );
    // A list that rebuilt every visible row on every snapshot would build
    // ~15 rows x hundreds of snapshots. Equal rows are kept as they were.
    expect(
      timelineRowBuilds,
      lessThan(6000),
      reason: 'rows are rebuilt only when their own content changes',
    );
    expect(tester.takeException(), isNull);
  });
}
