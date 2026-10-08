import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'support/harness.dart';

void main() {
  late AdminHarness h;

  setUp(() => h = AdminHarness());

  /// The tile announced as "[title]: [value]..." (its screen-reader text).
  Finder tile(String title, String value) => find.byWidgetPredicate(
    (w) =>
        w is Semantics &&
        (w.properties.label ?? '').startsWith('$title: $value'),
  );

  testWidgets('shows the server, its health and the live numbers', (
    tester,
  ) async {
    await h.startSignedIn(tester);

    expect(find.text('Test Server'), findsWidgets);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.textContaining('Online'), findsOneWidget);

    // From the Prometheus text: 3 sockets, 100 requests, 10 of them 5xx.
    expect(tile('Active device connections', '3'), findsOneWidget);
    expect(tile('Requests served', '100'), findsOneWidget);
    expect(find.text('10% server errors'), findsOneWidget);
    expect(tile('Failed background jobs', '0'), findsOneWidget);
    expect(tile('Undelivered messages', '12'), findsOneWidget);
    expect(tile('Database status', 'HEALTHY'), findsOneWidget);
  });

  testWidgets('a number the server did not report is a dash, not a zero', (
    tester,
  ) async {
    await h.startSignedIn(tester);

    expect(tile('Crash reports', '—'), findsOneWidget);
  });

  testWidgets('lists what the server checked, and how the server signs up', (
    tester,
  ) async {
    await h.startSignedIn(tester);
    await tester.scrollUntilVisible(
      find.text('Sign-up'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Database'), findsOneWidget);
    expect(find.text('Object storage'), findsOneWidget);
    expect(find.text('Invite code'), findsOneWidget);
    expect(find.text('Federation'), findsOneWidget);
  });

  testWidgets('says so when the server is not ready', (tester) async {
    h.server.ready = const ReadyResponse(
      ready: false,
      checks: {'database': true, 'storage': false},
    );
    await h.startSignedIn(tester);

    expect(find.text('Not ready'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Attachments and backups'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Not working'), findsOneWidget);
  });

  testWidgets('failed jobs are flagged when there are any', (tester) async {
    h.server.metrics = 'helix_jobs_dead 4.0\n';
    await h.startSignedIn(tester);

    expect(tile('Failed background jobs', '4'), findsOneWidget);
    // A family the server did not report is a dash, not a made-up zero.
    expect(tile('Active device connections', '—'), findsOneWidget);
  });

  testWidgets('maintenance mode is shown on the health list', (tester) async {
    h.server.config = const AdminConfig(
      serverName: 'Test Server',
      version: '2.0.0-test',
      registration: RegistrationMode.invite,
      maintenance: true,
      federationEnabled: false,
      maxAttachmentBytes: 1024,
      nodeId: 'node-1',
    );
    await h.startSignedIn(tester);
    await tester.scrollUntilVisible(
      find.text('Maintenance mode'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Maintenance mode'), findsOneWidget);
  });

  testWidgets('metrics that cannot be read do not hide the rest', (
    tester,
  ) async {
    h.server.fail('GET /v1/ops/metrics', ErrorCode.forbidden, times: null);
    await h.startSignedIn(tester);

    expect(find.text('Metrics are not available'), findsOneWidget);
    expect(tile('Database status', 'HEALTHY'), findsOneWidget);
  });

  testWidgets('a configuration that cannot be loaded shows an error with '
      'retry', (tester) async {
    h.configured();
    await h.pumpApp(tester);
    await enter(tester, 'Server address', 'helix.test');
    await tapText(tester, 'Continue');
    await enter(tester, 'Admin password', adminPassword);
    h.server.fail('GET /v1/admin/config', ErrorCode.internal);
    await tapText(tester, 'Sign in');

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.textContaining('server had a problem'), findsOneWidget);

    await tapText(tester, 'Try again');
    expect(find.text('Dashboard'), findsOneWidget);
  });

  testWidgets('a failed reload keeps the last good numbers', (tester) async {
    await h.startSignedIn(tester);
    h.server.fail('GET /v1/admin/config', ErrorCode.internal, times: null);
    await tester.tap(find.byTooltip('Reload server status'));
    await tester.pumpAndSettle();

    expect(tile('Requests served', '100'), findsOneWidget);
    expect(find.text('The server could not be checked'), findsOneWidget);
    expect(find.textContaining('server had a problem'), findsWidgets);
  });
}
