import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/calls/application/call_effects.dart';
import 'package:helix_remote/features/calls/application/group_call_state.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote/features/calls/calls_routes.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:orbit_ui/models.dart';

import '../support/call_support.dart';
import '../support/harness.dart';
import '../support/names_support.dart';

/// The full-screen group call: ringing and live, drawn from the room state,
/// with the controls wired to the engine port.
void main() {
  final names = directoryOf(const {
    'peer-1': HelixPersonNames(phoneBookName: 'Ada Lovelace'),
    'peer-2': HelixPersonNames(phoneBookName: 'Bilal Rahman'),
  });
  final answered = DateTime.utc(2026, 10, 3, 9, 5);

  late FakeCallsPort port;
  late FakeGroupCallsPort rooms;
  late FakeCallPermissions permissions;
  late FakeCallPlatform platform;
  late FakeRinger ringer;
  late CallMediaHub hub;

  Future<void> open(WidgetTester tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    port = FakeCallsPort();
    rooms = FakeGroupCallsPort();
    permissions = FakeCallPermissions();
    platform = FakeCallPlatform();
    ringer = FakeRinger();
    hub = CallMediaHub();
    await tester.pumpWidget(
      harness(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => context.push(CallRoutes.group),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        routes: callsRoutes,
        overrides: callOverrides(
          port: port,
          groups: rooms,
          permissions: permissions,
          platform: platform,
          ringer: ringer,
          hub: hub,
          names: names,
          clock: () => DateTime.utc(2026, 10, 3, 9, 10),
          linger: const Duration(milliseconds: 500),
        ),
      ),
    );
    rooms.emit(roomSnapshot());
    final container = ProviderScope.containerOf(
      tester.element(find.text('open')),
    );
    final sub = container.listen(groupCallScreenStateProvider, (_, _) {});
    addTearDown(sub.close);
    // The call host watches the effects for as long as the app runs.
    final effects = container.listen(callEffectsProvider, (_, _) {});
    addTearDown(effects.close);
    await tester.pump();
    await tester.pump();
    expect(container.read(groupCallScreenStateProvider), isNotNull);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> emit(WidgetTester tester, GroupCallSnapshot? room) async {
    rooms.emit(room);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('an invitation shows the group and who, and rings', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Friday crew'), findsOneWidget);
    expect(find.text('Ada Lovelace is calling the group'), findsOneWidget);
    expect(find.byTooltip('Join call'), findsOneWidget);
    expect(find.byTooltip('Decline group call'), findsOneWidget);
    // The same effects as a 1:1 call: it rings, with the group's name.
    expect(ringer.log.single, contains('ring Friday crew'));
  });

  testWidgets('Join asks for the microphone, then joins', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Join call'));
    await tester.pumpAndSettle();
    expect(permissions.asked, [false]);
    expect(rooms.calls, ['accept']);
  });

  testWidgets('a refused microphone keeps it ringing with a sentence', (
    tester,
  ) async {
    await open(tester);
    permissions.result = CallPermissionResult.microphoneDenied;
    await tester.tap(find.byTooltip('Join call'));
    await tester.pumpAndSettle();
    expect(rooms.calls, isEmpty);
    expect(find.textContaining('needs the microphone'), findsOneWidget);
  });

  testWidgets('Decline declines', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Decline group call'));
    await tester.pumpAndSettle();
    expect(rooms.calls, ['decline']);
  });

  group('a live room', () {
    Future<void> live(WidgetTester tester) async {
      await open(tester);
      await emit(
        tester,
        roomSnapshot(
          phase: GroupCallPhase.active,
          answeredAt: answered,
          video: true,
          cameraOn: true,
          people: {
            'peer-1': GroupParticipantState.connected,
            'peer-2': GroupParticipantState.connecting,
          },
        ),
      );
    }

    testWidgets('shows each person, how they are doing, and you', (
      tester,
    ) async {
      await live(tester);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Bilal Rahman · Connecting…'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('their pictures go where they are', (tester) async {
      await open(tester);
      hub
        ..publishGroup(
          'peer-1',
          local: FakeSurface('me'),
          remote: FakeSurface('ada'),
        )
        ..publishGroup('peer-2', remote: FakeSurface('bilal'));
      await emit(
        tester,
        roomSnapshot(
          phase: GroupCallPhase.active,
          answeredAt: answered,
          video: true,
          cameraOn: true,
          people: {
            'peer-1': GroupParticipantState.connected,
            'peer-2': GroupParticipantState.connected,
          },
        ),
      );
      expect(find.text('video:ada'), findsOneWidget);
      expect(find.text('video:bilal'), findsOneWidget);
      expect(find.textContaining('video:me'), findsOneWidget);
    });

    testWidgets('the tray mutes, switches the camera and leaves', (
      tester,
    ) async {
      await live(tester);
      await tester.tap(find.byTooltip('Mute microphone'));
      await tester.tap(find.byTooltip('Turn camera off'));
      await tester.tap(find.byTooltip('End call'));
      await tester.pumpAndSettle();
      expect(rooms.calls, ['muted:true', 'camera:false', 'hangUp']);
    });

    testWidgets('the foreground service runs while it lasts', (tester) async {
      await live(tester);
      expect(
        platform.log.where((l) => l.startsWith('service:start')),
        hasLength(1),
      );
      await emit(
        tester,
        roomSnapshot(
          phase: GroupCallPhase.ended,
          end: GroupCallEnd.everyoneLeft,
          answeredAt: answered,
          endedAt: answered.add(const Duration(minutes: 5)),
        ),
      );
      expect(platform.log, contains('service:stop'));
    });

    testWidgets('an ended room says how, then the screen closes', (
      tester,
    ) async {
      await live(tester);
      await emit(
        tester,
        roomSnapshot(
          phase: GroupCallPhase.ended,
          end: GroupCallEnd.everyoneLeft,
          answeredAt: answered,
          endedAt: answered.add(const Duration(minutes: 5)),
        ),
      );
      expect(find.text('EVERYONE LEFT'), findsOneWidget);
      await emit(tester, null);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });
}
