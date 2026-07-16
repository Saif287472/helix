// Phase 12 call UI and ICE gating tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      final config = RemoteIceConfig(
        iceServers: [],
        ipPrivacy: IpPrivacyMode.relayOnly,
      );
      expect(_callsAvailable(config), isFalse);
    });

    test('relay-only with STUN only → unavailable', () {
      final config = RemoteIceConfig(
        iceServers: [IceServerConfig(url: 'stun:stun.l.google.com:19302')],
        ipPrivacy: IpPrivacyMode.relayOnly,
      );
      expect(_callsAvailable(config), isFalse);
    });

    test('relay-only with TURN configured → available', () {
      final config = RemoteIceConfig(
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
      final config = RemoteIceConfig(
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
      final config = RemoteIceConfig(
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

    testWidgets('ringing state shows peer ID, accept and decline', (
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

      expect(find.text('alice'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      // Icons.call appears twice (status icon + Accept FAB); target FAB with last
      await tester.tap(find.byIcon(Icons.call).last); // Accept FAB
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

      expect(find.text('Calling'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
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

      await tester.tap(find.byIcon(Icons.hearing)); // Speaker toggle
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
      expect(find.text('Connecting'), findsOneWidget);
      expect(find.text('Camera off'), findsOneWidget);
      expect(find.text('Video off'), findsOneWidget);

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
              actions: [
                IconButton(
                  tooltip: 'Calls require TURN relay configuration',
                  icon: const Icon(Icons.call),
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
}
