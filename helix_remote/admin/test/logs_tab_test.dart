import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/admin_client.dart';
import 'package:helix_admin/screens/logs_tab.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: child),
);

LogsTab _logsTab({
  required ServerLogs logs,
  VoidCallback? onRefresh,
  bool autoRefreshEnabled = false,
  ValueChanged<bool>? onAutoRefreshChanged,
}) {
  return LogsTab(
    logs: logs,
    onRefresh: onRefresh ?? () {},
    autoRefreshEnabled: autoRefreshEnabled,
    onAutoRefreshChanged: onAutoRefreshChanged,
  );
}

void main() {
  testWidgets('renders the lines the server returned', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _logsTab(
          logs: const ServerLogs(
            lines: ['2026-08-04T12:00:00Z [INFO] server online'],
            source: 'memory',
          ),
        ),
      ),
    );

    expect(find.textContaining('server online'), findsOneWidget);
  });

  // The regression from the field report: the Logs screen showed a bare
  // "No logs available." while the server was actually explaining that it
  // could not write its log file. The explanation has to reach the screen.
  testWidgets(
    "shows the server's explanation instead of a bare empty message",
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          _logsTab(
            logs: const ServerLogs(
              lines: [],
              source: 'none',
              message:
                  'Could not write log file at /app/data/server.log: '
                  'read-only file system',
            ),
          ),
        ),
      );

      expect(find.textContaining('read-only file system'), findsOneWidget);
      expect(find.text('No logs available.'), findsNothing);
    },
  );

  testWidgets('falls back to a generic message when the server sent none', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _logsTab(
          logs: const ServerLogs(lines: [], source: 'none'),
        ),
      ),
    );

    expect(find.text('No logs available.'), findsOneWidget);
  });

  testWidgets('filters lines and reports when nothing matches', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _logsTab(
          logs: const ServerLogs(
            lines: ['[INFO] alpha request', '[ERROR] beta failure'],
            source: 'memory',
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump();

    expect(find.textContaining('beta failure'), findsOneWidget);
    expect(find.textContaining('alpha request'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pump();

    // A filter miss must not be blamed on the server.
    expect(find.textContaining('No lines match'), findsOneWidget);
  });

  testWidgets('a filter miss does not show the server explanation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _logsTab(
          logs: const ServerLogs(
            lines: ['[INFO] alpha'],
            source: 'memory',
            message: 'log file is unwritable',
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.textContaining('log file is unwritable'), findsNothing);
    expect(find.textContaining('No lines match'), findsOneWidget);
  });

  testWidgets('the stream toggle reports its new state to its callback', (
    tester,
  ) async {
    bool? reported;
    await tester.pumpWidget(
      _wrap(
        _logsTab(
          logs: const ServerLogs(lines: ['[INFO] a'], source: 'memory'),
          onAutoRefreshChanged: (value) => reported = value,
        ),
      ),
    );

    // Paused by default, so the button offers to resume.
    expect(find.text('Resume Stream'), findsOneWidget);
    await tester.tap(find.byKey(const Key('logs_stream_toggle_button')));
    await tester.pump();

    expect(reported, isTrue);
  });

  testWidgets('the stream toggle reports the opposite state when live', (
    tester,
  ) async {
    bool? reported;
    await tester.pumpWidget(
      _wrap(
        _logsTab(
          logs: const ServerLogs(lines: ['[INFO] a'], source: 'memory'),
          autoRefreshEnabled: true,
          onAutoRefreshChanged: (value) => reported = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('logs_stream_toggle_button')));
    await tester.pump();

    expect(reported, isFalse);
  });

  testWidgets('the refresh button calls back', (tester) async {
    var refreshed = 0;
    await tester.pumpWidget(
      _wrap(
        _logsTab(
          logs: const ServerLogs(lines: ['[INFO] a'], source: 'memory'),
          onRefresh: () => refreshed++,
        ),
      ),
    );

    // Always enabled, including while the stream is paused: with the poll off,
    // a failed fetch would otherwise be indistinguishable from an idle server.
    await tester.tap(find.byKey(const Key('logs_refresh_button')));
    await tester.pump();

    expect(refreshed, 1);
  });

  testWidgets('copying an empty tail copies nothing rather than failing', (
    tester,
  ) async {
    // `Clipboard.setData` goes over the platform channel, which the test
    // binding leaves unhandled - the future then never completes and the
    // confirmation below is never reached. Mocked so the handler runs to the
    // end.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      _wrap(
        _logsTab(
          logs: const ServerLogs(lines: [], source: 'none'),
        ),
      ),
    );

    // There is nothing to copy, so the button is a no-op rather than a
    // disabled affordance the operator has to reason about - it stays
    // tappable and copies an empty string.
    await tester.tap(find.text('Copy Tail'));
    // pumpAndSettle, not pump: the handler awaits Clipboard.setData before
    // showing the confirmation.
    await tester.pumpAndSettle();

    expect(find.text('Log tail copied to clipboard'), findsOneWidget);
  });

  testWidgets('a filter miss offers a way back rather than a dead end', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _logsTab(
          logs: const ServerLogs(lines: ['[INFO] alpha'], source: 'memory'),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.textContaining('No lines match'), findsOneWidget);

    await tester.tap(find.text('Clear filter'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No lines match'), findsNothing);
    expect(find.textContaining('alpha'), findsOneWidget);
  });

  testWidgets('error and warning lines are coloured distinctly', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _logsTab(
          logs: const ServerLogs(
            lines: ['[INFO] fine', '[WARN] careful', '[ERROR] broken'],
            source: 'memory',
          ),
        ),
      ),
    );

    Color colorOf(String needle) {
      final widget = tester.widget<SelectableText>(
        find.byWidgetPredicate(
          (w) => w is SelectableText && (w.data ?? '').contains(needle),
        ),
      );
      return widget.style!.color!;
    }

    expect(colorOf('fine'), isNot(equals(colorOf('careful'))));
    expect(colorOf('careful'), isNot(equals(colorOf('broken'))));
  });
}
