import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/harness.dart';

void main() {
  group('HelixComposer', () {
    testWidgets('empty: mic and camera; text: send and no camera', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpHelix(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: HelixComposer(controller: controller, onSend: () {}),
        ),
      );
      expect(find.byType(HelixMicButton), findsOneWidget);
      expect(find.byTooltip('Send'), findsNothing);
      expect(find.byTooltip('Camera'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(find.byType(HelixMicButton), findsNothing);
      expect(find.byTooltip('Send'), findsOneWidget);
      expect(find.byTooltip('Camera'), findsNothing);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(
        find.byType(HelixMicButton),
        findsOneWidget,
        reason: 'blank is empty',
      );
    });

    testWidgets('send and the side buttons reach their callbacks', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'hi');
      addTearDown(controller.dispose);
      final calls = <String>[];
      await pumpHelix(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: HelixComposer(
            controller: controller,
            onSend: () => calls.add('send'),
            onEmoji: () => calls.add('emoji'),
            onAttach: () => calls.add('attach'),
            onCamera: () => calls.add('camera'),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.tap(find.byTooltip('Emoji'));
      await tester.tap(find.byTooltip('Attach'));
      expect(calls, ['send', 'emoji', 'attach']);
      controller.clear();
      await tester.pump();
      await tester.tap(find.byTooltip('Camera'));
      expect(calls.last, 'camera');
    });

    testWidgets('grows with the text up to the line cap, then scrolls', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpHelix(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: HelixComposer(controller: controller, onSend: () {}),
        ),
      );
      double height() => tester.getSize(find.byType(HelixComposer)).height;
      final one = height();
      controller.text = List.filled(3, 'line').join('\n');
      await tester.pump();
      final three = height();
      controller.text = List.filled(12, 'line').join('\n');
      await tester.pump();
      final many = height();
      controller.text = 'line';
      await tester.pump();
      expect(three, greaterThan(one));
      expect(many, greaterThan(three));
      expect(height(), one, reason: 'shrinks back');
      controller.text = List.filled(30, 'line').join('\n');
      await tester.pump();
      expect(height(), many, reason: 'capped at maxLines');
    });

    testWidgets('edit mode saves, and cannot save nothing', (tester) async {
      final controller = TextEditingController(text: 'fixed');
      addTearDown(controller.dispose);
      var sends = 0;
      await pumpHelix(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: HelixComposer(
            controller: controller,
            onSend: () => sends++,
            editing: true,
            banner: const HelixComposerBannerModel(
              kind: HelixComposerBannerKind.edit,
              title: 'Edit message',
              text: 'old',
            ),
          ),
        ),
      );
      expect(find.text('Edit message'), findsOneWidget);
      await tester.tap(find.byTooltip('Save edit'));
      expect(sends, 1);
      controller.clear();
      await tester.pump();
      await tester.tap(find.byTooltip('Save edit'));
      expect(sends, 1);
      expect(
        find.byType(HelixMicButton),
        findsNothing,
        reason: 'no mic while editing',
      );
    });

    testWidgets('reply banner closes with a labelled button', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var closed = 0;
      await pumpHelix(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: HelixComposer(
            controller: controller,
            onSend: () {},
            onBannerClose: () => closed++,
            banner: const HelixComposerBannerModel(
              kind: HelixComposerBannerKind.reply,
              title: 'Replying to Sam',
              text: 'Hello',
            ),
          ),
        ),
      );
      expect(find.text('Replying to Sam'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel reply'));
      expect(closed, 1);
    });

    testWidgets('disabled composer shows its reason instead of a field', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpHelix(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: HelixComposer(
            controller: controller,
            onSend: () {},
            disabledMessage: 'You blocked this contact.',
          ),
        ),
      );
      expect(find.text('You blocked this contact.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('recording swaps the field for the record bar', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var cancelled = 0;
      var sent = 0;
      Widget composer(HelixVoiceRecordState state) => Align(
        alignment: Alignment.bottomCenter,
        child: HelixComposer(
          controller: controller,
          onSend: () {},
          recording: state,
          onRecordingCancel: () => cancelled++,
          onRecordingSend: () => sent++,
        ),
      );
      await pumpHelix(
        tester,
        composer(const HelixVoiceRecordState(elapsedLabel: '0:07')),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('0:07'), findsOneWidget);
      expect(find.text('Slide to cancel'), findsOneWidget);
      expect(find.byType(HelixVoiceLockHint), findsOneWidget);

      await pumpHelix(
        tester,
        composer(
          const HelixVoiceRecordState(elapsedLabel: '0:31', locked: true),
        ),
      );
      expect(find.text('Slide to cancel'), findsNothing);
      expect(find.byType(HelixMicButton), findsNothing);
      await tester.tap(find.byTooltip('Delete recording'));
      await tester.tap(find.byTooltip('Send recording'));
      expect((cancelled, sent), (1, 1));
    });

    testWidgets('mention suggestions: rows capped at four, tap selects', (
      tester,
    ) async {
      HelixMentionCandidate? picked;
      await pumpHelix(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: HelixMentionSuggestions(
            candidates: [
              for (var i = 0; i < 9; i++)
                HelixMentionCandidate(id: '$i', name: 'Person $i'),
            ],
            onSelected: (c) => picked = c,
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(HelixMentionSuggestions)).height,
        HelixMentionSuggestions.rowHeight * HelixMentionSuggestions.maxRows,
      );
      await tester.tap(find.text('Person 1'));
      expect(picked?.id, '1');
    });
  });

  group('HelixMicButton gestures', () {
    Future<(List<String>, TestGesture)> hold(WidgetTester tester) async {
      final events = <String>[];
      await pumpHelix(
        tester,
        Center(
          child: HelixMicButton(
            onTap: () => events.add('tap'),
            onStart: () => events.add('start'),
            onSlide: (c, l) => events.add(
              'slide ${c.toStringAsFixed(1)} ${l.toStringAsFixed(1)}',
            ),
            onLock: () => events.add('lock'),
            onCancel: () => events.add('cancel'),
            onEnd: () => events.add('end'),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HelixMicButton)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      return (events, gesture);
    }

    testWidgets('a quick tap only taps', (tester) async {
      final events = <String>[];
      await pumpHelix(
        tester,
        Center(
          child: HelixMicButton(
            onTap: () => events.add('tap'),
            onStart: () => events.add('start'),
          ),
        ),
      );
      await tester.tap(find.byType(HelixMicButton));
      expect(events, ['tap']);
    });

    testWidgets('hold and release sends', (tester) async {
      final (events, gesture) = await hold(tester);
      expect(events, ['start']);
      await gesture.up();
      expect(events, ['start', 'end']);
    });

    testWidgets('sliding towards the start far enough cancels once', (
      tester,
    ) async {
      final (events, gesture) = await hold(tester);
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.moveBy(const Offset(-80, 0));
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.up();
      expect(events.where((e) => e == 'cancel'), hasLength(1));
      expect(events, isNot(contains('end')));
      expect(events, contains('slide 0.5 0.0'));
    });

    testWidgets('sliding up far enough locks and does not send on release', (
      tester,
    ) async {
      final (events, gesture) = await hold(tester);
      await gesture.moveBy(const Offset(0, -90));
      await gesture.up();
      expect(events, contains('lock'));
      expect(events, isNot(contains('end')));
      expect(events, isNot(contains('cancel')));
    });

    testWidgets('in RTL, cancel is a slide to the right', (tester) async {
      final events = <String>[];
      await pumpHelix(
        tester,
        Center(
          child: HelixMicButton(
            onStart: () => events.add('start'),
            onCancel: () => events.add('cancel'),
          ),
        ),
        direction: TextDirection.rtl,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HelixMicButton)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(130, 0));
      await gesture.up();
      expect(events, ['start', 'cancel']);
    });
  });

  group('sheets, dialogs, snackbars', () {
    testWidgets('attachment sheet returns the chosen id', (tester) async {
      String? chosen;
      await pumpHelix(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                chosen = await showHelixAttachmentSheet(context),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      for (final label in [
        'Document',
        'Camera',
        'Gallery',
        'Audio',
        'Location',
        'Contact',
        'Poll',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();
      expect(chosen, 'location');
    });

    testWidgets('text input dialog trims, cancels, and disposes cleanly', (
      tester,
    ) async {
      String? result = 'unset';
      await pumpHelix(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showHelixTextInputDialog(
              context,
              title: 'Rename',
              initialValue: 'Sam',
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Samuel  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, 'Samuel');

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('confirm dialog returns the choice', (tester) async {
      bool? result;
      await pumpHelix(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showHelixConfirmDialog(
              context,
              title: 'Block?',
              message: 'They will not reach you.',
              confirmLabel: 'Block',
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('snackbar shows its action and replaces the previous one', (
      tester,
    ) async {
      var undone = 0;
      await pumpHelix(
        tester,
        Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => showHelixSnackBar(context, 'First'),
                child: const Text('one'),
              ),
              TextButton(
                onPressed: () => showHelixSnackBar(
                  context,
                  'Chat archived',
                  actionLabel: 'Undo',
                  onAction: () => undone++,
                ),
                child: const Text('two'),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('one'));
      await tester.pump();
      await tester.tap(find.text('two'));
      await tester.pumpAndSettle();
      expect(find.text('Chat archived'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      expect(undone, 1);
    });
  });

  group('search, people, calls', () {
    testWidgets('search field clears and reports', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final seen = <String>[];
      await pumpHelix(
        tester,
        HelixSearchField(controller: controller, onChanged: seen.add),
      );
      expect(find.byTooltip('Clear search'), findsNothing);
      await tester.enterText(find.byType(TextField), 'sam');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(seen, ['sam', '']);
      expect(find.byTooltip('Clear search'), findsNothing);
    });

    testWidgets('search app bar toggles between title and field', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var searching = false;
      late StateSetter set;
      await tester.pumpWidget(
        MaterialApp(
          theme: HelixThemes.light(),
          home: StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return Scaffold(
                appBar: HelixSearchAppBar(
                  title: 'Chats',
                  searching: searching,
                  controller: controller,
                  onSearchChanged: (v) => set(() => searching = v),
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('Chats'), findsOneWidget);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'x');
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.text('Chats'), findsOneWidget);
      expect(controller.text, isEmpty);
    });

    testWidgets(
      'highlighted text emphasises valid ranges and ignores bad ones',
      (tester) async {
        await pumpHelix(
          tester,
          const HelixHighlightedTextView(
            text: HelixHighlightedText('hello brave world', [
              HelixTextRange(6, 5),
              HelixTextRange(100, 3),
              HelixTextRange(-1, 2),
            ]),
          ),
        );
        final rich = tester.widget<RichText>(find.byType(RichText).first);
        final bold = <String>[];
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.style?.fontWeight == FontWeight.w700) {
            bold.add(span.text!);
          }
          return true;
        });
        expect(bold, ['brave']);
        expect(rich.text.toPlainText(), 'hello brave world');
      },
    );

    testWidgets('person tiles show the naming order', (tester) async {
      await pumpHelix(
        tester,
        const Column(
          children: [
            HelixPersonTile(
              person: HelixPersonItem(
                id: '1',
                names: HelixPersonNames(
                  phoneBookName: 'Aisha Khan',
                  nickname: 'Ash',
                  number: '+44 7700 900456',
                  helixName: 'aisha',
                ),
              ),
            ),
            HelixPersonTile(
              person: HelixPersonItem(
                id: '2',
                names: HelixPersonNames(
                  number: '+44 7700 900123',
                  helixName: 'kofi',
                ),
              ),
            ),
            HelixPersonTile(
              person: HelixPersonItem(
                id: '3',
                names: HelixPersonNames(helixName: 'nadia'),
              ),
            ),
            HelixPersonTile(
              person: HelixPersonItem(
                id: '4',
                names: HelixPersonNames(nickname: 'Blocked Bob'),
                blocked: true,
              ),
            ),
          ],
        ),
      );
      expect(find.text('Aisha Khan'), findsOneWidget);
      expect(
        find.text('Ash'),
        findsNothing,
        reason: 'nickname loses to the phone book',
      );
      expect(find.text('+44 7700 900456'), findsOneWidget);
      expect(find.text('+44 7700 900123'), findsOneWidget);
      expect(find.text('~kofi'), findsOneWidget);
      expect(find.text('~nadia'), findsOneWidget);
      expect(find.text('Blocked'), findsOneWidget);
    });

    testWidgets('person, message-search and call rows share the chat extent', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        const Column(
          children: [
            HelixPersonTile(
              person: HelixPersonItem(
                id: '1',
                names: HelixPersonNames(helixName: 'a'),
              ),
            ),
            HelixCallLogTile(
              item: HelixCallLogItem(
                id: 'k',
                title: 'Sam',
                avatar: HelixAvatarModel(name: 'Sam'),
                direction: HelixCallDirection.incoming,
                timeLabel: 'Today',
              ),
            ),
          ],
        ),
        textScale: 2,
      );
      final extent = HelixChatListTile.extentFor(const TextScaler.linear(2));
      expect(tester.getSize(find.byType(HelixPersonTile)).height, extent);
      expect(tester.getSize(find.byType(HelixCallLogTile)).height, extent);
      expect(tester.takeException(), isNull);
    });

    testWidgets('call log: missed is red, count folds, call back works', (
      tester,
    ) async {
      var calls = 0;
      await pumpHelix(
        tester,
        HelixCallLogTile(
          item: const HelixCallLogItem(
            id: 'k',
            title: 'Sam',
            avatar: HelixAvatarModel(name: 'Sam'),
            direction: HelixCallDirection.missed,
            timeLabel: 'Today, 14:05',
            count: 3,
            video: true,
          ),
          onCallBack: () => calls++,
        ),
      );
      final title = tester.widget<Text>(find.text('Sam (3)'));
      expect(title.style?.color, HelixThemes.light().colorScheme.error);
      expect(find.byIcon(Icons.call_missed), findsOneWidget);
      await tester.tap(find.byTooltip('Video call'));
      expect(calls, 1);
    });

    testWidgets('message search tile shows chat, time and snippet', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        const HelixMessageSearchTile(
          result: HelixMessageSearchResult(
            id: 'r',
            chatTitle: 'Weekend hike',
            avatar: HelixAvatarModel(name: 'Weekend hike', isGroup: true),
            snippet: HelixHighlightedText('Who has the stove', [
              HelixTextRange(12, 5),
            ]),
            timeLabel: 'Yesterday',
            senderLabel: 'Lee',
          ),
        ),
      );
      expect(find.text('Weekend hike'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Lee: '), findsOneWidget);
    });

    testWidgets('no results mentions the query', (tester) async {
      await pumpHelix(tester, const HelixNoResults(query: 'zzz'));
      expect(find.textContaining('zzz'), findsOneWidget);
    });
  });

  group('settings, banners', () {
    testWidgets('settings tiles: tap, switch row toggles, destructive', (
      tester,
    ) async {
      var taps = 0;
      bool? toggled;
      await pumpHelix(
        tester,
        SingleChildScrollView(
          child: HelixSettingsSection(
            title: 'Privacy',
            footer: 'Footnote',
            children: [
              HelixSettingsTile(
                title: 'Blocked',
                subtitle: '2 contacts',
                showChevron: true,
                onTap: () => taps++,
              ),
              HelixSettingsSwitchTile(
                title: 'Read receipts',
                value: true,
                onChanged: (v) => toggled = v,
              ),
              const HelixSettingsTile(title: 'Log out', destructive: true),
            ],
          ),
        ),
      );
      expect(find.text('Privacy'), findsOneWidget);
      expect(find.text('Footnote'), findsOneWidget);
      await tester.tap(find.text('Blocked'));
      expect(taps, 1);
      await tester.tap(find.text('Read receipts'));
      expect(toggled, isFalse);
      final scheme = HelixThemes.light().colorScheme;
      expect(
        tester.widget<Text>(find.text('Log out')).style?.color,
        scheme.error,
      );
    });

    testWidgets('banners: kinds, default text, action', (tester) async {
      var updates = 0;
      await pumpHelix(
        tester,
        SingleChildScrollView(
          child: Column(
            children: [
              const HelixBanner(kind: HelixBannerKind.offline),
              const HelixBanner(kind: HelixBannerKind.connecting),
              HelixBanner(
                kind: HelixBannerKind.updateAvailable,
                actionLabel: 'Update',
                onAction: () => updates++,
              ),
              const HelixBanner(
                kind: HelixBannerKind.info,
                message: 'Heads up',
              ),
            ],
          ),
        ),
      );
      expect(find.textContaining('No connection'), findsOneWidget);
      expect(find.text('Connecting...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Heads up'), findsOneWidget);
      await tester.tap(find.text('Update'));
      expect(updates, 1);
    });

    testWidgets('profile header', (tester) async {
      var taps = 0;
      await pumpHelix(
        tester,
        HelixProfileHeaderTile(
          avatar: const HelixAvatarModel(name: 'Lee Chen'),
          name: 'Lee Chen',
          about: 'On the trail',
          onTap: () => taps++,
        ),
      );
      await tester.tap(find.text('Lee Chen'));
      expect(taps, 1);
      expect(find.text('On the trail'), findsOneWidget);
    });
  });

  group('safety number and QR', () {
    testWidgets('digits are grouped in a grid and spoken one by one', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final groups = [for (var i = 0; i < 12; i++) '${10000 + i * 111}'];
      await pumpHelix(
        tester,
        HelixSafetyNumberView(groups: groups, verified: true),
      );
      for (final g in groups) {
        expect(find.text(g), findsOneWidget);
      }
      expect(find.text('Verified'), findsOneWidget);
      final node = tester.getSemantics(
        find.bySemanticsLabel('Safety number, verified'),
      );
      expect(node.value, startsWith('1 0 0 0 0, '));
      handle.dispose();
    });

    test('spoken form separates digits', () {
      expect(HelixSafetyNumberView.spoken(['123', '45']), '1 2 3, 4 5');
    });

    testWidgets('QR display paints the matrix on a white quiet zone', (
      tester,
    ) async {
      final matrix = HelixQrMatrix(3, const [
        true, false, true, //
        false, true, false,
        true, false, true,
      ]);
      final key = GlobalKey();
      await pumpHelix(
        tester,
        Center(
          child: RepaintBoundary(
            key: key,
            child: HelixQrDisplay(matrix: matrix, size: 110),
          ),
        ),
      );
      // 3 modules + 2 * 4 quiet = 11 cells of 10 px: the centre cell is dark,
      // the corner of the quiet zone is white.
      final image = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        return boundary.toImage();
      });
      final bytes = await tester.runAsync(() => image!.toByteData());
      int pixel(int x, int y) {
        final i = (y * image!.width + x) * 4;
        return bytes!.getUint8(i);
      }

      expect(pixel(5, 5), 255, reason: 'quiet zone is white');
      expect(pixel(45, 45), 0, reason: 'first module is dark');
      expect(pixel(55, 45), 255, reason: 'second module is light');
    });

    testWidgets('scan frame shows the hint over the camera child', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        const SizedBox(
          height: 300,
          child: HelixQrScanFrame(
            child: ColoredBox(color: HelixScrimColors.backdrop),
          ),
        ),
      );
      expect(find.text('Point the camera at the QR code'), findsOneWidget);
    });
  });

  group('shimmer and skeleton', () {
    testWidgets('shimmer does not animate under reduced motion', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        const HelixShimmer(child: HelixSkeleton(height: 20)),
      );
      // pumpHelix disables animations: settling must not time out.
      await tester.pumpAndSettle();
    });

    testWidgets('shimmer animates and stops cleanly otherwise', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HelixThemes.light(),
          home: const Scaffold(
            body: HelixShimmer(child: HelixSkeleton(height: 20)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
