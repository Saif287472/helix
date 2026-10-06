// Performance budgets for the list components (plan section 6.4): a chat list
// of 5,000 chats and a 1,000-message burst must stay cheap.
//
// Wall-clock thresholds are the classic flaky test (other processes, debug
// builds, a cold JIT), so these checks are *relative* and *structural*:
//
//  * Work is counted, not timed: how many rows the framework builds for one
//    frame, which must depend on the viewport and never on the list length.
//    This is what keeps a 5,000-row list under 16 ms per frame on a phone.
//  * Time is only ever compared between two runs on the same machine in the
//    same process (5,000 rows against 50), best of several attempts, with a
//    generous factor. A list that built or laid out every row would be
//    ~100x slower, so a 4x bound catches it without being a coin flip.
//
// The 16 ms figure itself is verified by the app's own frame-timing test
// against a release-like profile run; a unit test cannot honestly assert it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/harness.dart';

List<HelixChatListItem> _chats(int n) => [
  for (var i = 0; i < n; i++)
    HelixChatListItem(
      id: 'c$i',
      title: 'Chat number $i',
      avatar: HelixAvatarModel(name: 'Chat $i', colorIndex: i),
      timeLabel: '14:05',
      unreadCount: i % 7 == 0 ? i % 120 : 0,
      pinned: i < 3,
      muted: i % 11 == 0,
      preview: HelixChatPreview(
        text: 'Last message in chat $i',
        senderPrefix: i.isEven ? 'You' : null,
        status: i.isEven ? HelixDeliveryStatus.read : null,
      ),
    ),
];

HelixTimelineItem _timelineItem(int i, {int base = 0}) {
  final id = 'm${base + i}';
  final outgoing = (base + i) % 3 == 0;
  final content = switch ((base + i) % 6) {
    0 => const HelixMediaContent([
      HelixMediaItem(),
      HelixMediaItem(isVideo: true, durationLabel: '0:09'),
    ], caption: 'photos'),
    1 => const HelixAudioContent(durationLabel: '0:12'),
    2 => const HelixDocumentContent(name: 'notes.pdf', sizeLabel: '12 KB'),
    _ => HelixTextContent('Message number ${base + i} with a few words in it'),
  };
  return HelixMessageItem(
    HelixMessage(
      id: id,
      outgoing: outgoing,
      authorId: outgoing ? 'me' : 'them',
      timeLabel: '14:05',
      sentAtMs: (base + i) * 1000,
      status: HelixDeliveryStatus.delivered,
      reactions: i % 9 == 0
          ? const [HelixReaction(emoji: '👍', count: 2)]
          : const [],
      content: content,
    ),
    position: HelixRunPosition.single,
  );
}

Future<int> _timeMicros(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final watch = Stopwatch()..start();
  await body();
  watch.stop();
  return watch.elapsedMicroseconds;
}

