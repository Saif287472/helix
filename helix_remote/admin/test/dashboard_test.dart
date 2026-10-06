import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'support/harness.dart';

void main() {
  late AdminHarness h;

  setUp(() => h = AdminHarness());

  Finder tile(String title) => find.widgetWithText(SwitchListTile, title);

  /// The activity tile announced as [label] (its screen-reader text).
  Finder stat(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label,
  );
  bool on(WidgetTester tester, String title) =>
      tester.widget<SwitchListTile>(tile(title)).value;

  testWidgets('shows the server, its health and the activity numbers', (
    tester,
  ) async {
    await h.startSignedIn(tester);

    expect(find.text('Test Server'), findsWidgets);
    expect(find.text('2.0.0-test'), findsOneWidget);
    expect(find.text('Invite code'), findsOneWidget);
    expect(find.text('node-1'), findsOneWidget);
    expect(find.text('10 MiB'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);

    // From the Prometheus text: 3 sockets, 100 requests, 10 of them 5xx.
    expect(stat('Open sockets: 3'), findsOneWidget);
    expect(stat('Requests served: 100'), findsOneWidget);
    expect(stat('Server errors: 10%'), findsOneWidget);
    expect(stat('Dead jobs: 0'), findsOneWidget);
    expect(stat('Undelivered messages: 12'), findsOneWidget);
  });

  testWidgets('says so when the server is not ready', (tester) async {
    h.server.ready = const ReadyResponse(
      ready: false,
      checks: {'database': true, 'storage': false},
    );
    await h.startSignedIn(tester);

    expect(find.text('Not ready'), findsOneWidget);
    expect(find.text('Failing checks: storage.'), findsOneWidget);
  });

  testWidgets('dead jobs are flagged when there are any', (tester) async {
    h.server.metrics = 'helix_jobs_dead 4.0\n';
    await h.startSignedIn(tester);

    expect(stat('Dead jobs: 4'), findsOneWidget);
    // A family the server did not report is a dash, not a made-up zero.
    expect(stat('Open sockets: —'), findsOneWidget);
  });

  testWidgets('metrics that cannot be read do not hide the rest', (
    tester,
  ) async {
    h.server.fail('GET /v1/ops/metrics', ErrorCode.forbidden, times: null);
    await h.startSignedIn(tester);

    expect(find.textContaining('Metrics are not available'), findsOneWidget);
    expect(find.text('2.0.0-test'), findsOneWidget);
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

    await tapText(tester, 'Retry');
    expect(find.text('2.0.0-test'), findsOneWidget);
  });

  testWidgets('a failed reload keeps the last good configuration', (
    tester,
  ) async {
    await h.startSignedIn(tester);
    h.server.fail('GET /v1/admin/config', ErrorCode.internal, times: null);
    await tester.tap(find.byTooltip('Reload server status'));
    await tester.pumpAndSettle();

    expect(find.text('2.0.0-test'), findsOneWidget);
    expect(find.textContaining('server had a problem'), findsWidgets);
  });

  group('maintenance mode', () {
    testWidgets('asks first, then turns it on', (tester) async {
      await h.startSignedIn(tester);
      expect(on(tester, 'Maintenance mode'), isFalse);

      await tester.tap(tile('Maintenance mode'));
      await tester.pumpAndSettle();
      expect(find.text('Turn on maintenance mode?'), findsOneWidget);
      await tapText(tester, 'Turn on');

      expect(h.server.config.maintenance, isTrue);
      expect(on(tester, 'Maintenance mode'), isTrue);
      expect(find.text('Maintenance mode is on.'), findsOneWidget);
      expect(h.server.bodies['PATCH /v1/admin/config']!.single, {
        'maintenance': true,
      });
    });

    testWidgets('cancelling changes nothing', (tester) async {
      await h.startSignedIn(tester);
      await tester.tap(tile('Maintenance mode'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancel');

      expect(h.server.requests, isNot(contains('PATCH /v1/admin/config')));
      expect(on(tester, 'Maintenance mode'), isFalse);
    });

    testWidgets('turning it off needs no confirmation', (tester) async {
      await h.startSignedIn(tester);
      await tester.tap(tile('Maintenance mode'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Turn on');

      await tester.tap(tile('Maintenance mode'));
      await tester.pumpAndSettle();

      expect(h.server.config.maintenance, isFalse);
      expect(find.text('Maintenance mode is off.'), findsOneWidget);
    });

    testWidgets('a refusal leaves the switch where the server has it', (
      tester,
    ) async {
      await h.startSignedIn(tester);
      h.server.fail('PATCH /v1/admin/config', ErrorCode.forbidden);
      await tester.tap(tile('Maintenance mode'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Turn on');

      expect(find.text('The server refused this action.'), findsOneWidget);
      expect(on(tester, 'Maintenance mode'), isFalse);
    });
  });

  testWidgets('the federation switch changes the server', (tester) async {
    await h.startSignedIn(tester);
    await tester.tap(tile('Federation'));
    await tester.pumpAndSettle();

    expect(h.server.config.federationEnabled, isTrue);
    expect(on(tester, 'Federation'), isTrue);
    expect(h.server.bodies['PATCH /v1/admin/config']!.single, {
      'federation_enabled': true,
    });
  });

  group('feature flags', () {
    testWidgets('lists the allow-listed flags with plain names', (
      tester,
    ) async {
      await h.startSignedIn(tester);

      expect(on(tester, 'Accept crash reports from apps'), isFalse);
      expect(on(tester, 'Minimal analytics'), isTrue);
      expect(on(tester, 'Group calls'), isFalse);
    });

    testWidgets('switching one sends only that flag', (tester) async {
      await h.startSignedIn(tester);
      await tester.tap(tile('Group calls'));
      await tester.pumpAndSettle();

      expect(h.server.flags['group_calls'], isTrue);
      expect(on(tester, 'Group calls'), isTrue);
      expect(
        h.server.requests,
        contains('PUT /v1/admin/feature-flags/group_calls'),
      );
      expect(h.server.flags['minimal_analytics'], isTrue);
    });

    testWidgets('a refused change says why and keeps the old value', (
      tester,
    ) async {
      await h.startSignedIn(tester);
      h.server.fail('PUT /v1/admin/feature-flags/{}', ErrorCode.notFound);
      await tester.tap(tile('Group calls'));
      await tester.pumpAndSettle();

      expect(find.text('That item no longer exists.'), findsOneWidget);
      expect(on(tester, 'Group calls'), isFalse);
    });
  });
}
