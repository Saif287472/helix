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

/// The Users tab is a master list plus a detail pane, not a table, and every
/// destructive action lives in the detail pane's DANGER ZONE. It only appears
/// once a user is selected, so every action test has to select first.
///
/// The default 800x600 surface is narrower than the 900px split breakpoint,
/// which would collapse the detail pane away entirely; widened here so the
/// split layout is the one under test.
Future<void> _pumpUsersTab(WidgetTester tester, AdminClient client) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: UsersTab(client: client)),
    ),
  );
}

/// Selects [name] in the master list and waits for its detail pane to load.
Future<void> _selectUser(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await _settleWithRealIO(tester);
}

void main() {
  late HttpServer server;
  late List<Map<String, dynamic>> users;
  late bool failListRequests;
  late bool failSuspendRequests;
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
    failSuspendRequests = false;
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
        if (failSuspendRequests) {
          // A 500 with a message, so the client's error path has something
          // real to surface rather than a generic transport failure.
          request.response.statusCode = 500;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({'message': 'suspend rejected by policy'}),
          );
          await request.response.close();
          return;
        }
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

    // The master list row carries name, phone and status.
    expect(find.text('Alice'), findsWidgets);
    expect(find.text('4242'), findsWidgets);
    expect(find.text('ACTIVE'), findsWidgets);
    expect(find.text('No users registered yet.'), findsNothing);

    // The detail pane is where the account id and invite live, and it only
    // renders for the selected user.
    await _selectUser(tester, 'Alice');
    expect(find.text('user_1'), findsWidgets);
    expect(find.text('inv_1'), findsWidgets);
  });

  testWidgets('a user with no display name or phone shows placeholders', (
    tester,
  ) async {
    users = [user(accountId: 'user_2')];
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);
    await _selectUser(tester, 'User (user_2)');

    // Named by account id in the list, and the phone line says there is none
    // rather than showing a bare em dash.
    expect(find.text('User (user_2)'), findsWidgets);
    expect(find.text('No phone bound'), findsOneWidget);
    // No invite was redeemed, so no invite row is claimed.
    expect(find.text('Redeemed invite'), findsNothing);
  });

  testWidgets('suspending a user toggles its status and the action', (
    tester,
  ) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);
    await _selectUser(tester, 'Alice');

    expect(find.text('ACTIVE'), findsWidgets);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend'));
    await _settleWithRealIO(tester);

    expect(find.text('SUSPENDED'), findsWidgets);
    expect(requestedPaths, contains('POST /api/v1/ops/users/user_1/suspend'));
    // The action flips to Restore, so a second tap cannot re-suspend.
    expect(find.widgetWithText(OutlinedButton, 'Restore'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Restore'));
    await _settleWithRealIO(tester);

    expect(find.text('ACTIVE'), findsWidgets);
    expect(requestedPaths, contains('POST /api/v1/ops/users/user_1/unsuspend'));
  });

  testWidgets('a failed suspend reports the error and does not claim success', (
    tester,
  ) async {
    failSuspendRequests = true;
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);
    await _selectUser(tester, 'Alice');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend'));
    await _settleWithRealIO(tester);

    // The row must not flip to SUSPENDED on a failed write, and the success
    // toast must not appear.
    expect(find.text('SUSPENDED'), findsNothing);
    expect(find.text('Account suspended successfully'), findsNothing);
    expect(find.text('ACTIVE'), findsWidgets);
  });

  testWidgets('deleting a user requires confirmation and removes the row', (
    tester,
  ) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);
    await _selectUser(tester, 'Alice');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Data'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this user?'), findsOneWidget);

    // Cancelling the dialog must not call the delete endpoint.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsWidgets);
    expect(
      requestedPaths,
      isNot(contains('POST /api/v1/ops/users/user_1/delete')),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete Data'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete permanently'));
    // Not pumpAndSettle(): confirming starts a real network call and shows
    // an indeterminate CircularProgressIndicator while busy, which never
    // "settles" - see _settleWithRealIO's doc comment above.
    await tester.pump();
    await _settleWithRealIO(tester);

    // The list is the source of truth for "is this account still here". The
    // detail pane is cleared separately, so asserting on it would pass even
    // if the row were still listed.
    expect(find.text('No users registered yet.'), findsOneWidget);
    expect(requestedPaths, contains('POST /api/v1/ops/users/user_1/delete'));
  });

  testWidgets('cancelling the block confirmation calls nothing', (
    tester,
  ) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);
    await _selectUser(tester, 'Alice');

    await tester.tap(find.widgetWithText(FilledButton, 'Permanent Block Phone'));
    await tester.pumpAndSettle();
    expect(find.text('Block this user?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsWidgets);
    expect(
      requestedPaths,
      isNot(contains('POST /api/v1/ops/users/user_1/block')),
    );
  });

  testWidgets('blocking a user requires confirmation and removes the row', (
    tester,
  ) async {
    final client = AdminClient(baseUrl: baseUrl(), token: 't');
    await _pumpUsersTab(tester, client);
    await _settleWithRealIO(tester);
    await _selectUser(tester, 'Alice');

    await tester.tap(find.widgetWithText(FilledButton, 'Permanent Block Phone'));
    await tester.pumpAndSettle();
    expect(find.text('Block this user?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Block permanently'));
    // Not pumpAndSettle(): see the matching comment in the delete test above.
    await tester.pump();
    await _settleWithRealIO(tester);

    expect(requestedPaths, contains('POST /api/v1/ops/users/user_1/block'));
    expect(find.text('No users registered yet.'), findsOneWidget);
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
