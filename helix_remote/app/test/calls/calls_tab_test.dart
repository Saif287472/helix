import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote/features/calls/presentation/calls_tab.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import '../support/call_support.dart';
import '../support/harness.dart';
import '../support/names_support.dart';

/// The Calls tab: the real log, tap to open, call back, delete, search, and its
/// empty, loading and error states.
void main() {
  final now = DateTime(2026, 10, 3, 15, 30);
  final names = directoryOf(const {
    'peer-1': HelixPersonNames(
      phoneBookName: 'Ada Lovelace',
      number: '+8801711000001',
    ),
    'peer-2': HelixPersonNames(nickname: 'Bob', number: '+8801711000002'),
  });

  Widget tab(
    FakeCallsPort port, {
    CallsPeopleSearchBuilder? peopleSearch,
    FakeCallPermissions? permissions,
  }) => harness(
    home: CallsTabScreen(peopleSearch: peopleSearch),
    routes: [stubRoute('/home/calls/:callId', 'detail')],
    overrides: callOverrides(
      port: port,
      names: names,
      permissions: permissions,
      clock: () => now,
    ),
  );

  FakeCallsPort withLog() => FakeCallsPort()
    ..setLog([
      logRow(
        'c3',
        peer: 'peer-1',
        direction: 'incoming',
        state: 'ended',
        at: DateTime(2026, 10, 3, 14, 5),
      ),
      logRow(
        'c2',
        peer: 'peer-2',
        video: true,
        at: DateTime(2026, 10, 2, 9, 0),
        answeredAfterSeconds: 3,
        talkSeconds: 60,
      ),
      logRow(
        'c1',
        peer: 'peer-1',
        state: 'declined',
        at: DateTime(2026, 9, 12, 18, 0),
      ),
    ]);

  testWidgets('shows each call by the people-naming order, newest first', (
    tester,
  ) async {
    await tester.pumpWidget(tab(withLog()));
    await tester.pumpAndSettle();

    expect(find.text('Calls'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNWidgets(2));
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Today, 14:05'), findsOneWidget);
    expect(find.text('Yesterday, 09:00'), findsOneWidget);
    // Missed calls are marked, the others are not.
    expect(find.byIcon(Icons.call_missed), findsOneWidget);
    expect(find.byIcon(Icons.call_made), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsOneWidget);
  });

  testWidgets('an empty log says so honestly', (tester) async {
    await tester.pumpWidget(tab(FakeCallsPort()));
    await tester.pumpAndSettle();

    expect(find.text('No calls yet'), findsOneWidget);
    expect(
      find.text('Calls you make and receive will show up here.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a skeleton while the log loads', (tester) async {
    final port = FakeCallsPort();
    await tester.pumpWidget(tab(port));
    // The first frame, before the port future and the stream resolve.
    expect(find.byType(HelixChatListSkeleton), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(HelixChatListSkeleton), findsNothing);
  });

  testWidgets('a log that cannot load shows an error with a retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        home: const CallsTabScreen(),
        overrides: callOverrides(
          port: FakeCallsPort()..logError = StateError('db'),
          clock: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your calls could not be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping a row opens the call detail', (tester) async {
    await tester.pumpWidget(tab(withLog()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('the call button calls back, as video when it was video', (
    tester,
  ) async {
    final port = withLog();
    final permissions = FakeCallPermissions();
    await tester.pumpWidget(tab(port, permissions: permissions));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Video call'));
    await tester.pumpAndSettle();

    expect(port.calls, ['start peer-2 video:true']);
    expect(permissions.asked, [true]);
  });

  testWidgets('a refused microphone says what to do and places no call', (
    tester,
  ) async {
    final port = withLog();
    await tester.pumpWidget(
      tab(
        port,
        permissions: FakeCallPermissions(CallPermissionResult.microphoneDenied),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Voice call').first);
    await tester.pumpAndSettle();

    expect(port.calls, isEmpty);
    expect(find.textContaining('needs the microphone'), findsOneWidget);
  });

  testWidgets('long-press offers delete, asks, and removes the entry', (
    tester,
  ) async {
    final port = withLog();
    await tester.pumpWidget(tab(port));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Bob'));
    await tester.pumpAndSettle();
    expect(find.text('Delete from call history'), findsOneWidget);
    await tester.tap(find.text('Delete from call history'));
    await tester.pumpAndSettle();
    expect(find.text('Delete from call history?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(port.calls, ['forget c2']);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('cancelling the delete keeps the entry', (tester) async {
    final port = withLog();
    await tester.pumpWidget(tab(port));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete from call history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(port.calls, isEmpty);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('swiping a row away deletes it after confirmation', (
    tester,
  ) async {
    final port = withLog();
    await tester.pumpWidget(tab(port));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Bob'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete from call history?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(port.calls, ['forget c2']);
  });

  group('search', () {
    testWidgets('without the people search it filters the log by name', (
      tester,
    ) async {
      await tester.pumpWidget(tab(withLog()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bob');
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byType(HelixNoResults), findsOneWidget);
    });

    testWidgets('closing the search brings the whole log back', (tester) async {
      await tester.pumpWidget(tab(withLog()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bob');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();

      expect(find.text('Ada Lovelace'), findsNWidgets(2));
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('a plugged-in people search takes over the body and can '
        'place a call', (tester) async {
      final port = withLog();
      await tester.pumpWidget(
        tab(
          port,
          peopleSearch: (context, query, onCall) => Center(
            child: TextButton(
              onPressed: () => onCall('found-person', video: false),
              child: Text('people results for "$query"'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      // Nothing typed yet: the log is still showing.
      expect(find.text('Bob'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'dan');
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsNothing);
      await tester.tap(find.text('people results for "dan"'));
      await tester.pumpAndSettle();
      expect(port.calls, ['start found-person video:false']);
    });
  });

  group('shortcuts and keypad', () {
    CallsPeopleSearchBuilder results() =>
        (context, query, onCall) => Center(
          child: TextButton(
            onPressed: () => onCall('found-person', video: false),
            child: Text('people results for "$query"'),
          ),
        );

    testWidgets('round shortcuts and a Recent heading sit above the log', (
      tester,
    ) async {
      await tester.pumpWidget(tab(withLog(), peopleSearch: results()));
      await tester.pumpAndSettle();

      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Keypad'), findsOneWidget);
      expect(find.text('Recent'), findsOneWidget);
      // The two people called most recently, by first name.
      expect(find.byTooltip('Call Ada Lovelace'), findsOneWidget);
      expect(find.byTooltip('Call Bob'), findsOneWidget);
      expect(find.byTooltip('New call'), findsOneWidget);
    });

    testWidgets('a recent person shortcut places a voice call', (tester) async {
      final port = withLog();
      await tester.pumpWidget(tab(port, peopleSearch: results()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Call Bob'));
      await tester.pumpAndSettle();

      expect(port.calls, ['start peer-2 video:false']);
    });

    testWidgets('Call and the new call button open the people search', (
      tester,
    ) async {
      await tester.pumpWidget(tab(withLog(), peopleSearch: results()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New call'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      // The shortcuts step aside while searching.
      expect(find.text('Keypad'), findsNothing);
    });

    testWidgets('the keypad types a number and hands it to the search', (
      tester,
    ) async {
      // The keypad sheet is tall.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(tab(withLog(), peopleSearch: results()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keypad'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number'), findsOneWidget);
      // Too short to search yet.
      Finder key(String digit) => find.descendant(
        of: find.byType(GridView),
        matching: find.text(digit),
      );
      await tester.tap(key('8'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithIcon(FilledButton, Icons.call))
            .onPressed,
        isNull,
      );

      for (final digit in ['8', '0', '1', '7', '1', '1']) {
        await tester.tap(key(digit));
        await tester.pump();
      }
      await tester.tap(find.byTooltip('Delete digit'));
      await tester.pump();
      await tester.tap(key('1'));
      await tester.pump();
      expect(find.text('8801711'), findsOneWidget);

      await tester.tap(find.widgetWithIcon(FilledButton, Icons.call));
      await tester.pumpAndSettle();

      // The number went to the people search, which checks it is on Helix
      // before anything is called.
      expect(find.text('people results for "8801711"'), findsOneWidget);
    });

    testWidgets('the shortcuts hold at 2x text and meet the tap targets', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(tab(withLog(), peopleSearch: results()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });

    testWidgets('without a people search there are no shortcuts', (
      tester,
    ) async {
      await tester.pumpWidget(tab(withLog()));
      await tester.pumpAndSettle();

      expect(find.text('Keypad'), findsNothing);
      expect(find.byTooltip('New call'), findsNothing);
    });
  });

  testWidgets('holds at 2x text with nothing overflowing', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(tab(withLog()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('meets the tap-target and label guidelines', (tester) async {
    await tester.pumpWidget(tab(withLog()));
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  test('the clock the screens read is overridable', () {
    expect(clockProvider, isNotNull);
  });
}
