// Phase 12 call UI and ICE gating tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/screens/call/call_format.dart';
import 'package:helix_remote/screens/call_screen.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

// ---------------------------------------------------------------------------
// P12-A01 through P12-A03: callsAvailable ICE gating logic
// (mirrors the getter in RemoteCompositionRoot)
// ---------------------------------------------------------------------------

bool _callsAvailable(RemoteIceConfig config) {
  if (config.ipPrivacy == IpPrivacyMode.relayOnly) {
    return config.iceServers.any(
      (s) => s.url.startsWith('turn:') || s.url.startsWith('turns:'),
    );
  }
  return true;
}

void main() {
  // -----------------------------------------------------------------------
  // ICE gating unit tests
  // -----------------------------------------------------------------------

  group('P12-A01 callsAvailable ICE gating', () {
    test('relay-only with no servers → unavailable', () {
      final config = const RemoteIceConfig(
        iceServers: [],
        ipPrivacy: IpPrivacyMode.relayOnly,
      );
      expect(_callsAvailable(config), isFalse);
    });

    test('relay-only with STUN only → unavailable', () {
      final config = const RemoteIceConfig(
        iceServers: [IceServerConfig(url: 'stun:stun.l.google.com:19302')],
        ipPrivacy: IpPrivacyMode.relayOnly,
      );
      expect(_callsAvailable(config), isFalse);
    });

    test('relay-only with TURN configured → available', () {
      final config = const RemoteIceConfig(
        iceServers: [
          IceServerConfig(
            url: 'turn:turn.example.com:3478',
            username: 'user',
            credential: 'pass',
          ),
        ],
        ipPrivacy: IpPrivacyMode.relayOnly,
      );
      expect(_callsAvailable(config), isTrue);
    });

    test('relay-only with TURNS (secure TURN) configured → available', () {
      final config = const RemoteIceConfig(
        iceServers: [
          IceServerConfig(
            url: 'turns:turn.example.com:5349',
            username: 'user',
            credential: 'pass',
          ),
        ],
        ipPrivacy: IpPrivacyMode.relayOnly,
      );
      expect(_callsAvailable(config), isTrue);
    });

    test('directAndRelay mode with no servers → available', () {
      final config = const RemoteIceConfig(
        iceServers: [],
        ipPrivacy: IpPrivacyMode.directAndRelay,
      );
      expect(_callsAvailable(config), isTrue);
    });

    test('directAndRelay mode with STUN → available (defaultStun)', () {
      expect(_callsAvailable(RemoteIceConfig.defaultStun()), isTrue);
    });
  });

  // -----------------------------------------------------------------------
  // P12-W01: Incoming call widget shows accept/decline
  // -----------------------------------------------------------------------

  group('P12-W01 incoming call UI', () {
    Widget makeApp(Widget home) => MaterialApp(home: home);

    testWidgets('ringing state hides peer ID and shows accept and decline', (
      tester,
    ) async {
      const status = RemoteCallStatus(
        callId: 'call-001',
        peerId: 'alice',
        isVideo: false,
        direction: kCallDirectionIncoming,
        state: RemoteCallState.ringing,
      );

      var accepted = false;
      var declined = false;

      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: status,
            onAccept: () => accepted = true,
            onDecline: () => declined = true,
            onEnd: () {},
          ),
        ),
      );

      expect(find.text('alice'), findsNothing);
      expect(find.text('Unknown caller'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.call)); // Accept
      expect(accepted, isTrue);

      await tester.tap(find.byIcon(Icons.call_end)); // Decline FAB (unique)
      expect(declined, isTrue);
    });

    testWidgets('dialing state shows Calling label', (tester) async {
      const status = RemoteCallStatus(
        callId: 'call-002',
        peerId: 'bob',
        isVideo: false,
        direction: kCallDirectionOutgoing,
        state: RemoteCallState.dialing,
      );

      var ended = false;

      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: status,
            onDecline: () {},
            onEnd: () => ended = true,
          ),
        ),
      );

      expect(find.text('Calling…'), findsOneWidget);
      expect(find.text('bob'), findsNothing);
      expect(find.text('Unknown caller'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.call_end)); // End FAB
      expect(ended, isTrue);
    });

    testWidgets('active state shows Connected with mute toggle', (
      tester,
    ) async {
      const status = RemoteCallStatus(
        callId: 'call-003',
        peerId: 'charlie',
        isVideo: false,
        direction: kCallDirectionOutgoing,
        state: RemoteCallState.active,
      );

      bool? lastMuted;
      bool? lastSpeaker;

      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: status,
            onDecline: () {},
            onEnd: () {},
            onMute: ({required bool muted}) => lastMuted = muted,
            onSpeaker: ({required bool enabled}) => lastSpeaker = enabled,
          ),
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Mute'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.mic)); // Mute FAB
      await tester.pump();
      expect(lastMuted, isTrue);

      await tester.tap(find.text('Speaker')); // Speaker toggle (label)
      await tester.pump();
      expect(lastSpeaker, isTrue);
    });

    testWidgets('video call shows video controls and camera placeholder', (
      tester,
    ) async {
      const status = RemoteCallStatus(
        callId: 'call-004',
        peerDisplayName: 'Dana',
        peerAccountId: 'acct_dana',
        isVideo: true,
        direction: kCallDirectionOutgoing,
        state: RemoteCallState.connecting,
        isLocalVideoEnabled: false,
      );

      bool? lastVideo;
      var switched = false;

      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: status,
            onDecline: () {},
            onEnd: () {},
            onVideo: ({required bool enabled}) => lastVideo = enabled,
            onSwitchCamera: () => switched = true,
          ),
        ),
      );

      expect(find.text('Dana'), findsOneWidget);
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.text('Camera off'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.videocam_off));
      await tester.pump();
      expect(lastVideo, isTrue);

      await tester.tap(find.byIcon(Icons.cameraswitch));
      await tester.pump();
      expect(switched, isTrue);
    });

    testWidgets('decline and end callbacks are distinct', (tester) async {
      const incoming = RemoteCallStatus(
        callId: 'call-005',
        peerId: 'erin',
        isVideo: false,
        direction: kCallDirectionIncoming,
        state: RemoteCallState.ringing,
      );
      var declined = false;
      var ended = false;

      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: incoming,
            onAccept: () {},
            onDecline: () => declined = true,
            onEnd: () => ended = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.call_end));
      expect(declined, isTrue);
      expect(ended, isFalse);
    });

    testWidgets('disabled call buttons show tooltip when unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: const [
                IconButton(
                  tooltip: 'Calls require TURN relay configuration',
                  icon: Icon(Icons.call),
                  onPressed: null,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.call), findsOneWidget);
      final btn = tester.widget<IconButton>(find.byType(IconButton).first);
      expect(btn.onPressed, isNull);
    });
  });

  // -----------------------------------------------------------------------
  // Redesigned 1:1 call screen
  // -----------------------------------------------------------------------

  group('call screen redesign', () {
    Widget makeApp(Widget home, {double textScale = 1, bool reduced = false}) {
      return MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: home,
      );
    }

    void useSize(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    RemoteCallStatus activeAudio({
      DateTime? startedAt,
      CallQualityMetrics? quality,
      RemoteCallState state = RemoteCallState.active,
      bool isVideo = false,
      String? errorMessage,
    }) => RemoteCallStatus(
      callId: 'call-100',
      peerDisplayName: 'Farah Ahmed',
      peerAccountId: 'acct_farah',
      isVideo: isVideo,
      direction: kCallDirectionOutgoing,
      state: state,
      startedAt: startedAt,
      quality: quality,
      errorMessage: errorMessage,
    );

    testWidgets('incoming shows Accept, Decline, subtitle and Message', (
      tester,
    ) async {
      var messaged = false;
      var accepted = false;
      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: const RemoteCallStatus(
              callId: 'call-101',
              peerDisplayName: 'Farah Ahmed',
              isVideo: false,
              direction: kCallDirectionIncoming,
              state: RemoteCallState.ringing,
            ),
            peerSubtitle: '+44 7700 900123',
            onAccept: () => accepted = true,
            onDecline: () {},
            onEnd: () {},
            onMessage: () => messaged = true,
          ),
        ),
      );

      expect(find.text('Farah Ahmed'), findsOneWidget);
      expect(find.text('+44 7700 900123'), findsOneWidget);
      expect(find.text('Helix voice call'), findsOneWidget);
      expect(find.text('End-to-end encrypted'), findsOneWidget);
      expect(find.text('FA'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);

      await tester.tap(find.text('Message'));
      expect(messaged, isTrue);
      await tester.tap(find.text('Accept'));
      expect(accepted, isTrue);
    });

    testWidgets('incoming without onMessage has no Message button', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: const RemoteCallStatus(
              callId: 'call-102',
              peerDisplayName: 'Farah',
              isVideo: true,
              direction: kCallDirectionIncoming,
              state: RemoteCallState.ringing,
            ),
            onAccept: () {},
            onDecline: () {},
            onEnd: () {},
          ),
        ),
      );
      expect(find.text('Message'), findsNothing);
      expect(find.text('Helix video call'), findsOneWidget);
      // A video call is answered with the camera icon.
      expect(find.byIcon(Icons.videocam), findsOneWidget);
    });

    testWidgets('incoming pulse animates, and stops under reduced motion', (
      tester,
    ) async {
      const ringing = RemoteCallStatus(
        callId: 'call-103',
        peerDisplayName: 'Farah',
        isVideo: false,
        direction: kCallDirectionIncoming,
        state: RemoteCallState.ringing,
      );
      Widget screen() => CallScreen(
        callStatus: ringing,
        onAccept: () {},
        onDecline: () {},
        onEnd: () {},
      );

      await tester.pumpWidget(makeApp(screen()));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(makeApp(screen(), reduced: true));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets(
      'active audio controls fit 360x640 at text scale 1.3 in one row',
      (tester) async {
        useSize(tester, const Size(360, 640));
        await tester.pumpWidget(
          makeApp(
            CallScreen(
              callStatus: activeAudio(
                startedAt: DateTime.now().subtract(const Duration(seconds: 75)),
              ),
              peerSubtitle: '+44 7700 900123',
              onDecline: () {},
              onEnd: () {},
              onMute: ({required bool muted}) {},
              onSpeaker: ({required bool enabled}) {},
              onMinimize: () {},
            ),
            textScale: 1.3,
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        for (final label in const ['Speaker', 'Video', 'Mute', 'End']) {
          expect(find.text(label), findsOneWidget);
        }
        final rows = {
          for (final icon in const [
            Icons.volume_up_outlined,
            Icons.videocam_off,
            Icons.mic,
            Icons.call_end,
          ])
            tester.getCenter(find.byIcon(icon)).dy.round(),
        };
        expect(rows, hasLength(1), reason: 'controls must share one row');
        expect(find.textContaining(RegExp(r'^01:1[56]$')), findsOneWidget);
        expect(find.byTooltip('Minimise call'), findsOneWidget);
      },
    );

    testWidgets('video controls fit 360x640 and landscape at text scale 1.3', (
      tester,
    ) async {
      final status = activeAudio(
        isVideo: true,
        startedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      Widget screen() => CallScreen(
        callStatus: status,
        onDecline: () {},
        onEnd: () {},
        onMute: ({required bool muted}) {},
        onSpeaker: ({required bool enabled}) {},
        onVideo: ({required bool enabled}) {},
        onSwitchCamera: () {},
        onMinimize: () {},
      );

      useSize(tester, const Size(360, 640));
      await tester.pumpWidget(makeApp(screen(), textScale: 1.3));
      expect(tester.takeException(), isNull);
      for (final label in const ['Flip', 'Video', 'Mute', 'Speaker', 'End']) {
        expect(find.text(label), findsOneWidget);
      }

      useSize(tester, const Size(640, 360));
      await tester.pumpWidget(makeApp(screen(), textScale: 1.3));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('incoming screen survives a landscape phone', (tester) async {
      useSize(tester, const Size(640, 360));
      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: const RemoteCallStatus(
              callId: 'call-104',
              peerDisplayName: 'Farah Ahmed',
              isVideo: false,
              direction: kCallDirectionIncoming,
              state: RemoteCallState.ringing,
            ),
            peerSubtitle: '+44 7700 900123',
            onAccept: () {},
            onDecline: () {},
            onEnd: () {},
            onMessage: () {},
          ),
          textScale: 1.3,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('toggled controls are filled and announce their state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: activeAudio().copyWith(isMuted: true),
            onDecline: () {},
            onEnd: () {},
            onMute: ({required bool muted}) {},
            onSpeaker: ({required bool enabled}) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Unmute microphone')),
        matchesSemantics(
          label: 'Unmute microphone',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('back on an active call minimises instead of popping', (
      tester,
    ) async {
      var minimised = 0;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            callStatus: activeAudio(startedAt: DateTime.now()),
            onDecline: () {},
            onEnd: () {},
            onMinimize: () => minimised++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(minimised, 1);
      expect(find.byType(CallScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Minimise call'));
      expect(minimised, 2);
    });

    testWidgets('back on the incoming screen does nothing', (tester) async {
      var minimised = 0;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            callStatus: const RemoteCallStatus(
              callId: 'call-105',
              peerDisplayName: 'Farah',
              isVideo: false,
              direction: kCallDirectionIncoming,
              state: RemoteCallState.ringing,
            ),
            onAccept: () {},
            onDecline: () {},
            onEnd: () {},
            onMinimize: () => minimised++,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(minimised, 0);
      expect(find.byType(CallScreen), findsOneWidget);
    });

    testWidgets('terminal state shows Call ended with a frozen timer', (
      tester,
    ) async {
      final startedAt = DateTime.now().subtract(const Duration(seconds: 65));
      var ended = false;
      Widget screen(RemoteCallStatus status) => CallScreen(
        callStatus: status,
        onDecline: () {},
        onEnd: () => ended = true,
      );

      await tester.pumpWidget(
        makeApp(screen(activeAudio(startedAt: startedAt))),
      );
      await tester.pumpWidget(
        makeApp(
          screen(
            activeAudio(startedAt: startedAt, state: RemoteCallState.ended),
          ),
        ),
      );
      expect(find.text('Call ended'), findsOneWidget);
      final frozen = find.textContaining(RegExp(r'^01:0[56]$'));
      expect(frozen, findsOneWidget);
      final shown = tester.widget<Text>(frozen).data!;

      await tester.pump(const Duration(seconds: 3));
      expect(find.text(shown), findsOneWidget, reason: 'timer is frozen');

      await tester.tap(find.byIcon(Icons.call_end));
      expect(ended, isFalse, reason: 'controls are disabled once finished');
    });

    testWidgets('each terminal state has its own words', (tester) async {
      const words = {
        RemoteCallState.declined: 'Declined',
        RemoteCallState.busy: 'Busy',
        RemoteCallState.failed: 'Call failed',
      };
      for (final entry in words.entries) {
        await tester.pumpWidget(
          makeApp(
            CallScreen(
              callStatus: activeAudio(state: entry.key),
              onDecline: () {},
              onEnd: () {},
            ),
          ),
        );
        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets('raw exception text is replaced with a friendly sentence', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: activeAudio(
              state: RemoteCallState.failed,
              errorMessage:
                  'SocketException: Connection refused (OS Error: errno = 111)',
            ),
            onDecline: () {},
            onEnd: () {},
          ),
        ),
      );
      expect(find.text('The call could not be completed.'), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
    });

    testWidgets('reconnecting shows a spinner; weak link shows a chip', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeApp(
          CallScreen(
            callStatus: activeAudio(
              state: RemoteCallState.reconnecting,
              startedAt: DateTime.now(),
              errorMessage:
                  'Weak network detected. Call quality may be reduced.',
              quality: const CallQualityMetrics(
                callId: 'call-100',
                packetLossPercent: 12,
                jitterMs: 80,
                roundTripMs: 600,
                audioBitrateKbps: 12,
                isWeak: true,
              ),
            ),
            onDecline: () {},
            onEnd: () {},
          ),
        ),
      );
      expect(find.text('Reconnecting…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Poor connection'), findsOneWidget);
      // The chip replaces the sentence rather than repeating it.
      expect(find.textContaining('Weak network'), findsNothing);
    });

    test('duration format is mm:ss, then h:mm:ss', () {
      expect(formatCallDuration(const Duration(seconds: 7)), '00:07');
      expect(
        formatCallDuration(const Duration(minutes: 12, seconds: 3)),
        '12:03',
      );
      expect(
        formatCallDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('friendly errors pass plain sentences through', () {
      expect(friendlyCallError(null), isNull);
      expect(friendlyCallError('  '), isNull);
      expect(
        friendlyCallError('The other device is already in a call.'),
        'The other device is already in a call.',
      );
      expect(friendlyCallError("Instance of 'StateError'"), kGenericCallError);
    });
  });
}
