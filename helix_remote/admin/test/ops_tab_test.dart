import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/admin_client.dart';
import 'package:helix_admin/screens/ops_tab.dart';
import 'package:helix_admin/theme/app_theme.dart';

/// Regression coverage for the Ops screen's audit trail (F17).
///
/// The empty state used to be filled with `_defaultAuditEvents` - a hardcoded
/// list of plausible-looking admin actions. On a freshly provisioned server
/// that showed an operator a history of suspensions, deletions and role changes
/// that had never happened, which is the worst possible thing for an audit
/// view: it looks like evidence.
///
/// The tests below pin the empty state to the empty state, and pin a real
/// event to the server's own fields rather than a formatted guess.
Future<void> _settleWithRealIO(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

void main() {
  late HttpServer server;
  late bool failAudit;
  late List<Map<String, dynamic>> auditEvents;
  late List<String> requestedPaths;

  String baseUrl() => 'http://${server.address.address}:${server.port}';

  Future<void> pumpOpsTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: OpsTab(
            client: AdminClient(baseUrl: baseUrl(), token: 't'),
            logs: const ServerLogs.empty(),
            onRefreshLogs: () {},
            autoRefreshLogs: false,
            onAutoRefreshLogsChanged: (_) {},
            config: const {'server_name': 'Test Server'},
            onSetWorldwideMode: (_) async {},
            onSaveServerName: (_) async => 'Test Server',
            serverHost: 'test.example',
            isLoading: false,
            onTriggerBackup: () async => const {},
            initialSubTab: 'audit',
          ),
        ),
      ),
    );
    await _settleWithRealIO(tester);
  }

  setUp(() async {
    HttpOverrides.global = null;
    failAudit = false;
    auditEvents = [];
    requestedPaths = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestedPaths.add('${request.method} ${request.uri.path}');
      if (request.uri.path == '/api/v1/admin/audit') {
        request.response.headers.contentType = ContentType.json;
        if (failAudit) {
          request.response.statusCode = 500;
          request.response.write(
            jsonEncode({'error': 'audit store unavailable'}),
          );
        } else {
          // The server's own response key is `logs`.
          request.response.write(jsonEncode({'logs': auditEvents}));
        }
        await request.response.close();
        return;
      }
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{}');
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  testWidgets('an empty audit trail renders the empty state, not sample events', (
    tester,
  ) async {
    await pumpOpsTab(tester);

    expect(find.text('No audit events recorded yet'), findsOneWidget);
    // The specific fabricated rows the old default list contained. If any of
    // these can appear without the server sending them, F17 is back.
    for (final fabricated in const [
      'Deleted user account',
      'Suspended user account',
      'Changed user role',
      'Updated server configuration',
    ]) {
      expect(find.textContaining(fabricated), findsNothing);
    }
    // And no event cards at all.
    expect(find.byIcon(Icons.gavel), findsNothing);
  });

  testWidgets('a real audit event is rendered from the server payload', (
    tester,
  ) async {
    // The row shape the server actually writes (see the backend's
    // `logAudit` / `getAuditLogs`): `account_id` is the actor, and there is no
    // target column - an action name is all the trail records.
    auditEvents = [
      {
        'event_id': 'aud_1',
        'account_id': 'acc_admin',
        'device_id': 'dev_1234abcd',
        'action': 'USER_SUSPEND',
        'client_ip': '203.0.113.9',
        'user_agent': 'redacted',
        'timestamp': 1781848900000,
      },
    ];
    await pumpOpsTab(tester);

    expect(find.text('No audit events recorded yet'), findsNothing);
    // The action is carried through verbatim as the row's code, and the detail
    // line names the actor so an operator can tell who did it.
    expect(find.text('USER_SUSPEND'), findsOneWidget);
    expect(find.textContaining('acc_admin'), findsWidgets);
  });

  testWidgets('a read-only poll is not shown as an administrative action', (
    tester,
  ) async {
    // The server already drops these, and so does the tab. Pinning it here
    // because a screen that lists routine polls as audited actions trains an
    // operator to skim past the entries that matter.
    auditEvents = [
      {
        'event_id': 'aud_2',
        'account_id': 'acc_admin',
        'action': 'ADMIN_OPERABILITY_METRICS_READ',
        'timestamp': 1781848900000,
      },
    ];
    await pumpOpsTab(tester);

    expect(find.text('No audit events recorded yet'), findsOneWidget);
    expect(find.textContaining('METRICS READ'), findsNothing);
  });

  testWidgets('a failed audit load is shown as an error, not as "no events"', (
    tester,
  ) async {
    failAudit = true;
    await pumpOpsTab(tester);

    // The two states are very different to an operator - "nothing has been
    // recorded" versus "I cannot see the record" - and must not collapse into
    // one another.
    expect(find.text('No audit events recorded yet'), findsNothing);
    expect(find.textContaining('audit store unavailable'), findsWidgets);
  });

  testWidgets('the audit trail is fetched without an account filter by default', (
    tester,
  ) async {
    await pumpOpsTab(tester);

    expect(requestedPaths, contains('GET /api/v1/admin/audit'));
  });
}
