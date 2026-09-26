import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/admin_client.dart';
import 'package:helix_admin/screens/reports_tab.dart';
import 'package:helix_admin/theme/app_theme.dart';

/// Regression coverage for the Reports screen (F1, F24).
///
/// Two things this pins down, both of which used to be wrong in the direction
/// that matters most for a moderation tool:
///
///  * a failed load must be visibly different from "there are no reports" -
///    an operator who cannot tell those apart has no reason to look again;
///  * a failed resolve or dismiss must not be rendered as a success. These are
///    the actions an operator takes to close out an abuse report, so a
///    false success means the report stays open and nobody knows.
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
  late bool failList;
  late bool failActions;
  late List<String> requestedPaths;
  late List<Map<String, dynamic>> reports;

  String baseUrl() => 'http://${server.address.address}:${server.port}';

  Map<String, dynamic> report({
    String id = 'rep_1',
    String status = 'PENDING',
  }) => {
    'report_id': id,
    'category': 'Harassment',
    'status': status,
    'subject_account_id': 'acc_bad',
    'subject_display_name': 'Troublemaker',
    'reporter_account_id': 'acc_good',
    'reporter_display_name': 'Witness',
    'context_hash': 'sha256:abc123',
    'created_at': 1000,
  };

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ReportsTab(client: AdminClient(baseUrl: baseUrl(), token: 't'))),
      ),
    );
    await _settleWithRealIO(tester);
  }

  setUp(() async {
    HttpOverrides.global = null;
    failList = false;
    failActions = false;
    requestedPaths = [];
    reports = [report()];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestedPaths.add('${request.method} ${request.uri.path}');
      if (request.method == 'GET' && request.uri.path == '/api/v1/admin/reports') {
        request.response.headers.contentType = ContentType.json;
        if (failList) {
          request.response.statusCode = 500;
          request.response.write(jsonEncode({'error': 'reports store offline'}));
        } else {
          request.response.write(jsonEncode({'reports': reports}));
        }
        await request.response.close();
        return;
      }
      final action = RegExp(
        r'^/api/v1/admin/reports/([^/]+)/(resolve|dismiss)$',
      ).firstMatch(request.uri.path);
      if (request.method == 'POST' && action != null) {
        request.response.headers.contentType = ContentType.json;
        if (failActions) {
          // 500 with a message, so the client's non-200 path has something
          // real to surface.
          request.response.statusCode = 500;
          request.response.write(
            jsonEncode({'error': 'moderation action refused'}),
          );
        } else {
          request.response.write(jsonEncode({'status': 'RESOLVED'}));
        }
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  group('load failures are not mistaken for an empty queue', () {
    testWidgets('a failed load shows the error, not the empty state', (
      tester,
    ) async {
      failList = true;
      await pumpTab(tester);

      expect(find.textContaining('reports store offline'), findsOneWidget);
      // The empty state is a different screen and must not be shown instead.
      expect(find.text('No user reports or moderation flags.'), findsNothing);
    });

    testWidgets('an empty response really does show the empty state', (
      tester,
    ) async {
      reports = [];
      await pumpTab(tester);

      expect(find.text('No user reports or moderation flags.'), findsOneWidget);
    });
  });

  group('a failed moderation action is never reported as a success', () {
    // The action bar is rendered only for a pending report, so its presence is
    // how these tests assert "the report is still open". A pending report
    // carries no status badge, so there is no 'PENDING' string to look for.
    testWidgets('a refused resolve leaves the report pending and says why', (
      tester,
    ) async {
      await pumpTab(tester);
      expect(find.widgetWithText(FilledButton, 'Resolve'), findsOneWidget);

      failActions = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Resolve'));
      await tester.pump();
      await _settleWithRealIO(tester);

      expect(
        requestedPaths,
        contains('POST /api/v1/admin/reports/rep_1/resolve'),
      );
      // No success toast, and the report is not re-rendered as resolved.
      expect(find.text('Report marked as Resolved'), findsNothing);
      expect(find.text('RESOLVED'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Resolve'), findsOneWidget);
      // The server's own explanation is surfaced rather than swallowed.
      expect(find.textContaining('moderation action refused'), findsWidgets);
    });

    testWidgets('a refused dismiss is likewise not a success', (tester) async {
      await pumpTab(tester);

      failActions = true;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Dismiss'));
      await tester.pump();
      await _settleWithRealIO(tester);

      expect(
        requestedPaths,
        contains('POST /api/v1/admin/reports/rep_1/dismiss'),
      );
      expect(find.text('Report dismissed'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Dismiss'), findsOneWidget);
      expect(find.textContaining('moderation action refused'), findsWidgets);
    });

    testWidgets('a successful resolve does report success', (tester) async {
      await pumpTab(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Resolve'));
      await tester.pump();
      await _settleWithRealIO(tester);

      expect(find.text('Report marked as Resolved'), findsOneWidget);
    });

    testWidgets('a resolved report offers no further actions', (tester) async {
      reports = [report(status: 'RESOLVED')];
      await pumpTab(tester);

      // The action bar is for pending reports only, so a decided one is read
      // - and cannot be resolved twice.
      expect(find.widgetWithText(FilledButton, 'Resolve'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Dismiss'), findsNothing);
      expect(find.text('RESOLVED'), findsOneWidget);
    });
  });

  testWidgets('a report without the optional fields still renders', (
    tester,
  ) async {
    // The server is not obliged to send display names or a context hash; the
    // screen must fall back to the account ids rather than crash or blank out.
    reports = [
      {
        'report_id': 'rep_bare',
        'status': 'PENDING',
        'subject_account_id': 'acc_subject',
        'reporter_account_id': 'acc_reporter',
      },
    ];
    await pumpTab(tester);

    // The card labels what it is showing, so the fallback is checked on the
    // rendered line rather than a bare id.
    expect(find.textContaining('Reported user: acc_subject'), findsOneWidget);
    expect(find.textContaining('Reporter: acc_reporter'), findsOneWidget);
  });
}
