import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/admin_client.dart';
import 'package:helix_admin/screens/users_tab.dart';

/// See invites_tab_test.dart's identical helper for why real async I/O
/// needs tester.runAsync() rather than plain pump()/pumpAndSettle().
Future<void> _settleWithRealIO(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

/// The Users table's seven columns (plus three per-row action icons) don't
/// fit the default 800x600 test surface - past it, `tester.tap` on a
/// tooltip/icon there fails hit-testing since that part of the row is laid
/// out beyond the root render tree's bounds, not merely scrolled out of
/// view. Widened for every test here rather than only the ones that
/// currently tap into the Actions column, so a future column/action
/// addition doesn't silently reintroduce this for tests that happen not to
/// interact with it yet.
Future<void> _pumpUsersTab(WidgetTester tester, AdminClient client) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: UsersTab(client: client)),
    ),
  );
}

void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> users;
  late bool failListRequests;
  late List<String> requestedPaths;

  String baseUrl() => 'http://${server.address.address}:${server.port}';

  Map<String, dynamic> user({
    required String accountId,
    String displayName = '',
    String phoneLast4 = '',
    String? inviteId,
    String status = 'ACTIVE',
    int createdAt = 1000,
  }) => {
    'account_id': accountId,
    'created_at': createdAt,
    'status': status,
    'phone_last4': phoneLast4,
    'display_name': displayName,
    'invite_id': inviteId,
    'invite_issuer_label': inviteId == null ? null : 'admin',
    'invite_redeemed_at': inviteId == null ? null : createdAt,
  };

  setUp(() async {
    HttpOverrides.global = null;
    users = [
      user(
        accountId: 'user_1',
        displayName: 'Alice',
        phoneLast4: '4242',
        inviteId: 'inv_1',
      ),
    ];
    failListRequests = false;
    requestedPaths = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestedPaths.add('${request.method} ${request.uri.path}');
      if (request.method == 'GET' && request.uri.path == '/api/v1/ops/users') {
        if (failListRequests) {
          request.response.statusCode = 500;
          request.response.write('simulated failure');
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'users': users, 'limit': 20, 'offset': 0}),
        );
        await request.response.close();
        return;
      }
      final suspendMatch = RegExp(
        r'^/api/v1/ops/users/([^/]+)/suspend$',
      ).firstMatch(request.uri.path);
      if (request.method == 'POST' && suspendMatch != null) {
        final accountId = suspendMatch.group(1)!;
        users = users
            .map(
              (u) => u['account_id'] == accountId
                  ? {...u, 'status': 'SUSPENDED'}
                  : u,
            )
            .toList();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'account_id': accountId, 'status': 'SUSPENDED'}),
        );
        await request.response.close();
        return;
      }
      final unsuspendMatch = RegExp(
        r'^/api/v1/ops/users/([^/]+)/unsuspend$',
      ).firstMatch(request.uri.path);
      if (request.method == 'POST' && unsuspendMatch != null) {
        final accountId = unsuspendMatch.group(1)!;
        users = users
            .map(
              (u) =>
                  u['account_id'] == accountId ? {...u, 'status': 'ACTIVE'} : u,
            )
            .toList();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'account_id': accountId, 'status': 'ACTIVE'}),
        );
        await request.response.close();
        return;
      }
      final deleteMatch = RegExp(
        r'^/api/v1/ops/users/([^/]+)/delete$',
      ).firstMatch(request.uri.path);
      if (request.method == 'POST' && deleteMatch != null) {
        final accountId = deleteMatch.group(1)!;
        users = users.where((u) => u['account_id'] != accountId).toList();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'account_id': accountId, 'deleted': true}),
        );
        await request.response.close();
        return;
      }
      final blockMatch = RegExp(
        r'^/api/v1/ops/users/([^/]+)/block$',
      ).firstMatch(request.uri.path);
      if (request.method == 'POST' && blockMatch != null) {
        final accountId = blockMatch.group(1)!;
        users = users.where((u) => u['account_id'] != accountId).toList();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'account_id': accountId,
            'blocked': true,
            'deleted': true,
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

  testWidgets('loads and displays existing users, displaying the phone number', (
    tester,
  ) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('user_1'), findsOneWidget);
    expect(find.text('4242'), findsOneWidget);
    expect(find.text('inv_1'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('No users registered yet.'), findsNothing);
  });

  testWidgets('a user with no display name or invite shows placeholders', (
    tester,
  ) async {
    users = [user(accountId: 'user_2')];
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);

    expect(find.text('—'), findsNWidgets(3)); // name, phone, invite
  });

  testWidgets('suspending a user toggles its status and icon', (tester) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);

    expect(find.text('ACTIVE'), findsOneWidget);
    await tester.tap(find.byTooltip('Suspend access (temporary)'));
    await _settleWithRealIO(tester);

    expect(find.text('SUSPENDED'), findsOneWidget);
    expect(requestedPaths, contains('POST /api/v1/ops/users/user_1/suspend'));

    await tester.tap(find.byTooltip('Restore access'));
    await _settleWithRealIO(tester);

    expect(find.text('ACTIVE'), findsOneWidget);
    expect(requestedPaths, contains('POST /api/v1/ops/users/user_1/unsuspend'));
  });

  testWidgets('deleting a user requires confirmation and removes the row', (
    tester,
  ) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);

    await tester.tap(find.byTooltip('Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this user?'), findsOneWidget);

    // Cancelling the dialog must not call the delete endpoint.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(
      requestedPaths,
      isNot(contains('POST /api/v1/ops/users/user_1/delete')),
    );

    await tester.tap(find.byTooltip('Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
    // Not pumpAndSettle(): confirming starts a real network call and shows
    // an indeterminate CircularProgressIndicator while busy, which never
    // "settles" - see _settleWithRealIO's doc comment above.
    await tester.pump();
    await _settleWithRealIO(tester);

    expect(find.text('Alice'), findsNothing);
    expect(find.text('No users registered yet.'), findsOneWidget);
    expect(requestedPaths, contains('POST /api/v1/ops/users/user_1/delete'));
  });

  testWidgets('blocking a user requires confirmation and removes the row', (
    tester,
  ) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);

    await tester.tap(find.byTooltip('Block (delete + ban phone number)'));
    await tester.pumpAndSettle();

    expect(find.text('Block this user?'), findsOneWidget);

    // Cancelling the dialog must not call the block endpoint.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(
      requestedPaths,
      isNot(contains('POST /api/v1/ops/users/user_1/block')),
    );

    await tester.tap(find.byTooltip('Block (delete + ban phone number)'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Block permanently'));
    // Not pumpAndSettle(): see the matching comment in the delete test above.
    await tester.pump();
    await _settleWithRealIO(tester);

    expect(find.text('Alice'), findsNothing);
    expect(find.text('No users registered yet.'), findsOneWidget);
    expect(requestedPaths, contains('POST /api/v1/ops/users/user_1/block'));
  });

  testWidgets('pagination controls disable at the edges', (tester) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);

    final previous = tester.widget<TextButton>(
      find.byKey(const Key('users_previous_page')),
    );
    final next = tester.widget<TextButton>(
      find.byKey(const Key('users_next_page')),
    );
    // Only one user (below page size), so no next/previous page yet.
    expect(previous.onPressed, isNull);
    expect(next.onPressed, isNull);
  });

  testWidgets('a load failure surfaces an error instead of crashing', (
    tester,
  ) async {
    failListRequests = true;
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);

    expect(find.textContaining('Failed to load users'), findsOneWidget);
  });
}
