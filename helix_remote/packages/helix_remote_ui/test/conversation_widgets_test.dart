import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/harness.dart';

HelixMessage _text(
  String body, {
  bool outgoing = false,
  HelixDeliveryStatus status = HelixDeliveryStatus.sent,
  HelixReplyQuote? reply,
  bool forwarded = false,
  bool edited = false,
  List<HelixReaction> reactions = const [],
  String? author,
  String? expires,
  HelixLinkPreview? link,
}) => HelixMessage(
  id: 'm',
  outgoing: outgoing,
  timeLabel: '14:05',
  status: status,
  reply: reply,
  forwarded: forwarded,
  edited: edited,
  reactions: reactions,
  authorName: author,
  expiresLabel: expires,
  content: HelixTextContent(body, linkPreview: link),
);

Widget _bubble(
  HelixMessage m, {
  HelixBubbleActions? actions,
  HelixRunPosition p = HelixRunPosition.single,
}) => HelixMessageBubble(
  message: m,
  position: p,
  actions: actions ?? const HelixBubbleActions(),
);

void main() {
  wallpaperTests();
  group('text bubbles', () {
    testWidgets('show body, time and, for outgoing, the tick', (tester) async {
      await pumpHelix(
        tester,
        _bubble(
          _text(
            'Hello there',
            outgoing: true,
            status: HelixDeliveryStatus.read,
          ),
        ),
      );
      expect(
        find.textContaining('Hello there', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('14:05'), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsOneWidget);
    });

    testWidgets('incoming bubbles have no tick', (tester) async {
      await pumpHelix(tester, _bubble(_text('Hi')));
      expect(find.byIcon(Icons.done), findsNothing);
      expect(find.byIcon(Icons.done_all), findsNothing);
    });

    testWidgets('each delivery status has its own glyph and label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      for (final entry in {
        HelixDeliveryStatus.pending: (Icons.schedule, 'Sending'),
        HelixDeliveryStatus.sent: (Icons.done, 'Sent'),
        HelixDeliveryStatus.delivered: (Icons.done_all, 'Delivered'),
        HelixDeliveryStatus.read: (Icons.done_all, 'Read'),
        HelixDeliveryStatus.failed: (Icons.error, 'Not sent'),
      }.entries) {
        await pumpHelix(tester, HelixStatusTicks(status: entry.key));
        expect(
          find.byIcon(entry.value.$1),
          findsOneWidget,
          reason: '${entry.key}',
        );
        expect(find.bySemanticsLabel(entry.value.$2), findsOneWidget);
      }
      handle.dispose();
    });

    testWidgets('the read tick is blue and the delivered tick is not', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        const HelixStatusTicks(status: HelixDeliveryStatus.read),
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.done_all)).color,
        HelixChatColors.readTick,
      );
      await pumpHelix(
        tester,
        const HelixStatusTicks(status: HelixDeliveryStatus.delivered),
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.done_all)).color,
        HelixChatColors.metaText,
      );
    });

    testWidgets('forwarded, edited and timer markers appear', (tester) async {
      await pumpHelix(
        tester,
        _bubble(
          _text(
            'x',
            outgoing: true,
            forwarded: true,
            edited: true,
            expires: '1d',
          ),
        ),
      );
      expect(find.text('Forwarded'), findsOneWidget);
      expect(find.text('Edited'), findsOneWidget);
      expect(find.text('1d'), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    });

    testWidgets('reply quote shows author and quoted text', (tester) async {
      await pumpHelix(
        tester,
        _bubble(
          _text(
            'Agreed',
            reply: const HelixReplyQuote(
              authorName: 'Sam',
              text: 'Leaving at seven',
            ),
          ),
        ),
      );
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Leaving at seven'), findsOneWidget);
    });

    testWidgets('a quote of a missing message says so', (tester) async {
      await pumpHelix(
        tester,
        _bubble(
          _text(
            'ok',
            reply: const HelixReplyQuote(authorName: 'Sam', missing: true),
          ),
        ),
      );
      expect(find.text('Original message not available'), findsOneWidget);
    });

    testWidgets('a quote of media shows its label and glyph', (tester) async {
      await pumpHelix(
        tester,
        _bubble(
          _text(
            'nice',
            reply: const HelixReplyQuote(
              authorName: 'Sam',
              kind: HelixPreviewKind.image,
            ),
          ),
        ),
      );
      expect(find.text('Photo'), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    });

    testWidgets('reactions render with counts', (tester) async {
      await pumpHelix(
        tester,
        _bubble(
          _text(
            'x',
            reactions: const [
              HelixReaction(emoji: '👍', count: 3, mine: true),
              HelixReaction(emoji: '❤️', count: 1),
            ],
          ),
        ),
      );
      expect(find.text('👍 3'), findsOneWidget);
      expect(find.text('❤️'), findsOneWidget);
    });

    testWidgets('reactions and quote are reachable by screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHelix(
        tester,
        _bubble(
          _text(
            'text',
            reply: const HelixReplyQuote(authorName: 'S', text: 'q'),
            reactions: const [HelixReaction(emoji: '👍', count: 1)],
          ),
          actions: HelixBubbleActions(
            onReply: () {},
            onQuoteTap: () {},
            onReactionsTap: () {},
          ),
        ),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Reply to S')),
      );
      // Reply, go to replied message, show reactions.
      expect(node.getSemanticsData().customSemanticsActionIds, hasLength(3));
      handle.dispose();
    });

    testWidgets('long press and tap reach the callbacks', (tester) async {
      var taps = 0;
      var longs = 0;
      await pumpHelix(
        tester,
        _bubble(
          _text('press me'),
          actions: HelixBubbleActions(
            onTap: () => taps++,
            onLongPress: () => longs++,
          ),
        ),
      );
      await tester.tap(find.textContaining('press me', findRichText: true));
      await tester.longPress(
        find.textContaining('press me', findRichText: true),
      );
      expect((taps, longs), (1, 1));
    });

    testWidgets('failed messages offer a retry', (tester) async {
      var retries = 0;
      await pumpHelix(
        tester,
        _bubble(
          _text('oops', outgoing: true, status: HelixDeliveryStatus.failed),
          actions: HelixBubbleActions(onRetry: () => retries++),
        ),
      );
      expect(find.text('Not sent'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('swipe towards the centre replies', (tester) async {
      var replies = 0;
      await pumpHelix(
        tester,
        _bubble(
          _text('swipe'),
          actions: HelixBubbleActions(onReply: () => replies++),
        ),
      );
      await tester.drag(
        find.textContaining('swipe', findRichText: true),
        const Offset(120, 0),
      );
      await tester.pumpAndSettle();
      expect(replies, 1);
      await tester.drag(
        find.textContaining('swipe', findRichText: true),
        const Offset(20, 0),
      );
      await tester.pumpAndSettle();
      expect(replies, 1, reason: 'a short drag must not reply');
    });

    testWidgets('links in text are tappable and previewed', (tester) async {
      final tapped = <String>[];
      await pumpHelix(
        tester,
        _bubble(
          _text(
            'see https://example.org/page now',
            link: const HelixLinkPreview(
              url: 'https://example.org/page',
              title: 'The page',
            ),
          ),
          actions: HelixBubbleActions(onLinkTap: tapped.add),
        ),
      );
      expect(find.text('The page'), findsOneWidget);
      expect(find.text('example.org'), findsOneWidget);
      await tester.tapOnText(
        find.textRange.ofSubstring('https://example.org/page'),
      );
      expect(tapped, ['https://example.org/page']);
      await tester.tap(find.text('The page'));
      expect(tapped, hasLength(2));
    });

    testWidgets('mentions are emphasised', (tester) async {
      await pumpHelix(
        tester,
        _bubble(
          const HelixMessage(
            id: 'm',
            outgoing: false,
            timeLabel: '1',
            content: HelixTextContent(
              'hi @Lee ok',
              mentions: [HelixTextRange(3, 4)],
            ),
          ),
        ),
      );
      final rich = tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('hi @Lee'),
        ),
      );
      var bold = false;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == '@Lee') {
          bold = span.style?.fontWeight == FontWeight.w700;
        }
        return true;
      });
      expect(bold, isTrue);
    });

    testWidgets('a bubble never takes more than 80% of the row', (
      tester,
    ) async {
      await pumpHelix(tester, _bubble(_text('long ' * 80)));
      final width = tester.getSize(find.byType(DecoratedBox).first).width;
      final bubble = tester.getRect(find.byType(HelixMessageBubble));
      expect(bubble.width, 400);
      final text = tester.getRect(find.byType(RichText).first);
      expect(text.width, lessThanOrEqualTo(400 * 0.8));
      expect(width, greaterThan(0));
    });

    testWidgets('incoming hugs the start edge, outgoing the end edge', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        Column(
          children: [
            _bubble(_text('in')),
            _bubble(_text('out', outgoing: true)),
          ],
        ),
      );
      final inRect = tester.getRect(
        find.textContaining('in', findRichText: true).first,
      );
      final outRect = tester.getRect(
        find.textContaining('out', findRichText: true).first,
      );
      expect(inRect.left, lessThan(60));
      expect(outRect.right, greaterThan(340));
    });

    testWidgets('RTL flips the sides', (tester) async {
      await pumpHelix(
        tester,
        Column(
          children: [
            _bubble(_text('in')),
            _bubble(_text('out', outgoing: true)),
          ],
        ),
        direction: TextDirection.rtl,
      );
      final inRect = tester.getRect(
        find.textContaining('in', findRichText: true).first,
      );
      final outRect = tester.getRect(
        find.textContaining('out', findRichText: true).first,
      );
      expect(inRect.right, greaterThan(340));
      expect(outRect.left, lessThan(60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic text lays out right to left in an LTR UI', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        _bubble(_text('مرحبا بك في هيلكس', author: 'نادية')),
      );
      final rich = tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('مرحبا'),
        ),
      );
      expect(
        Directionality.of(tester.element(find.byWidget(rich))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Bengali text builds without overflow at 2x', (tester) async {
      await pumpHelix(
        tester,
        SingleChildScrollView(
          child: _bubble(_text('আজ বিকেলে দেখা হবে তো? ' * 6, outgoing: true)),
        ),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('group authors appear on the first message of a run only', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        Column(
          children: [
            _bubble(_text('a', author: 'Sam'), p: HelixRunPosition.first),
            _bubble(_text('b', author: 'Sam'), p: HelixRunPosition.last),
          ],
        ),
      );
      expect(find.text('Sam'), findsOneWidget);
    });

    testWidgets('summary label covers author, reply and status', (
      tester,
    ) async {
      final label = HelixMessageBubble.summaryLabel(
        _text(
          'Body',
          outgoing: true,
          status: HelixDeliveryStatus.delivered,
          reply: const HelixReplyQuote(authorName: 'Sam', text: 'Q'),
          edited: true,
          reactions: const [HelixReaction(emoji: '👍', count: 2)],
        ),
      );
      expect(label, startsWith('You: '));
      expect(label, contains('Reply to Sam: Q'));
      expect(label, contains('Body'));
      expect(label, contains('edited'));
      expect(label, contains('Delivered'));
      expect(label, contains('👍 2'));
    });
  });

  group('placeholders', () {
    for (final entry in {
      HelixPlaceholderKind.deleted: 'This message was deleted',
      HelixPlaceholderKind.undecryptable: "Couldn't decrypt this message",
      HelixPlaceholderKind.unsupported:
          'This message needs a newer version of Helix',
      HelixPlaceholderKind.expired: 'This message has disappeared',
    }.entries) {
      testWidgets('${entry.key.name} says ${entry.value}', (tester) async {
        await pumpHelix(
          tester,
          _bubble(
            HelixMessage(
              id: 'p',
              outgoing: false,
              timeLabel: '1',
              content: HelixPlaceholderContent(entry.key),
            ),
          ),
        );
        expect(find.text(entry.value), findsOneWidget);
        expect(
          find.textContaining('{'),
          findsNothing,
          reason: 'never raw JSON',
        );
      });
    }

    testWidgets('your own deleted message is worded for you', (tester) async {
      await pumpHelix(
        tester,
        _bubble(
          const HelixMessage(
            id: 'p',
            outgoing: true,
            timeLabel: '1',
            content: HelixPlaceholderContent(HelixPlaceholderKind.deleted),
          ),
        ),
      );
      expect(find.text('You deleted this message'), findsOneWidget);
    });

    testWidgets('undecryptable and unsupported can offer an action', (
      tester,
    ) async {
      var actions = 0;
      for (final (kind, label) in [
        (HelixPlaceholderKind.undecryptable, 'Ask to resend'),
        (HelixPlaceholderKind.unsupported, 'Update Helix'),
      ]) {
        await pumpHelix(
          tester,
          _bubble(
            HelixMessage(
              id: 'p',
              outgoing: false,
              timeLabel: '1',
              content: HelixPlaceholderContent(kind),
            ),
            actions: HelixBubbleActions(onPlaceholderAction: () => actions++),
          ),
        );
        await tester.tap(find.text(label));
      }
      expect(actions, 2);
    });

    testWidgets('no action button without a handler', (tester) async {
      await pumpHelix(
        tester,
        _bubble(
          const HelixMessage(
            id: 'p',
            outgoing: false,
            timeLabel: '1',
            content: HelixPlaceholderContent(
              HelixPlaceholderKind.undecryptable,
            ),
          ),
        ),
      );
      expect(find.text('Ask to resend'), findsNothing);
    });
  });

  group('media', () {
    HelixMessage media(int n, {String caption = '', bool video = false}) =>
        HelixMessage(
          id: 'p',
          outgoing: false,
          timeLabel: '14:05',
          content: HelixMediaContent([
            for (var i = 0; i < n; i++)
              HelixMediaItem(
                isVideo: video && i == 0,
                durationLabel: video && i == 0 ? '0:12' : null,
              ),
          ], caption: caption),
        );

    testWidgets('one image keeps its aspect ratio', (tester) async {
      await pumpHelix(tester, _bubble(media(1)));
      final size = tester.getSize(find.byType(HelixMediaGrid));
      expect(size.width / size.height, closeTo(4 / 3, 0.01));
    });

    testWidgets('grid layouts for 2, 3, 4 and 5 items', (tester) async {
      for (final n in [2, 3, 4, 5]) {
        await pumpHelix(tester, _bubble(media(n)));
        final size = tester.getSize(find.byType(HelixMediaGrid));
        expect(size.width, lessThanOrEqualTo(300), reason: '$n');
        expect(size.height, greaterThan(100), reason: '$n');
        expect(tester.takeException(), isNull, reason: '$n');
      }
    });

    testWidgets('more than four shows the remaining count', (tester) async {
      await pumpHelix(tester, _bubble(media(7)));
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('videos show a play glyph and duration', (tester) async {
      await pumpHelix(tester, _bubble(media(1, video: true)));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.text('0:12'), findsOneWidget);
    });

    testWidgets('caption-less media overlays the time on the picture', (
      tester,
    ) async {
      await pumpHelix(tester, _bubble(media(1)));
      final grid = tester.getRect(find.byType(HelixMediaGrid));
      final time = tester.getRect(find.text('14:05'));
      expect(grid.contains(time.center), isTrue);
    });

    testWidgets('a caption sits under the grid with the time', (tester) async {
      await pumpHelix(tester, _bubble(media(2, caption: 'Trail photos')));
      expect(
        find.textContaining('Trail photos', findRichText: true),
        findsOneWidget,
      );
      final grid = tester.getRect(find.byType(HelixMediaGrid));
      final time = tester.getRect(find.text('14:05'));
      expect(time.top, greaterThan(grid.bottom - 1));
    });

    testWidgets('tapping an item reports its index', (tester) async {
      final tapped = <int>[];
      await pumpHelix(
        tester,
        _bubble(media(4), actions: HelixBubbleActions(onMediaTap: tapped.add)),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(HelixMediaGrid)) + const Offset(10, 10),
      );
      await tester.tapAt(
        tester.getBottomLeft(find.byType(HelixMediaGrid)) +
            const Offset(10, -10),
      );
      expect(tapped, [0, 2]);
    });

    testWidgets('undownloaded media taps to download, not to open', (
      tester,
    ) async {
      final opened = <int>[];
      final transfers = <int>[];
      await pumpHelix(
        tester,
        _bubble(
          const HelixMessage(
            id: 'p',
            outgoing: false,
            timeLabel: '1',
            content: HelixMediaContent([
              HelixMediaItem(transfer: HelixTransferState.notDownloaded),
            ]),
          ),
          actions: HelixBubbleActions(
            onMediaTap: opened.add,
            onTransferTap: transfers.add,
          ),
        ),
      );
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      await tester.tap(find.byType(HelixMediaGrid));
      expect(opened, isEmpty);
      expect(transfers, [0]);
    });

    testWidgets('a running transfer shows progress and a cancel glyph', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        _bubble(
          const HelixMessage(
            id: 'p',
            outgoing: true,
            timeLabel: '1',
            content: HelixMediaContent([
              HelixMediaItem(
                transfer: HelixTransferState.uploading,
                progress: .4,
              ),
            ]),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });

  group('documents, audio, location, contact, view once', () {
    testWidgets('document shows name, size and type; taps open', (
      tester,
    ) async {
      var opened = 0;
      await pumpHelix(
        tester,
        _bubble(
          const HelixMessage(
            id: 'p',
            outgoing: false,
            timeLabel: '1',
            content: HelixDocumentContent(
              name: 'plan.pdf',
              sizeLabel: '482 KB',
              typeLabel: 'PDF',
            ),
          ),
          actions: HelixBubbleActions(onMediaTap: (_) {}),
        ),
      );
      expect(find.text('plan.pdf'), findsOneWidget);
      expect(find.text('482 KB · PDF'), findsOneWidget);
      await pumpHelix(
        tester,
        HelixDocumentTile(
          content: const HelixDocumentContent(name: 'a.pdf'),
          onTap: () => opened++,
        ),
      );
      await tester.tap(find.text('a.pdf'));
      expect(opened, 1);
    });

    testWidgets('voice note: play, speed, seek, position', (tester) async {
      var plays = 0;
      var speeds = 0;
      double? seek;
      await pumpHelix(
        tester,
        HelixAudioBubbleBody(
          outgoing: true,
          content: const HelixAudioContent(
            durationLabel: '0:23',
            positionLabel: '0:07',
            progress: .3,
            playing: true,
            speed: 1.5,
          ),
          onToggle: () => plays++,
          onSpeed: () => speeds++,
          onSeek: (f) => seek = f,
        ),
      );
      expect(find.text('0:07'), findsOneWidget);
      expect(find.text('1.5x'), findsOneWidget);
      expect(find.byIcon(Icons.pause), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause));
      await tester.tap(find.text('1.5x'));
      expect((plays, speeds), (1, 1));
      final wave = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_WaveformPainter',
      );
      final r = tester.getRect(wave);
      await tester.tapAt(Offset(r.left + r.width * .75, r.center.dy));
      expect(seek, closeTo(.75, .05));
    });

    testWidgets('speed label formatting', (tester) async {
      expect(HelixAudioBubbleBody.speedLabel(1), '1x');
      expect(HelixAudioBubbleBody.speedLabel(2), '2x');
      expect(HelixAudioBubbleBody.speedLabel(1.5), '1.5x');
    });

    testWidgets('unplayed incoming voice notes carry a dot; played do not', (
      tester,
    ) async {
      Future<int> dots(bool played, bool outgoing) async {
        await pumpHelix(
          tester,
          HelixAudioBubbleBody(
            outgoing: outgoing,
            content: HelixAudioContent(durationLabel: '0:05', played: played),
          ),
        );
        return find
            .byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.constraints?.maxWidth == 8 &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).shape == BoxShape.circle,
            )
            .evaluate()
            .length;
      }

      expect(await dots(false, false), 1);
      expect(await dots(true, false), 0);
      expect(await dots(false, true), 0);
    });

    testWidgets('audio not downloaded asks to download', (tester) async {
      var transfers = 0;
      await pumpHelix(
        tester,
        HelixAudioBubbleBody(
          outgoing: false,
          content: const HelixAudioContent(
            durationLabel: '0:05',
            transfer: HelixTransferState.notDownloaded,
          ),
          onTransferTap: () => transfers++,
        ),
      );
      await tester.tap(find.byIcon(Icons.arrow_downward));
      expect(transfers, 1);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
    });

    testWidgets('location shows label and address', (tester) async {
      var taps = 0;
      await pumpHelix(
        tester,
        HelixLocationCard(
          content: const HelixLocationContent(
            label: 'Station',
            address: 'North gate',
          ),
          onTap: () => taps++,
        ),
      );
      expect(find.text('Station'), findsOneWidget);
      expect(find.text('North gate'), findsOneWidget);
      await tester.tap(find.text('Station'));
      expect(taps, 1);
    });

    testWidgets('contact shows name and detail', (tester) async {
      await pumpHelix(
        tester,
        const HelixContactCard(
          content: HelixContactContent(
            name: 'Aisha Khan',
            detail: '+44 7700 900456',
            onHelix: true,
          ),
        ),
      );
      expect(find.text('Aisha Khan'), findsOneWidget);
      expect(find.text('+44 7700 900456'), findsOneWidget);
    });

    testWidgets('view once: tap to view, then opened and inert', (
      tester,
    ) async {
      var taps = 0;
      await pumpHelix(
        tester,
        HelixViewOnceTile(
          content: const HelixViewOnceContent(),
          outgoing: false,
          onTap: () => taps++,
        ),
      );
      expect(find.text('Tap to view'), findsOneWidget);
      await tester.tap(find.text('Photo'));
      expect(taps, 1);
      await pumpHelix(
        tester,
        HelixViewOnceTile(
          content: const HelixViewOnceContent(opened: true),
          outgoing: false,
          onTap: () => taps++,
        ),
      );
      expect(find.text('Opened'), findsOneWidget);
      await tester.tap(find.text('Photo'));
      expect(taps, 1);
    });

    testWidgets('your own view-once media cannot be opened by you', (
      tester,
    ) async {
      var taps = 0;
      await pumpHelix(
        tester,
        HelixViewOnceTile(
          content: const HelixViewOnceContent(isVideo: true),
          outgoing: true,
          onTap: () => taps++,
        ),
      );
      expect(find.text('Video'), findsOneWidget);
      await tester.tap(find.text('Video'));
      expect(taps, 0);
    });
  });

  group('conversation furniture', () {
    testWidgets('date separator, notice, unread divider', (tester) async {
      await pumpHelix(
        tester,
        const Column(
          children: [
            HelixDateSeparator(label: 'Today'),
            HelixSystemNotice(text: 'Sam added Lee', icon: Icons.person_add),
            HelixUnreadDivider(count: 3),
            HelixUnreadDivider(count: 1),
          ],
        ),
      );
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Sam added Lee'), findsOneWidget);
      expect(find.text('3 unread messages'), findsOneWidget);
      expect(find.text('1 unread message'), findsOneWidget);
    });

    testWidgets('typing indicator is a live region and settles', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHelix(
        tester,
        const HelixTypingIndicator(label: 'Sam is typing'),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Sam is typing'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('timeline rows pick the right component', (tester) async {
      await pumpHelix(
        tester,
        Column(
          children: [
            const HelixTimelineRow(item: HelixDateSeparatorItem('Today')),
            const HelixTimelineRow(item: HelixUnreadDividerItem(2)),
            const HelixTimelineRow(item: HelixSystemNoticeItem('n', 'Notice')),
            HelixTimelineRow(item: HelixMessageItem(_text('bubble'))),
          ],
        ),
      );
      expect(find.byType(HelixDateSeparator), findsOneWidget);
      expect(find.byType(HelixUnreadDivider), findsOneWidget);
      expect(find.byType(HelixSystemNotice), findsOneWidget);
      expect(find.byType(HelixMessageBubble), findsOneWidget);
    });

    testWidgets('conversation list is bottom-anchored with a footer', (
      tester,
    ) async {
      final items = <HelixTimelineItem>[
        for (var i = 3; i >= 1; i--)
          HelixMessageItem(
            HelixMessage(
              id: 'm$i',
              outgoing: i.isEven,
              timeLabel: '1',
              content: HelixTextContent('message $i'),
            ),
          ),
      ];
      await pumpHelix(
        tester,
        HelixConversationList(
          itemsNewestFirst: items,
          footer: const HelixTypingIndicator(animate: false),
          indexOfId: {for (final (i, e) in items.indexed) e.id: i},
        ),
      );
      expect(find.byType(HelixMessageBubble), findsNWidgets(3));
      final newest = tester.getRect(
        find.textContaining('message 3', findRichText: true),
      );
      final typing = tester.getRect(find.byType(HelixTypingIndicator));
      expect(typing.top, greaterThan(newest.bottom));
    });
  });

  group('reaction picker and action menu', () {
    testWidgets('picking reports the emoji; current is marked', (tester) async {
      final picked = <String>[];
      await pumpHelix(
        tester,
        Center(
          child: HelixReactionPicker(onPick: picked.add, current: '❤️'),
        ),
      );
      await tester.tap(find.text('😂'));
      expect(picked, ['😂']);
    });

    testWidgets('menu returns action ids and reactions', (tester) async {
      String? result;
      await pumpHelix(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showHelixMessageActionMenu(
              context,
              actions: helixDefaultMessageActions(outgoing: false),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(result, HelixMessageActionIds.reply);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('👍'));
      await tester.pumpAndSettle();
      expect(result, 'react:👍');
    });

    testWidgets('no picker when reactions are not allowed', (tester) async {
      await pumpHelix(
        tester,
        HelixMessageActionMenu(
          actions: helixDefaultMessageActions(outgoing: true),
          onAction: (_) {},
        ),
      );
      expect(find.byType(HelixReactionPicker), findsNothing);
    });
  });
}

void wallpaperTests() {
  testWidgets('the chat wallpaper paints its pattern behind the child', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HelixThemes.light(),
        home: const HelixChatWallpaper(child: Text('over the pattern')),
      ),
    );

    expect(find.text('over the pattern'), findsOneWidget);
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(HelixChatWallpaper),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(paint.painter, isNotNull);
    // The page colour is under the pattern.
    final base = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(HelixChatWallpaper),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(base.color, HelixChatColors.page);
  });
}
