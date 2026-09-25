import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/screens/dashboard_tab.dart';

const _metrics = <String, dynamic>{
  'table_counts': {
    'accounts': 1,
    'messages': 0,
    'quarantine_events': 0,
    'outbox': 0,
  },
  'websocket': {'connected_devices': 0},
  'database_quick_check_ok': true,
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
    expect(cards, findsNWidgets(6));

    final gridFinder = find.byType(GridView);
    expect(gridFinder, findsOneWidget);
    final grid = tester.widget<GridView>(gridFinder);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
  });

  testWidgets('all six metrics fit on one phone screen without scrolling', (
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
    expect(find.text('Quarantined Security Events'), findsOneWidget);
    expect(find.text('Outbox Delivery Retry Queue'), findsOneWidget);
    expect(find.text('Database Status Check'), findsOneWidget);
    expect(find.text('HEALTHY'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
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
