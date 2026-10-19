import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Phase 4 batch 5: the call screen and call details. How they look is
/// checked against the prototype by the compare tool (`call-*`).
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

  CallModel call(
    CallStage stage, {
    bool video = false,
    String status = '',
    bool videoLayout = false,
    List<CallAudioRoute> routes = const [
      CallAudioRoute.earpiece,
      CallAudioRoute.speaker,
    ],
    CallAudioRoute route = CallAudioRoute.earpiece,
    String? notice,
  }) => CallModel(
    callId: 'c',
    title: 'Nadia Rahman',
    subtitle: '+880 1712-458921',
    avatar: const HelixAvatarModel(name: 'Nadia Rahman'),
    stage: stage,
    statusText: status,
    video: video,
    cameraOn: video,
    videoLayout: videoLayout,
    audioRoutes: routes,
    audioRoute: route,
    elapsedLabel: '00:12',
    notice: notice,
  );

  testWidgets('an incoming call answers and declines', (tester) async {
    var answered = 0;
    var declined = 0;
    await show(
      tester,
      CallScreen(
        model: call(CallStage.incoming, status: 'Incoming voice call'),
        actions: CallActions(
          answer: () => answered++,
          decline: () => declined++,
        ),
      ),
    );
    expect(find.text('INCOMING VOICE CALL'), findsOneWidget);
    await tester.tap(find.byTooltip('Answer call'));
    await tester.tap(find.byTooltip('Decline call'));
    expect((answered, declined), (1, 1));
  });

  testWidgets('a live voice call mutes, uses the speaker and ends', (
    tester,
  ) async {
    bool? muted;
    CallAudioRoute? route;
    var ended = 0;
    await show(
      tester,
      CallScreen(
        model: call(CallStage.active),
        actions: CallActions(
          setMuted: (v) => muted = v,
          selectAudioRoute: (r) => route = r,
          hangUp: () => ended++,
        ),
      ),
    );
    expect(find.text('00:12'), findsOneWidget);
    await tester.tap(find.byTooltip('Mute microphone'));
    await tester.tap(find.byTooltip('Turn speaker on'));
    await tester.tap(find.byTooltip('End call'));
    expect(muted, isTrue);
    expect(route, CallAudioRoute.speaker);
    expect(ended, 1);
  });

  testWidgets('with a headset there is an output sheet', (tester) async {
    CallAudioRoute? route;
    await show(
      tester,
      CallScreen(
        model: call(
          CallStage.active,
          routes: const [
            CallAudioRoute.earpiece,
            CallAudioRoute.speaker,
            CallAudioRoute.bluetooth,
          ],
          route: CallAudioRoute.bluetooth,
        ),
        actions: CallActions(selectAudioRoute: (r) => route = r),
      ),
    );
    await tester.tap(find.byTooltip('Audio output: Bluetooth'));
    await tester.pumpAndSettle();
    expect(find.text('Audio output'), findsOneWidget);
    await tester.tap(find.text('Speaker'));
    await tester.pumpAndSettle();
    expect(route, CallAudioRoute.speaker);
  });

  testWidgets('an ended call disables every control', (tester) async {
    var ended = 0;
    await show(
      tester,
      CallScreen(
        model: call(CallStage.ended, status: 'Call ended'),
        actions: CallActions(hangUp: () => ended++),
      ),
    );
    expect(find.text('CALL ENDED'), findsOneWidget);
    await tester.tap(find.byTooltip('End call'), warnIfMissed: false);
    expect(ended, 0);
  });

  testWidgets('a notice can be dismissed', (tester) async {
    var dismissed = 0;
    await show(
      tester,
      CallScreen(
        model: call(CallStage.incoming, notice: 'Orbit needs the microphone.'),
        actions: CallActions(dismissNotice: () => dismissed++),
      ),
    );
    expect(find.text('Orbit needs the microphone.'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    expect(dismissed, 1);
  });

  testWidgets('a live video call hides its controls on a tap', (tester) async {
    await show(
      tester,
      CallScreen(model: call(CallStage.active, video: true, videoLayout: true)),
    );
    expect(find.byTooltip('Flip camera'), findsOneWidget);
    await tester.tapAt(const Offset(200, 450));
    await tester.pump();
    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byTooltip('Flip camera'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, 0);
  });

  testWidgets('call details: calls, delete asks first, blocked hides calls', (
    tester,
  ) async {
    var deleted = 0;
    const rows = [
      CallDetailRowModel(
        callId: 'a',
        direction: CallLogDirection.missed,
        label: 'Missed voice call',
        timeLabel: 'Yesterday, 19:02',
      ),
      CallDetailRowModel(
        callId: 'b',
        direction: CallLogDirection.incoming,
        label: 'Incoming voice call',
        timeLabel: 'Yesterday, 21:30',
        durationLabel: '32:18',
      ),
    ];
    await show(
      tester,
      CallDetailScreen(
        model: const CallDetailModel(
          title: 'Ammu',
          avatar: HelixAvatarModel(name: 'Ammu'),
          rows: rows,
        ),
        actions: CallDetailActions(deleteAll: () => deleted++),
      ),
    );
    expect(find.text('32:18'), findsOneWidget);
    expect(find.byTooltip('Voice call'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete from call history'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'These 2 calls with Ammu will be removed from your call history.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
    await show(
      tester,
      const CallDetailScreen(
        model: CallDetailModel(
          title: 'Ammu',
          avatar: HelixAvatarModel(name: 'Ammu'),
          canCall: false,
          blockedReason: 'Ammu has blocked you.',
        ),
      ),
    );
    expect(find.byTooltip('Voice call'), findsNothing);
    expect(find.byTooltip('Contact'), findsOneWidget);
  });

  group("the app's hooks", () {
    testWidgets('the status is announced in words, the clock as a duration', (
      tester,
    ) async {
      await show(
        tester,
        CallScreen(
          model: call(CallStage.incoming, status: 'Incoming voice call'),
        ),
      );
      expect(find.bySemanticsLabel('Incoming voice call'), findsOneWidget);
      expect(find.bySemanticsLabel('Picture of Nadia Rahman'), findsOneWidget);
      await show(tester, CallScreen(model: call(CallStage.active)));
      expect(find.bySemanticsLabel('Call duration 00:12'), findsOneWidget);
    });

    testWidgets('a live call says Connected until its clock ticks', (
      tester,
    ) async {
      await show(
        tester,
        const CallScreen(
          model: CallModel(
            callId: 'c',
            title: 'Nadia Rahman',
            avatar: HelixAvatarModel(name: 'Nadia Rahman'),
            stage: CallStage.active,
            statusText: 'Connected',
          ),
        ),
      );
      expect(find.text('CONNECTED'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
    });

    testWidgets('with two outputs the toggle picks the other one', (
      tester,
    ) async {
      final picked = <CallAudioRoute>[];
      await show(
        tester,
        CallScreen(
          model: call(
            CallStage.active,
            routes: const [CallAudioRoute.speaker, CallAudioRoute.wiredHeadset],
            route: CallAudioRoute.wiredHeadset,
          ),
          actions: CallActions(selectAudioRoute: picked.add),
        ),
      );
      await tester.tap(find.byTooltip('Audio output: Headset'));
      expect(picked, [CallAudioRoute.speaker]);
    });

    testWidgets('the app draws the pictures, with a stand-in until frames', (
      tester,
    ) async {
      await show(
        tester,
        CallScreen(
          model: const CallModel(
            callId: 'c',
            title: 'Nadia Rahman',
            avatar: HelixAvatarModel(name: 'Nadia Rahman'),
            stage: CallStage.active,
            statusText: '',
            elapsedLabel: '00:12',
            video: true,
            cameraOn: true,
            videoLayout: true,
            hasLocalVideo: true,
          ),
          remoteVideo: (context, placeholder) => placeholder,
          localVideo: (context, placeholder) => const Text('mine'),
        ),
      );
      // Their picture waits on the gradient; yours is in the tile.
      expect(find.text('NR'), findsWidgets);
      expect(find.text('mine'), findsOneWidget);
      expect(find.bySemanticsLabel('Video from Nadia Rahman'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Show your camera full screen'),
        findsOneWidget,
      );
      await tester.tap(find.text('mine'));
      await tester.pump();
      expect(find.bySemanticsLabel('Your camera'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Show Nadia Rahman full screen'),
        findsOneWidget,
      );
    });

    testWidgets('your tile cannot be dragged off the screen', (tester) async {
      await show(
        tester,
        CallScreen(
          model: call(CallStage.active, video: true, videoLayout: true),
        ),
      );
      final tile = find.bySemanticsLabel('Show your camera full screen');
      await tester.drag(tile, const Offset(-5000, 5000));
      await tester.pump();
      final at = tester.getRect(tile);
      expect(at.left, greaterThanOrEqualTo(0));
      expect(at.bottom, lessThanOrEqualTo(866));
    });

    testWidgets("call details wait on a call and say why it did not start", (
      tester,
    ) async {
      final placing = Completer<String?>();
      await show(
        tester,
        CallDetailScreen(
          model: const CallDetailModel(
            title: 'Ammu',
            avatar: HelixAvatarModel(name: 'Ammu'),
          ),
          actions: CallDetailActions(voiceCall: () => placing.future),
        ),
      );
      await tester.tap(find.byTooltip('Voice call'));
      await tester.pump();
      expect(find.byType(OrbitSpinner), findsOneWidget);
      placing.complete('You are already in a call.');
      await tester.pump();
      await tester.pump();
      expect(find.byType(OrbitSpinner), findsNothing);
      expect(find.text('You are already in a call.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
