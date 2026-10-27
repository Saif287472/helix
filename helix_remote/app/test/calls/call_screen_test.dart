import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/calls/application/call_controller.dart';
import 'package:helix_remote/features/calls/application/call_effects.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote/features/calls/calls_routes.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:orbit_ui/models.dart';

import '../support/call_support.dart';
import '../support/harness.dart';
import '../support/names_support.dart';

/// The full-screen call: incoming, dialing, live (voice and video) and ended,
/// drawn from the call state, with the controls wired to the engine port.
void main() {
  var wall = DateTime.utc(2026, 10, 3, 9, 10);
  final names = directoryOf(const {
    'peer-1': HelixPersonNames(
      phoneBookName: 'Ada Lovelace',
      number: '+8801711000001',
    ),
  });

  late FakeCallsPort port;
  late FakeCallPermissions permissions;
  late FakeAudioPlatform audio;
  late CallMediaHub hub;

  /// Pumps a home with an "open" button that pushes the call route, taps it,
  /// and returns once the call screen is up.
  Future<void> open(WidgetTester tester, {Set<CallAudioRoute>? routes}) async {
    // The avatar's pulse repeats for ever; reduced motion turns it off so the
    // screen can settle.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    port = FakeCallsPort();
    permissions = FakeCallPermissions();
    audio = FakeAudioPlatform(routes);
    hub = CallMediaHub();
    await tester.pumpWidget(
      harness(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push(CallRoutes.call),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        routes: callsRoutes,
        overrides: callOverrides(
          port: port,
          permissions: permissions,
          audio: audio,
          hub: hub,
          names: names,
          clock: () => wall,
          linger: const Duration(milliseconds: 500),
        ),
      ),
    );
    // The first call arrives before the screen opens, as it does in the app.
    port.emit(
      snapshot(direction: CallDirection.incoming, phase: CallPhase.ringing),
    );
    // The call host keeps the call state alive and opens the screen once a
    // call exists; do the same.
    final container = ProviderScope.containerOf(
      tester.element(find.text('open')),
    );
    final sub = container.listen(callScreenStateProvider, (_, _) {});
    addTearDown(sub.close);
    // The call host watches the effects for as long as the app runs.
    final effects = container.listen(callEffectsProvider, (_, _) {});
    addTearDown(effects.close);
    await tester.pump();
    await tester.pump();
    expect(container.read(callScreenStateProvider), isNotNull);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The status line, by what a screen reader announces.
  Finder status(String words) => find.bySemanticsLabel(words);

  Future<void> emit(WidgetTester tester, CallSnapshot? call) async {
    port.emit(call);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('an incoming call shows who, and Answer and Decline', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('+8801711000001'), findsOneWidget);
    expect(status('Incoming voice call'), findsOneWidget);
    expect(find.text('ORBIT VOICE CALL'), findsOneWidget);
    expect(find.text('END-TO-END ENCRYPTED'), findsOneWidget);
    expect(find.bySemanticsLabel('Picture of Ada Lovelace'), findsOneWidget);
    expect(find.byTooltip('Answer call'), findsOneWidget);
    expect(find.byTooltip('Decline call'), findsOneWidget);
  });

  testWidgets('Answer asks for the microphone, then accepts', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('Answer call'));
    await tester.pumpAndSettle();

    expect(permissions.asked, [false]);
    expect(port.calls, ['accept']);
  });

  testWidgets('Decline declines', (tester) async {
    await open(tester);

    await tester.tap(find.byTooltip('Decline call'));
    await tester.pumpAndSettle();

    expect(port.calls, ['decline']);
  });

  testWidgets('a refused microphone keeps ringing and says what to do', (
    tester,
  ) async {
    await open(tester);
    permissions.result = CallPermissionResult.microphoneDenied;

    await tester.tap(find.byTooltip('Answer call'));
    await tester.pumpAndSettle();

    expect(port.calls, isEmpty);
    expect(find.textContaining('needs the microphone'), findsOneWidget);
    expect(find.byTooltip('Answer call'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('needs the microphone'), findsNothing);
  });

  testWidgets('an answer that fails shows the reason', (tester) async {
    await open(tester);
    port.failWith = const CallFailedException(CallFailure.noCall);

    await tester.tap(find.byTooltip('Answer call'));
    await tester.pumpAndSettle();

    expect(find.text('There is no call to answer any more.'), findsOneWidget);
  });

  testWidgets('an incoming video call says so and answers with video', (
    tester,
  ) async {
    await open(tester);
    await emit(
      tester,
      snapshot(
        direction: CallDirection.incoming,
        phase: CallPhase.ringing,
        video: true,
      ),
    );

    expect(status('Incoming video call'), findsOneWidget);
    await tester.tap(find.byTooltip('Answer video call'));
    await tester.pumpAndSettle();
    expect(permissions.asked, [true]);
  });

  testWidgets('dialing shows Calling… then Ringing…, and End cancels', (
    tester,
  ) async {
    await open(tester);
    await emit(tester, snapshot());
    expect(status('Calling…'), findsOneWidget);
    await emit(tester, snapshot(phase: CallPhase.ringing));
    expect(status('Ringing…'), findsOneWidget);

    await tester.tap(find.byTooltip('End call'));
    await tester.pumpAndSettle();
    expect(port.calls, ['hangUp']);
  });

  group('a live voice call', () {
    final answered = DateTime.utc(2026, 10, 3, 9, 5);

    Future<void> live(
      WidgetTester tester, {
      bool muted = false,
      Set<CallAudioRoute>? routes,
    }) async {
      await open(tester, routes: routes);
      await emit(
        tester,
        snapshot(phase: CallPhase.active, answeredAt: answered, muted: muted),
      );
    }

    testWidgets('runs a timer from the moment it connected', (tester) async {
      await live(tester);
      expect(find.text('05:00'), findsOneWidget);
      expect(status('Call duration 05:00'), findsOneWidget);

      wall = DateTime.utc(2026, 10, 3, 9, 11, 5);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('06:05'), findsOneWidget);
      wall = DateTime.utc(2026, 10, 3, 9, 10);
    });

    testWidgets('mute toggles and says what it will do next', (tester) async {
      await live(tester);
      expect(find.byTooltip('Mute microphone'), findsOneWidget);

      await tester.tap(find.byTooltip('Mute microphone'));
      await tester.pumpAndSettle();
      expect(port.calls, ['mute:true']);

      await emit(
        tester,
        snapshot(phase: CallPhase.active, answeredAt: answered, muted: true),
      );
      expect(find.byTooltip('Unmute microphone'), findsOneWidget);
    });

    testWidgets('video is honestly unavailable on a voice call', (
      tester,
    ) async {
      await live(tester);
      expect(
        find.byTooltip('Video is not available on a voice call'),
        findsOneWidget,
      );
    });

    testWidgets('with two outputs the speaker control toggles', (tester) async {
      await live(tester);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byTooltip('Turn speaker on'));
      await tester.pumpAndSettle();

      expect(audio.selected.last, CallAudioRoute.speaker);
      expect(find.byTooltip('Turn speaker off'), findsOneWidget);
    });

    testWidgets('with a headset there is a menu of outputs', (tester) async {
      await live(
        tester,
        routes: {
          CallAudioRoute.earpiece,
          CallAudioRoute.speaker,
          CallAudioRoute.bluetooth,
        },
      );
      await tester.pump(const Duration(milliseconds: 50));

      // A connected Bluetooth device wins over the earpiece.
      await tester.tap(find.byTooltip('Audio output: Bluetooth'));
      await tester.pumpAndSettle();
      expect(find.text('Audio output'), findsOneWidget);
      await tester.tap(find.text('Speaker').last);
      await tester.pumpAndSettle();

      expect(audio.selected.last, CallAudioRoute.speaker);
    });

    testWidgets('End hangs up', (tester) async {
      await live(tester);
      await tester.tap(find.byTooltip('End call'));
      await tester.pumpAndSettle();
      expect(port.calls, ['hangUp']);
    });

    testWidgets('a weak connection shows a chip, a dropped one Reconnecting…', (
      tester,
    ) async {
      await live(tester);
      hub.publish(
        const CallMediaInfo(weak: true, state: CallMediaState.connected),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Poor connection'), findsOneWidget);

      hub.publish(const CallMediaInfo(state: CallMediaState.disconnected));
      await tester.pump(const Duration(milliseconds: 20));
      expect(status('Reconnecting…'), findsOneWidget);
    });
  });

  group('a live video call', () {
    final answered = DateTime.utc(2026, 10, 3, 9, 5);

    Future<void> live(WidgetTester tester, {bool cameraOn = true}) async {
      await open(tester);
      hub.publish(
        CallMediaInfo(
          local: FakeSurface('local'),
          remote: FakeSurface('remote'),
          state: CallMediaState.connected,
        ),
      );
      await emit(
        tester,
        snapshot(
          phase: CallPhase.active,
          answeredAt: answered,
          video: true,
          cameraOn: cameraOn,
        ),
      );
    }

    group('sharing the screen', () {
      // The Share button is for the phones and Windows. The override must be
      // gone before the test ends, or the framework refuses the test.
      void onAndroid(
        String name,
        Future<void> Function(WidgetTester tester) body,
      ) => testWidgets(name, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      onAndroid('Share asks the engine, and Stop ends it', (tester) async {
        await live(tester);
        await tester.tap(find.byTooltip('Share your screen'));
        await tester.pumpAndSettle();
        expect(port.calls, contains('screen:true'));

        await emit(
          tester,
          snapshot(
            phase: CallPhase.active,
            answeredAt: answered,
            video: true,
            cameraOn: true,
            screenSharing: true,
          ),
        );
        expect(find.text('You are sharing your screen'), findsOneWidget);
        await tester.tap(find.text('Stop'));
        await tester.pumpAndSettle();
        expect(port.calls, contains('screen:false'));
      });

      onAndroid('a refused capture says so in a sentence', (tester) async {
        await live(tester);
        port.screenShareWorks = false;
        await tester.tap(find.byTooltip('Share your screen'));
        await tester.pumpAndSettle();
        expect(find.textContaining('could not be shared'), findsOneWidget);
      });

      onAndroid('their shared screen is drawn whole, not cropped', (
        tester,
      ) async {
        final remote = FakeSurface('remote');
        await open(tester);
        hub.publish(
          CallMediaInfo(
            local: FakeSurface('local'),
            remote: remote,
            state: CallMediaState.connected,
          ),
        );
        await emit(
          tester,
          snapshot(
            phase: CallPhase.active,
            answeredAt: answered,
            video: true,
            cameraOn: true,
          ),
        );
        expect(remote.lastFit, isFalse);
        await emit(
          tester,
          snapshot(
            phase: CallPhase.active,
            answeredAt: answered,
            video: true,
            cameraOn: true,
            peerScreenSharing: true,
          ),
        );
        expect(remote.lastFit, isTrue);
        expect(
          find.text('Ada Lovelace is sharing their screen'),
          findsOneWidget,
        );
      });

      onAndroid('a voice call has no Share', (tester) async {
        await open(tester);
        await emit(
          tester,
          snapshot(phase: CallPhase.active, answeredAt: answered),
        );
        expect(find.byTooltip('Share your screen'), findsNothing);
      });
    });

    testWidgets('shows the other person full screen and you in a corner', (
      tester,
    ) async {
      await live(tester);

      expect(find.text('video:remote'), findsOneWidget);
      expect(find.textContaining('video:local'), findsOneWidget);
      expect(find.byTooltip('Flip camera'), findsOneWidget);
    });

    testWidgets('tapping your preview swaps the two', (tester) async {
      final semantics = tester.ensureSemantics();
      await live(tester);

      await tester.tap(
        find.bySemanticsLabel(RegExp('Show your camera full screen')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('video:local'), findsOneWidget);
      expect(find.text('video:remote'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Show Ada Lovelace full screen')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('your preview can be dragged, but not off the screen', (
      tester,
    ) async {
      await live(tester);
      final preview = find.textContaining('video:local');
      final before = tester.getCenter(preview);

      await tester.drag(preview, const Offset(-150, 300));
      await tester.pumpAndSettle();
      final moved = tester.getCenter(preview);
      expect(moved.dx, lessThan(before.dx - 100));
      expect(moved.dy, greaterThan(before.dy + 200));

      await tester.drag(preview, const Offset(-5000, 5000));
      await tester.pumpAndSettle();
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final parked = tester.getCenter(preview);
      expect(parked.dx, inInclusiveRange(0, screen.width));
      expect(parked.dy, inInclusiveRange(0, screen.height));
    });

    testWidgets('the camera button turns the camera off', (tester) async {
      await live(tester);

      await tester.tap(find.byTooltip('Turn camera off'));
      await tester.pumpAndSettle();

      expect(port.calls, ['camera:false']);
    });

    testWidgets('with the camera off there is no flip and no preview', (
      tester,
    ) async {
      await live(tester, cameraOn: false);

      expect(find.byTooltip('Turn camera on'), findsOneWidget);
      expect(find.textContaining('video:local'), findsNothing);
    });

    testWidgets('until the first frame the other person is an avatar', (
      tester,
    ) async {
      await open(tester);
      final remote = FakeSurface('remote', frames: false);
      hub.publish(
        CallMediaInfo(remote: remote, state: CallMediaState.connected),
      );
      await emit(
        tester,
        snapshot(
          phase: CallPhase.active,
          answeredAt: answered,
          video: true,
          cameraOn: true,
        ),
      );

      expect(find.text('video:remote'), findsNothing);
      expect(find.text('AL'), findsWidgets);

      remote.frames = true;
      await tester.pump();
      expect(find.text('video:remote'), findsOneWidget);
    });
  });

  group('how a call ended', () {
    final answered = DateTime.utc(2026, 10, 3, 9, 5);

    Future<void> ended(
      WidgetTester tester,
      CallEnd end, {
      CallDirection direction = CallDirection.outgoing,
      DateTime? answeredAt,
    }) async {
      await open(tester);
      await emit(
        tester,
        snapshot(
          direction: direction,
          phase: CallPhase.ended,
          end: end,
          answeredAt: answeredAt,
          endedAt: answeredAt?.add(const Duration(minutes: 4, seconds: 12)),
        ),
      );
    }

    testWidgets('answered on another device', (tester) async {
      await ended(
        tester,
        CallEnd.answeredElsewhere,
        direction: CallDirection.incoming,
      );
      expect(status('Answered on another device'), findsOneWidget);
    });

    testWidgets('declined on another device', (tester) async {
      await ended(
        tester,
        CallEnd.declinedElsewhere,
        direction: CallDirection.incoming,
      );
      expect(status('Declined on another device'), findsOneWidget);
    });

    testWidgets('no answer, busy, declined by them, failed', (tester) async {
      await ended(tester, CallEnd.unanswered);
      expect(status('No answer'), findsOneWidget);
    });

    testWidgets('busy', (tester) async {
      await ended(tester, CallEnd.busy);
      expect(status('Busy: on another call'), findsOneWidget);
      expect(find.text('They are in another call right now.'), findsOneWidget);
    });

    testWidgets('declined by the other person', (tester) async {
      await ended(tester, CallEnd.declinedByPeer);
      expect(status('Call declined'), findsOneWidget);
    });

    testWidgets('a failure explains itself', (tester) async {
      await ended(tester, CallEnd.failed);
      expect(status('Call failed'), findsOneWidget);
      expect(find.textContaining('could not connect'), findsOneWidget);
    });

    testWidgets('an answered call keeps its talk time', (tester) async {
      await ended(tester, CallEnd.remoteHungUp, answeredAt: answered);
      expect(status('Call ended'), findsOneWidget);
      expect(find.text('04:12'), findsOneWidget);
    });

    testWidgets('the controls are disabled, and the screen closes by itself', (
      tester,
    ) async {
      await ended(tester, CallEnd.hungUp, answeredAt: answered);

      await tester.tap(find.byTooltip('Mute microphone'), warnIfMissed: false);
      expect(port.calls, isEmpty);

      port.emit(null);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(status('Call ended'), findsNothing);
    });
  });

  testWidgets('the back gesture does not leave a live call', (tester) async {
    await open(tester);
    await emit(
      tester,
      snapshot(
        phase: CallPhase.active,
        answeredAt: DateTime.utc(2026, 10, 3, 9, 5),
      ),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byTooltip('End call'), findsOneWidget);
  });

  group('accessibility', () {
    testWidgets('incoming and live calls meet the guidelines at 2x text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester.takeException(), isNull);

      await emit(
        tester,
        snapshot(
          phase: CallPhase.active,
          answeredAt: DateTime.utc(2026, 10, 3, 9, 5),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester.takeException(), isNull);
    });
  });
}