void main() {
  group('chat list with 5,000 chats', () {
    Future<(int, Future<void> Function(double))> pumpList(
      WidgetTester tester,
      int count,
      List<int> builds,
    ) async {
      final items = _chats(count);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpHelix(
        tester,
        Builder(
          builder: (context) => ListView.builder(
            controller: controller,
            itemCount: items.length,
            itemExtent: HelixChatListTile.extentFor(
              MediaQuery.textScalerOf(context),
            ),
            itemBuilder: (context, index) {
              builds.add(index);
              return HelixChatListTile(
                key: ValueKey(items[index].id),
                item: items[index],
              );
            },
          ),
        ),
        height: 800,
      );
      return (
        items.length,
        (double offset) async {
          controller.jumpTo(offset);
          await tester.pump();
        },
      );
    }

    testWidgets('builds only what the viewport shows, whatever the length', (
      tester,
    ) async {
      final small = <int>[];
      await pumpList(tester, 500, small);
      final smallCount = small.length;
      small.clear();

      final big = <int>[];
      await pumpList(tester, 5000, big);
      // 800 px / 72 px rows plus the cache extent: a couple of dozen rows.
      expect(big.length, lessThan(40));
      expect(big.length, smallCount, reason: 'independent of the list length');
    });

    testWidgets('each scroll frame builds a bounded number of new rows', (
      tester,
    ) async {
      final builds = <int>[];
      final (_, jumpTo) = await pumpList(tester, 5000, builds);
      var worst = 0;
      for (var step = 1; step <= 60; step++) {
        builds.clear();
        await jumpTo(step * 72.0 * 3); // three rows per frame, a fast fling
        worst = worst < builds.length ? builds.length : worst;
      }
      expect(worst, lessThan(20), reason: 'new rows per frame');
      // Jumping across the whole list builds only the destination.
      builds.clear();
      await jumpTo(72.0 * 4900);
      expect(builds.length, lessThan(40));
      expect(builds.first, greaterThan(4800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 5,000-row frame costs about the same as a 50-row frame', (
      tester,
    ) async {
      Future<int> bestFrame(int count) async {
        final builds = <int>[];
        final (_, jumpTo) = await pumpList(tester, count, builds);
        var best = 1 << 40;
        for (var attempt = 0; attempt < 5; attempt++) {
          final micros = await _timeMicros(tester, () async {
            for (var i = 1; i <= 20; i++) {
              await jumpTo(
                i * 72.0 * 2 % (count > 100 ? 72.0 * count / 2 : 72.0 * 10),
              );
            }
          });
          if (micros < best) best = micros;
        }
        return best;
      }

      final small = await bestFrame(50);
      final big = await bestFrame(5000);
      // Relative check: see the file header.
      expect(
        big,
        lessThan(small * 4 + 50000),
        reason: '5000 rows took ${big}us, 50 rows ${small}us',
      );
    });

    testWidgets('rows scale to 2x text without overflowing at the extent', (
      tester,
    ) async {
      final builds = <int>[];
      await pumpHelix(
        tester,
        Builder(
          builder: (context) => ListView.builder(
            itemCount: 200,
            itemExtent: HelixChatListTile.extentFor(
              MediaQuery.textScalerOf(context),
            ),
            itemBuilder: (context, i) {
              builds.add(i);
              return HelixChatListTile(item: _chats(200)[i]);
            },
          ),
        ),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(builds, isNotEmpty);
    });
  });

  group('conversation of 1,000 messages', () {
    Future<Future<void> Function(double)> pumpConversation(
      WidgetTester tester,
      List<HelixTimelineItem> items,
      List<String> built,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await pumpHelix(
        tester,
        HelixConversationList(
          controller: controller,
          itemsNewestFirst: items,
          indexOfId: {for (final (i, item) in items.indexed) item.id: i},
          actionsFor: (message) {
            built.add(message.id);
            return const HelixBubbleActions();
          },
        ),
        height: 800,
      );
      return (double offset) async {
        controller.jumpTo(offset);
        await tester.pump();
      };
    }

    testWidgets('opening shows the newest page and builds a viewport of rows', (
      tester,
    ) async {
      final items = [for (var i = 999; i >= 0; i--) _timelineItem(i)];
      final built = <String>[];
      await pumpConversation(tester, items, built);
      expect(built, isNotEmpty);
      expect(built.length, lessThan(60));
      expect(built, contains('m999'), reason: 'the newest message is shown');
      expect(built, isNot(contains('m0')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolling the whole history never builds more than a page', (
      tester,
    ) async {
      final items = [for (var i = 999; i >= 0; i--) _timelineItem(i)];
      final built = <String>[];
      final jumpTo = await pumpConversation(tester, items, built);
      var worst = 0;
      for (var step = 1; step <= 120; step++) {
        built.clear();
        await jumpTo(step * 400.0);
        worst = worst < built.length ? built.length : worst;
      }
      expect(worst, lessThan(60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 1,000-message burst arriving in batches stays cheap', (
      tester,
    ) async {
      final built = <String>[];
      final items = <HelixTimelineItem>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      // The conversation list is rebuilt with a longer list for each batch,
      // as the engine's stream would deliver it.
      late StateSetter update;
      await pumpHelix(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return HelixConversationList(
              controller: controller,
              itemsNewestFirst: List.of(items),
              indexOfId: {for (final (i, item) in items.indexed) item.id: i},
              actionsFor: (message) {
                built.add(message.id);
                return const HelixBubbleActions();
              },
            );
          },
        ),
        height: 800,
      );
      var worstBatch = 0;
      for (var batch = 0; batch < 20; batch++) {
        built.clear();
        update(() {
          for (var i = 0; i < 50; i++) {
            items.insert(0, _timelineItem(batch * 50 + i));
          }
        });
        await tester.pump();
        worstBatch = worstBatch < built.length ? built.length : worstBatch;
      }
      expect(items, hasLength(1000));
      // A batch rebuilds the visible page, not the history.
      expect(worstBatch, lessThan(80), reason: 'rows built per batch');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'rebuilding a 1,000-message list costs about a 20-message list',
      (tester) async {
        Future<int> bestFrame(int count) async {
          final items = [for (var i = count - 1; i >= 0; i--) _timelineItem(i)];
          final jumpTo = await pumpConversation(tester, items, <String>[]);
          var best = 1 << 40;
          for (var attempt = 0; attempt < 5; attempt++) {
            final micros = await _timeMicros(tester, () async {
              for (var i = 1; i <= 15; i++) {
                await jumpTo((i % 5) * 120.0);
              }
            });
            if (micros < best) best = micros;
          }
          return best;
        }

        final small = await bestFrame(20);
        final big = await bestFrame(1000);
        expect(
          big,
          lessThan(small * 4 + 100000),
          reason: '1000 messages took ${big}us, 20 messages ${small}us',
        );
      },
    );

    testWidgets('long conversations lay out at 2x text without overflow', (
      tester,
    ) async {
      final items = [for (var i = 199; i >= 0; i--) _timelineItem(i)];
      await pumpHelix(
        tester,
        HelixConversationList(itemsNewestFirst: items),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
