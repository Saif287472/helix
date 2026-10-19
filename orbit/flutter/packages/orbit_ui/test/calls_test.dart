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
}
