import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Sharing the screen in a video call: the Share button, the banner, and the
/// other side's screen drawn whole.
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
      MediaQuery(
        data: const MediaQueryData(
          size: Size(412, 866),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: OrbitTheme.of(orbit),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
  }

  CallModel live({
    bool video = true,
    bool canShare = true,
    bool sharing = false,
    bool theirs = false,
    CallStage stage = CallStage.active,
  }) => CallModel(
    callId: 'c',
    title: 'Nadia Rahman',
    avatar: const HelixAvatarModel(name: 'Nadia Rahman'),
    stage: stage,
    statusText: '',
    elapsedLabel: '00:12',
    video: video,
    cameraOn: video,
    videoLayout: video,
    canShareScreen: canShare,
    screenSharing: sharing,
    peerScreenSharing: theirs,
  );

  testWidgets('Share shows on a live video call and starts the share', (
    tester,
  ) async {
    final asked = <bool>[];
    await show(
      tester,
      CallScreen(
        model: live(),
        actions: CallActions(setScreenSharing: asked.add),
      ),
    );
    await tester.tap(find.byTooltip('Share your screen'));
    expect(asked, [true]);
  });

  testWidgets('while sharing, the button and the banner both stop it', (
    tester,
  ) async {
    final asked = <bool>[];
    await show(
      tester,
      CallScreen(
        model: live(sharing: true),
        actions: CallActions(setScreenSharing: asked.add),
      ),
    );
    expect(find.text('You are sharing your screen'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop sharing your screen').first);
    await tester.pump();
    expect(asked, [false]);
    await tester.tap(find.text('Stop'));
    expect(asked, [false, false]);
  });

  testWidgets('there is no Share on a voice call or without the action', (
    tester,
  ) async {
    await show(
      tester,
      CallScreen(
        model: live(video: false),
        actions: CallActions(setScreenSharing: (_) {}),
      ),
    );
    expect(find.byTooltip('Share your screen'), findsNothing);

    await show(tester, const SizedBox());
    await show(tester, CallScreen(model: live()));
    expect(find.byTooltip('Share your screen'), findsNothing);

    await show(tester, const SizedBox());
    await show(
      tester,
      CallScreen(
        model: live(canShare: false),
        actions: CallActions(setScreenSharing: (_) {}),
      ),
    );
    expect(find.byTooltip('Share your screen'), findsNothing);
  });

  testWidgets('Share waits until the call is live', (tester) async {
    final asked = <bool>[];
    await show(
      tester,
      CallScreen(
        model: live(stage: CallStage.connecting),
        actions: CallActions(setScreenSharing: asked.add),
      ),
    );
    await tester.tap(find.byTooltip('Share your screen'), warnIfMissed: false);
    expect(asked, isEmpty);
  });

  testWidgets('their shared screen is announced and drawn whole', (
    tester,
  ) async {
    final screens = <bool>[];
    await show(
      tester,
      CallScreen(
        model: live(theirs: true),
        remoteVideo: (context, placeholder, {required screen}) {
          screens.add(screen);
          return placeholder;
        },
      ),
    );
    expect(find.text('Nadia Rahman is sharing their screen'), findsOneWidget);
    expect(screens, contains(true));

    await show(tester, const SizedBox());
    screens.clear();
    await show(
      tester,
      CallScreen(
        model: live(),
        remoteVideo: (context, placeholder, {required screen}) {
          screens.add(screen);
          return placeholder;
        },
      ),
    );
    expect(screens, everyElement(isFalse));
    expect(find.textContaining('is sharing their screen'), findsNothing);
  });
}
