import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/features/logs/logs_controller.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'support/harness.dart';

String line(String level, String event, [String? extra]) => jsonEncode({
  'ts': '2026-10-02T10:00:00Z',
  'level': level,
  'event': event,
  'extra': ?extra,
});

void main() {
  late AdminHarness h;

  setUp(() {
    h = AdminHarness();
    h.server.logLines = [
      line('info', 'server_started'),
      line('warn', 'slow_request'),
      line('error', 'unhandled_error'),
    ];
  });

  Future<void> openLogs(WidgetTester tester) async {
    await h.startSignedIn(tester);
    await h.goTo(tester, 'Server log');
  }

  testWidgets('shows the recent lines', (tester) async {
    await openLogs(tester);

    expect(find.textContaining('server_started'), findsOneWidget);
    expect(find.textContaining('slow_request'), findsOneWidget);
    expect(find.textContaining('unhandled_error'), findsOneWidget);
    expect(h.server.requests, contains('GET /v1/admin/logs'));
  });

  testWidgets('errors and warnings are coloured apart from info', (
    tester,
  ) async {
    await openLogs(tester);

    Color? colorOf(String text) =>
        tester.widget<Text>(find.textContaining(text)).style?.color;
    expect(colorOf('server_started'), isNull);
    expect(colorOf('slow_request'), isNotNull);
    expect(colorOf('unhandled_error'), isNotNull);
    expect(colorOf('slow_request'), isNot(colorOf('unhandled_error')));
  });

  testWidgets('filters the lines and offers a way back', (tester) async {
    await openLogs(tester);
    await enter(tester, 'Filter lines', 'slow');
    expect(find.textContaining('slow_request'), findsOneWidget);
    expect(find.textContaining('server_started'), findsNothing);

    await enter(tester, 'Filter lines', 'zzz');
    expect(find.text('No lines match the filter'), findsOneWidget);
    await tapText(tester, 'Clear filter');
    expect(find.textContaining('server_started'), findsOneWidget);
  });

  testWidgets('copies the shown lines', (tester) async {
    final copied = recordClipboard(tester);
    await openLogs(tester);
    await enter(tester, 'Filter lines', 'error');
    await tester.tap(find.byTooltip('Copy shown lines'));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains('unhandled_error'));
    expect(copied.single, isNot(contains('server_started')));
  });

  testWidgets('an empty log says so', (tester) async {
    h.server.logLines = [];
    await openLogs(tester);

    expect(find.text('No log lines yet'), findsOneWidget);
  });

  testWidgets('a failure to load is an error with retry', (tester) async {
    h.server.fail('GET /v1/admin/logs', ErrorCode.unavailable);
    await openLogs(tester);

    expect(find.text('Something went wrong'), findsOneWidget);
    await tapText(tester, 'Retry');
    expect(find.textContaining('server_started'), findsOneWidget);
  });

  group('following live', () {
    testWidgets('opens the socket with the admin token and shows new lines', (
      tester,
    ) async {
      await openLogs(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Follow live'));
      await tester.pumpAndSettle();

      expect(h.sockets, hasLength(1));
      expect(h.sockets.single.headers['authorization'], startsWith('Bearer '));
      expect(
        find.text('New lines appear as they are written.'),
        findsOneWidget,
      );

      h.sockets.single.push(line('info', 'fresh_line'));
      await tester.pumpAndSettle();
      expect(find.textContaining('fresh_line'), findsOneWidget);
      // The earlier lines are still there.
      expect(find.textContaining('server_started'), findsOneWidget);
    });

    testWidgets('turning it off closes the socket and stops updating', (
      tester,
    ) async {
      await openLogs(tester);
      final toggle = find.widgetWithText(SwitchListTile, 'Follow live');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final socket = h.sockets.single;
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      // Closing the socket completes on real event-loop turns (stream
      // cancellation futures live in the root zone).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );

      expect(socket.closedByClient, isTrue);
      expect(
        find.text('Showing the last lines; not updating.'),
        findsOneWidget,
      );
    });

    testWidgets('where a socket is impossible it polls instead', (
      tester,
    ) async {
      h.socketError = UnsupportedError('no websocket');
      await openLogs(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Follow live'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Reloading every 3 seconds'), findsOneWidget);
      h.server.logLines = [...h.server.logLines, line('info', 'polled_line')];
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.textContaining('polled_line'), findsOneWidget);
    });

    testWidgets('an expired token on the socket returns to sign-in', (
      tester,
    ) async {
      h.socketError = const RealtimeUpgradeException(
        ApiException(status: 401, code: ErrorCode.unauthenticated),
      );
      await openLogs(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Follow live'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
    });
  });

  group('LogsController', () {
    test('keeps at most maxLines, dropping the oldest', () async {
      final api = h.services().apiFactory(
        Uri.parse('https://helix.test'),
        session: h.server.issue(),
      );
      final logs = LogsController(
        AdminContext(api: api, report: (_) {}, now: h.clock.call),
        maxLines: 3,
      );
      addTearDown(() async {
        logs.dispose();
        await api.close();
      });

      await logs.setLive(true);
      await Future<void>.delayed(Duration.zero);
      for (var i = 1; i <= 5; i++) {
        h.sockets.single.push(line('info', 'line_$i'));
      }
      await Future<void>.delayed(Duration.zero);

      expect(logs.lines.map((l) => l.raw), [
        line('info', 'line_3'),
        line('info', 'line_4'),
        line('info', 'line_5'),
      ]);
    });

    test('a dropped socket falls back to polling and says so', () async {
      final api = h.services().apiFactory(
        Uri.parse('https://helix.test'),
        session: h.server.issue(),
      );
      final logs = LogsController(
        AdminContext(api: api, report: (_) {}, now: h.clock.call),
        pollInterval: const Duration(milliseconds: 20),
      );
      addTearDown(() async {
        logs.dispose();
        await api.close();
      });

      await logs.setLive(true);
      await Future<void>.delayed(Duration.zero);
      await h.sockets.single.serverCloses();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(logs.feed, LogFeed.polling);
      expect(logs.feedNote, contains('The live connection closed.'));
      // It keeps the log current by fetching the tail.
      h.server.logLines = [line('info', 'polled_line')];
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(logs.lines.map((l) => l.raw), [line('info', 'polled_line')]);
    });

    test('a line that is not JSON is kept as plain text', () {
      final entry = LogEntry.parse('not json at all');
      expect(entry.raw, 'not json at all');
      expect(entry.level, isNull);
      expect(entry.isError, isFalse);
    });
  });
}
