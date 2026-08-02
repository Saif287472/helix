import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/admin_client.dart';
import 'package:helix_admin/screens/invites_tab.dart';

/// AdminClient makes real socket I/O (even against the loopback fake
/// server below), which doesn't interleave with pumpAndSettle()'s
/// frame-pumping the way fake timers do. tester.runAsync() steps outside
/// the fake-async test zone so the real Future actually resolves, then a
/// couple of pumps flush the resulting setState into the widget tree.
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
  late List<Map<String, dynamic>> invites;
  late int createCalls;
  late bool failListRequests;
  late bool serverOmitsShareableUrlHost;

  String baseUrl() => 'http://${server.address.address}:${server.port}';

  setUp(() async {
    // TestWidgetsFlutterBinding installs a global HttpOverrides that forces
    // every HttpClient request to 400, so AdminClient's real HTTP calls to
    // the loopback fake server below would never land without this. Must
    // be reset per-test (after the binding's own setup), not at top-level
    // main(), which runs too early.
    HttpOverrides.global = null;
    invites = [
      {
        'invite_id': 'inv_1',
        'issuer_type': 'ADMIN',
        'issuer_label': 'admin',
        'status': 'PENDING',
        'created_at': 1000,
        'expires_at': 2000,
        'redeemed_at': null,
        'redeemed_by_account_id': null,
      },
    ];
    createCalls = 0;
    failListRequests = false;
    serverOmitsShareableUrlHost = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'GET' &&
          request.uri.path == '/api/v1/ops/invites') {
        if (failListRequests) {
          request.response.statusCode = 500;
          request.response.write('simulated failure');
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'invites': invites, 'limit': 50, 'offset': 0}),
        );
        await request.response.close();
        return;
      }
      if (request.method == 'POST' &&
          request.uri.path == '/api/v1/ops/invites') {
        createCalls++;
        final code = 'code_$createCalls';
        invites = [
          {
            'invite_id': 'inv_new_$createCalls',
            'issuer_type': 'ADMIN',
            'issuer_label': 'admin',
            'status': 'PENDING',
            'created_at': 3000,
            'expires_at': 4000,
            'redeemed_at': null,
            'redeemed_by_account_id': null,
          },
          ...invites,
        ];
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'invite_id': 'inv_new_$createCalls',
            'invite_code': code,
            'shareable_url': serverOmitsShareableUrlHost
                ? '/join?invite=$code'
                : 'https://example.com/join?invite=$code',
            'expires_at': 4000,
          }),
        );
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

  testWidgets('loads and displays existing invites', (tester) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InvitesTab(client: client)),
      ),
    );
    await _settleWithRealIO(tester);

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('No invites issued yet.'), findsNothing);
  });

  testWidgets('generating an invite shows the shareable link once', (
    tester,
  ) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InvitesTab(client: client)),
      ),
    );
    await _settleWithRealIO(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Generate Invite'));
    await _settleWithRealIO(tester);

    expect(find.textContaining('/join?invite=code_1'), findsOneWidget);
    expect(createCalls, equals(1));
    // The new invite is reflected in the refreshed history table too.
    expect(find.text('PENDING'), findsNWidgets(2));
  });

  testWidgets(
    'a schemeless shareable_url from the server (missing '
    'HELIX_REMOTE_PUBLIC_BASE_URL) is repaired using the connected base URL',
    (tester) async {
      serverOmitsShareableUrlHost = true;
      final client = AdminClient(baseUrl: baseUrl(), token: 't');
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: InvitesTab(client: client))),
      );
      await _settleWithRealIO(tester);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Generate Invite'));
      await _settleWithRealIO(tester);

      expect(
        find.text('${baseUrl()}/join?invite=code_1'),
        findsOneWidget,
        reason:
            'a bare /join?invite=CODE link is useless once pasted '
            'elsewhere - it must be completed with the server address the '
            'admin console is already connected to',
      );
    },
  );

  testWidgets('pagination controls disable at the edges', (tester) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InvitesTab(client: client)),
      ),
    );
    await _settleWithRealIO(tester);

    final previous = tester.widget<TextButton>(
      find.byKey(const Key('invites_previous_page')),
    );
    final next = tester.widget<TextButton>(
      find.byKey(const Key('invites_next_page')),
    );
    // Only one invite (below page size), so no next/previous page yet.
    expect(previous.onPressed, isNull);
    expect(next.onPressed, isNull);
  });

  testWidgets('a load failure surfaces an error instead of crashing', (
    tester,
  ) async {
    failListRequests = true;
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InvitesTab(client: client)),
      ),
    );
    await _settleWithRealIO(tester);

    expect(find.textContaining('Failed to load invites'), findsOneWidget);
  });
}
