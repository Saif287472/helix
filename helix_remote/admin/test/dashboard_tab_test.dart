import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/screens/dashboard_tab.dart';

const _metrics = <String, dynamic>{
  'table_counts': {
    'accounts': 1,
    'messages': 0,
    'outbox': 0,
  },
  'websocket': {'connected_devices': 0},
  'database_quick_check_ok': true,
  'push_provider': {'configured': false, 'available': false},
  'sms_provider': {'configured': false, 'name': 'None'},
  'turn': {'configured': false, 'url_count': 0},
};

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: DashboardTab(metrics: _metrics)),
    ),
  );
}

void main() {
  testWidgets('shows a prompt when there are no metrics yet', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DashboardTab(metrics: null))),
    );

    expect(find.textContaining('No metrics available'), findsOneWidget);
  });

  // The reported problem: on a phone each metric occupied about 150dp, so
  // six numbers took roughly a metre of scrolling.
  testWidgets('metric cards render in a 2-column grid on a phone-width screen', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(411, 915));

    final cards = find.byType(Card);
    expect(cards, findsNWidgets(5));

    final gridFinder = find.byType(GridView);
    expect(gridFinder, findsOneWidget);
    final grid = tester.widget<GridView>(gridFinder);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
  });

  testWidgets('all metrics fit on one phone screen without scrolling', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(411, 915));

    final gridFinder = find.byType(GridView);
    expect(gridFinder, findsOneWidget);

    final last = find.text('Database Status Check');
    expect(last, findsOneWidget);
    // Bottom of the final row must land within the viewport height.
    expect(tester.getBottomLeft(last).dy, lessThan(915));
  });

  testWidgets('renders every metric label and value on a phone', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(411, 915));

    expect(find.text('Active Devices Connections'), findsOneWidget);
    expect(find.text('Registered User Accounts'), findsOneWidget);
    expect(find.text('Mailbox Encrypted Messages'), findsOneWidget);
    expect(find.text('Outbox Delivery Retry Queue'), findsOneWidget);
    expect(find.text('Database Status Check'), findsOneWidget);
    expect(find.text('HEALTHY'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  // The card was removed because `table_counts` has no `quarantine_events`
  // key - there is no quarantine subsystem, so the tile could only ever
  // read 0 while implying a security capability the server does not have.
  testWidgets('no metric tile claims a quarantine subsystem', (tester) async {
    await _pumpAt(tester, const Size(411, 915));

    expect(find.text('Quarantined Security Events'), findsNothing);
  });

  // Each integration card must reflect the server's own report. These used to
  // be three hardcoded strings with a green dot and an invented $48.50 SMS
  // balance, shown identically on a server with no FCM key and no TURN.
  testWidgets('integration cards report real push, sms and turn state', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(411, 915));

    expect(find.text('FCM Push Notification Service'), findsOneWidget);
    expect(find.textContaining('Not configured'), findsNWidgets(2));
    expect(find.textContaining('No SMS provider configured'), findsOneWidget);
    expect(find.textContaining('TURN peer connection • Not configured'),
        findsOneWidget);

    // The invented balance is gone.
    expect(find.textContaining('48.50'), findsNothing);
    expect(find.textContaining('2,420'), findsNothing);
  });

  testWidgets('a configured but unavailable push provider is not green', (
    tester,
  ) async {
    final degraded = Map<String, dynamic>.from(_metrics);
    degraded['push_provider'] = {'configured': true, 'available': false};
    degraded['sms_provider'] = {'configured': true, 'name': 'BulkSMSBD'};
    degraded['turn'] = {'configured': true, 'url_count': 2};
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DashboardTab(metrics: degraded))),
    );

    expect(
      find.textContaining('Configured but unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('BulkSMSBD • Configured'), findsOneWidget);
    expect(
      find.textContaining('2 URLs configured'),
      findsOneWidget,
    );
  });

  testWidgets('an unmeasured latency renders a dash, never a made-up number', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(411, 915));

    expect(find.text('Latency: —'), findsOneWidget);
    expect(find.textContaining('Latency: 23ms'), findsNothing);
  });

  testWidgets('a measured latency is shown verbatim', (tester) async {
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DashboardTab(metrics: _metrics, latencyMs: 42)),
      ),
    );

    expect(find.text('Latency: 42ms'), findsOneWidget);
  });

  testWidgets('a long status value does not truncate its label', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final unhealthy = Map<String, dynamic>.from(_metrics);
    unhealthy['database_quick_check_ok'] = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DashboardTab(metrics: unhealthy)),
      ),
    );

    expect(find.text('UNHEALTHY'), findsOneWidget);
    expect(find.text('Database Status Check'), findsOneWidget);
  });

  testWidgets('wider screens keep the multi-column tile grid', (tester) async {
    await _pumpAt(tester, const Size(1000, 900));

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(ListView), findsNothing);

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
  });

  testWidgets('desktop widths use three columns', (tester) async {
    await _pumpAt(tester, const Size(1400, 900));

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
  });

  testWidgets('no layout overflow at a narrow phone width', (tester) async {
    await _pumpAt(tester, const Size(320, 700));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
