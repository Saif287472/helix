import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Phase 4 batch 4: the conversation's pages. How they look is checked
/// against the prototype by the compare tool.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Scaffold(body: screen),
      ),
    );
    await tester.pump();
  }

  const targets = [
    ForwardTargetItem(
      id: 'a',
      title: 'Arif Hossain',
      avatar: HelixAvatarModel(name: 'Arif Hossain'),
    ),
    ForwardTargetItem(
      id: 'f',
      title: 'Family',
      avatar: HelixAvatarModel(name: 'Family'),
    ),
  ];

  testWidgets('forward: picking shows Send, search filters', (tester) async {
    Set<String>? sent;
    await show(
      tester,
      ForwardScreen(
        model: const ForwardModel(messageCount: 1, targets: targets),
        actions: ForwardActions(onSend: (ids) async => sent = ids),
      ),
    );
    expect(find.text('Forward message'), findsOneWidget);
    expect(find.textContaining('Send to'), findsNothing);
    await tester.tap(find.text('Family'));
    await tester.tap(find.text('Arif Hossain'));
    await tester.pump();
    expect(find.text('Send to 2 chats'), findsOneWidget);
    await tester.tap(find.text('Send to 2 chats'));
    await tester.pump();
    expect(sent, {'a', 'f'});
    await tester.enterText(find.byType(EditableText), 'zz');
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);
    expect(find.text('Nothing matches “zz”.'), findsOneWidget);
  });

  testWidgets('message info lists receipts, and says when it is gone', (
    tester,
  ) async {
    await show(
      tester,
      const MessageInfoScreen(
        model: MessageInfoModel(
          message: HelixMessage(
            id: 'x',
            outgoing: true,
            content: HelixTextContent('Hi'),
            timeLabel: '18:40',
          ),
          sentLabel: 'Sunday, 18:40',
          isGroup: true,
          recipients: [
            ReceiptItem(
              name: 'Ammu',
              avatar: HelixAvatarModel(name: 'Ammu'),
              readLabel: 'Read Sunday, 18:41',
            ),
            ReceiptItem(
              name: 'Karim',
              avatar: HelixAvatarModel(name: 'K'),
            ),
          ],
        ),
      ),
    );
    expect(
      find.textContaining(RegExp('recipients', caseSensitive: false)),
      findsOneWidget,
    );
    expect(find.text('Read Sunday, 18:41'), findsOneWidget);
    expect(find.text('Not delivered yet'), findsOneWidget);
    await show(
      tester,
      const MessageInfoScreen(
        model: MessageInfoModel(loadState: MessageInfoState.notFound),
      ),
    );
    expect(find.text('Message not found'), findsOneWidget);
  });

  testWidgets('the viewer is a night page and counts its pages', (
    tester,
  ) async {
    await show(
      tester,
      const MediaViewerScreen(
        model: MediaViewerModel(
          title: 'Nadia Rahman',
          timeLabel: 'Today, 09:40',
          items: [
            ViewerItem(swatch: 'ph-a'),
            ViewerItem(swatch: 'ph-b'),
          ],
        ),
      ),
    );
    expect(find.text('Today, 09:40 (1 of 2)'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value.statusBarIconBrightness, Brightness.light);
  });

  testWidgets('a view-once you sent says so and offers no Share', (
    tester,
  ) async {
    await show(
      tester,
      const MediaViewerScreen(
        model: MediaViewerModel(
          state: ViewerState.viewOnceMine,
          title: 'View once',
          canShare: false,
        ),
      ),
    );
    expect(
      find.text('You cannot open a view-once message you sent.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Share'), findsNothing);
  });

  testWidgets('send files: View once only with pictures, × removes', (
    tester,
  ) async {
    String? removed;
    await show(
      tester,
      SendFilesScreen(
        model: const SendFilesModel(
          files: [
            SendFileItem(
              id: 'd',
              name: 'Invoice.pdf',
              sizeLabel: '312 KB',
              kind: SendFileKind.document,
            ),
          ],
        ),
        actions: SendFilesActions(onRemove: (id) => removed = id),
      ),
    );
    expect(find.text('Send file'), findsOneWidget);
    expect(find.text('View once'), findsNothing);
    await tester.tap(find.byTooltip('Remove Invoice.pdf'));
    expect(removed, 'd');
  });

  testWidgets('shared media switches tabs, each with its own empty state', (
    tester,
  ) async {
    await show(
      tester,
      const SharedMediaScreen(model: SharedMediaModel(title: 'Arif')),
    );
    expect(find.text('No media yet'), findsOneWidget);
    await tester.tap(find.text('Docs'));
    await tester.pump();
    expect(find.text('No documents yet'), findsOneWidget);
    await tester.tap(find.text('Links'));
    await tester.pump();
    expect(find.text('No links yet'), findsOneWidget);
  });

  testWidgets('chat settings: block asks first, unblock does not', (
    tester,
  ) async {
    var blocked = 0;
    var unblocked = 0;
    final actions = ChatSettingsActions(
      onBlock: () => blocked++,
      onUnblock: () => unblocked++,
    );
    await show(
      tester,
      ChatSettingsScreen(
        model: const ChatSettingsModel(
          title: 'Shuvo',
          avatar: HelixAvatarModel(name: 'Shuvo'),
        ),
        actions: actions,
      ),
    );
    await tester.tap(find.text('Block Shuvo'));
    await tester.pumpAndSettle();
    expect(find.text('Block Shuvo?'), findsOneWidget);
    expect(blocked, 0);
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(blocked, 1);
    await show(
      tester,
      ChatSettingsScreen(
        model: const ChatSettingsModel(
          title: 'Shuvo',
          avatar: HelixAvatarModel(name: 'Shuvo'),
          blocked: true,
        ),
        actions: actions,
      ),
    );
    await tester.tap(find.text('Unblock Shuvo'));
    expect(unblocked, 1);
  });

  testWidgets('a group has Group info and no block row', (tester) async {
    await show(
      tester,
      const ChatSettingsScreen(
        model: ChatSettingsModel(
          title: 'Family',
          avatar: HelixAvatarModel(name: 'Family'),
          isGroup: true,
        ),
      ),
    );
    expect(find.text('Group info'), findsOneWidget);
    expect(find.textContaining('Block'), findsNothing);
  });

  group('the viewer\'s hooks', () {
    const video = VideoView(
      playing: true,
      positionLabel: '0:07',
      durationLabel: '0:24',
      fraction: 0.3,
    );

    testWidgets('arrow keys turn the pages and report them', (tester) async {
      final pages = <int>[];
      await show(
        tester,
        MediaViewerScreen(
          model: const MediaViewerModel(
            title: 'Nadia Rahman',
            timeLabel: 'Today, 09:40',
            items: [
              ViewerItem(swatch: 'ph-a'),
              ViewerItem(swatch: 'ph-b'),
              ViewerItem(swatch: 'ph-c'),
            ],
          ),
          actions: MediaViewerActions(onPageChanged: pages.add),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('Today, 09:40 (2 of 3)'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('Today, 09:40 (1 of 3)'), findsOneWidget);
      expect(pages, [1, 0]);
    });

    testWidgets('one picture has no count; one not here hides Share', (
      tester,
    ) async {
      await show(
        tester,
        const MediaViewerScreen(
          model: MediaViewerModel(
            title: 'Nadia Rahman',
            timeLabel: 'Today, 09:40',
            items: [ViewerItem(swatch: 'ph-a', onDevice: false)],
          ),
        ),
      );
      expect(find.text('Today, 09:40'), findsOneWidget);
      expect(find.text('This file is not on your device yet.'), findsOneWidget);
      expect(find.byTooltip('Share'), findsNothing);
    });

    testWidgets('a message with nothing to show says so', (tester) async {
      await show(
        tester,
        const MediaViewerScreen(
          model: MediaViewerModel(state: ViewerState.empty, canShare: false),
        ),
      );
      expect(find.text('There is nothing to show here.'), findsOneWidget);
    });

    testWidgets('a playing video hides its controls after 3 seconds', (
      tester,
    ) async {
      var toggles = 0;
      final surface = Container(key: const Key('surface'), height: 200);
      await show(
        tester,
        MediaViewerScreen(
          model: MediaViewerModel(
            items: const [ViewerItem(isVideo: true)],
            video: VideoView(
              playing: video.playing,
              positionLabel: video.positionLabel,
              durationLabel: video.durationLabel,
              fraction: video.fraction,
              surface: surface,
            ),
          ),
          actions: MediaViewerActions(onVideoToggle: () => toggles++),
        ),
      );
      expect(find.byKey(const Key('surface')), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byTooltip('Pause'), findsNothing);
      await tester.tap(find.byKey(const Key('surface')));
      await tester.pump();
      await tester.tap(find.byTooltip('Pause'));
      expect(toggles, 1);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the seek bar follows the finger and seeks when let go', (
      tester,
    ) async {
      final seeks = <double>[];
      await show(
        tester,
        MediaViewerScreen(
          model: const MediaViewerModel(
            items: [ViewerItem(isVideo: true)],
            video: VideoView(durationLabel: '0:24'),
          ),
          actions: MediaViewerActions(onVideoSeek: seeks.add),
        ),
      );
      final bar = tester.getRect(find.byType(Slider));
      final drag = await tester.startGesture(
        bar.centerLeft + const Offset(4, 0),
      );
      await drag.moveTo(bar.center);
      await tester.pump();
      expect(seeks, isEmpty, reason: 'nothing until it is let go');
      await drag.up();
      await tester.pump();
      expect(seeks.single, closeTo(0.5, 0.05));
    });

    testWidgets("a video that cannot play gives the app's reason", (
      tester,
    ) async {
      var elsewhere = 0;
      await show(
        tester,
        MediaViewerScreen(
          model: const MediaViewerModel(
            items: [ViewerItem(isVideo: true)],
            video: VideoView(
              phase: VideoPhase.failed,
              message: 'This video stopped playing.',
            ),
          ),
          actions: MediaViewerActions(onOpenVideoElsewhere: (_) => elsewhere++),
        ),
      );
      expect(find.text('This video stopped playing.'), findsOneWidget);
      await tester.tap(find.text('Open video'));
      expect(elsewhere, 1);
    });
  });
}
