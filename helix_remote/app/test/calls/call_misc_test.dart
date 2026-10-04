import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/core/people/name_lookup.dart';
import 'package:helix_remote/features/calls/application/call_controller.dart';
import 'package:helix_remote/features/calls/application/call_effects.dart';
import 'package:helix_remote/features/calls/presentation/call_detail_screen.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import '../support/call_support.dart';
import '../support/harness.dart';

/// The call-detail page, and the notification buttons: Answer or Decline
/// pressed before the app knew of the call is applied when it rings.
void main() {
  group('call notifications', () {
    test('the payload round-trips and others are ignored', () {
      expect(
        CallNotifications.callIdOf(CallNotifications.payloadFor('abc')),
        'abc',
      );
      expect(CallNotifications.callIdOf('chat=1'), isNull);
      expect(CallNotifications.callIdOf(null), isNull);
      expect(CallNotifications.callIdOf('call_id='), isNull);
    });

    test('the notification id is stable per call', () {
      expect(CallNotifications.idFor('x'), CallNotifications.idFor('x'));
      expect(CallNotifications.idFor('x'), isNonNegative);
    });

    group('a button pressed before the call rings', () {
      late FakeCallsPort port;
      late StreamController<CallNotificationResponse> presses;
      late ProviderContainer container;
      var wall = DateTime.utc(2026, 10, 3, 9);

      setUp(() {
        wall = DateTime.utc(2026, 10, 3, 9);
        port = FakeCallsPort();
        presses = StreamController<CallNotificationResponse>.broadcast();
        container = ProviderContainer(
          overrides: callOverrides(
            port: port,
            clock: () => wall,
            responses: presses.stream,
          ),
        );
        container.listen(callScreenStateProvider, (_, _) {});
        container.read(callNotificationHandlerProvider);
      });

      tearDown(() async {
        container.dispose();
        await presses.close();
      });

      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 20));

      CallSnapshot ringing() =>
          snapshot(direction: CallDirection.incoming, phase: CallPhase.ringing);

      test('Answer is applied when that call rings', () async {
        presses.add(
          const CallNotificationResponse(
            'call-1',
            CallNotificationAction.accept,
          ),
        );
        await settle();
        expect(port.calls, isEmpty);

        port.emit(ringing());
        await settle();

        expect(port.calls, ['accept']);
      });

      test('Decline is applied when that call rings', () async {
        presses.add(
          const CallNotificationResponse(
            'call-1',
            CallNotificationAction.decline,
          ),
        );
        port.emit(ringing());
        await settle();

        expect(port.calls, ['decline']);
      });

      test('a press for another call is not applied to this one', () async {
        presses.add(
          const CallNotificationResponse(
            'other',
            CallNotificationAction.accept,
          ),
        );
        port.emit(ringing());
        await settle();

        expect(port.calls, isEmpty);
      });

      test('a press that is too old is dropped', () async {
        presses.add(
          const CallNotificationResponse(
            'call-1',
            CallNotificationAction.accept,
          ),
        );
        await settle();
        wall = wall.add(const Duration(minutes: 5));

        port.emit(ringing());
        await settle();

        expect(port.calls, isEmpty);
      });

      test('tapping the body just opens the app', () async {
        presses.add(
          const CallNotificationResponse('call-1', CallNotificationAction.open),
        );
        port.emit(ringing());
        await settle();

        expect(port.calls, isEmpty);
      });
    });
  });

  group('call detail', () {
    const names = PeopleNames({
      'peer-1': HelixPersonNames(
        phoneBookName: 'Ada Lovelace',
        number: '+8801711000001',
      ),
    });
    final now = DateTime(2026, 10, 3, 15, 30);

    FakeCallsPort withCalls() => FakeCallsPort()
      ..setLog([
        logRow(
          'c2',
          peer: 'peer-1',
          direction: 'incoming',
          at: DateTime(2026, 10, 3, 14, 5),
        ),
        logRow(
          'c1',
          peer: 'peer-1',
          video: true,
          at: DateTime(2026, 10, 2, 9),
          answeredAfterSeconds: 3,
          talkSeconds: 252,
        ),
        logRow('other', peer: 'peer-2', at: DateTime(2026, 10, 1, 9)),
      ]);

    Future<FakeCallsPort> pump(WidgetTester tester, String id) async {
      final port = withCalls();
      await tester.pumpWidget(
        harness(
          home: CallDetailScreen(callId: id),
          overrides: callOverrides(port: port, names: names, clock: () => now),
        ),
      );
      await tester.pumpAndSettle();
      return port;
    }

    testWidgets('shows the person and every call with them', (tester) async {
      await pump(tester, 'c1');

      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('+8801711000001'), findsOneWidget);
      expect(find.text('Missed voice call'), findsOneWidget);
      expect(find.text('Outgoing video call'), findsOneWidget);
      expect(find.text('04:12'), findsOneWidget);
      // Calls with somebody else are not here.
      expect(find.textContaining('1 Oct'), findsNothing);
    });

    testWidgets('the call buttons place calls', (tester) async {
      final port = await pump(tester, 'c1');

      await tester.tap(find.text('Video call'));
      await tester.pumpAndSettle();

      expect(port.calls, ['start peer-1 video:true']);
    });

    testWidgets('delete removes every call with the person, after asking', (
      tester,
    ) async {
      final port = await pump(tester, 'c1');

      await tester.tap(find.byTooltip('Delete from call history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(port.calls, ['forget c2', 'forget c1']);
    });

    testWidgets('a call that is no longer in the log says so', (tester) async {
      await pump(tester, 'gone');

      expect(find.text('Call not found'), findsOneWidget);
    });

    testWidgets('meets the guidelines', (tester) async {
      await pump(tester, 'c1');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(find.byType(HelixAvatar), findsOneWidget);
    });
  });
}
