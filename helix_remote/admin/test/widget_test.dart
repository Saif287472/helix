import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/main.dart';
import 'package:helix_admin/screens/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settleWithRealIO(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

Future<void> _pumpAdminApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const HelixAdminApp());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('first launch opens directly to the LoginScreen', (tester) async {
    await _pumpAdminApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('HELIX SERVER ADMIN'), findsOneWidget);
    expect(find.byKey(const Key('login_url_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(find.byKey(const Key('login_guide_button')), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
  });

  testWidgets(
    'the Self-Hosting Guide is accessible unauthenticated via the guide button',
    (tester) async {
      await _pumpAdminApp(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login_guide_button')));
      await tester.pumpAndSettle();

      expect(find.text('SELF-HOSTING GUIDE'), findsOneWidget);
      expect(
        find.textContaining('Welcome to self-hosting Helix'),
        findsOneWidget,
      );

      // Back button in the AppBar returns to the LoginScreen
      await tester.tap(find.byTooltip('Back to Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('HELIX SERVER ADMIN'), findsOneWidget);
      expect(find.byKey(const Key('login_button')), findsOneWidget);
    },
  );

  testWidgets('successful sign in takes the user straight to the dashboard', (
    tester,
  ) async {
    late HttpServer server;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path == '/api/v1/ops/config') {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'server_id': 'test-server',
              'server_name': 'Test Server',
              'federation': {'domain': 'test.domain'},
            }),
          );
        } else if (request.uri.path == '/api/v1/ops/metrics') {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'table_counts': {'accounts': 5},
              'websocket': {'connected_devices': 2},
              'database_quick_check_ok': true,
            }),
          );
        } else if (request.uri.path == '/api/v1/ops/logs') {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'logs': <String>[]}));
        } else {
          request.response.statusCode = 200;
        }
        await request.response.close();
      });
    });
    addTearDown(() => tester.runAsync(() => server.close(force: true)));
    final serverUrl = 'http://${server.address.address}:${server.port}';

    await _pumpAdminApp(tester);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('login_url_field')),
      serverUrl,
    );
    await tester.enterText(
      find.byKey(const Key('login_password_field')),
      'secret-password',
    );
    await tester.tap(find.byKey(const Key('login_button')));
    await _settleWithRealIO(tester);
    await _settleWithRealIO(tester);

    expect(find.text('Helix Panel'), findsOneWidget);
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.byKey(const Key('sidebar_sign_out_button')), findsOneWidget);
  });

  testWidgets('signing out from the sidebar returns to the LoginScreen', (
    tester,
  ) async {
    late HttpServer server;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'logs': <String>[]}));
        await request.response.close();
      });
    });
    addTearDown(() => tester.runAsync(() => server.close(force: true)));
    final serverUrl = 'http://${server.address.address}:${server.port}';

    SharedPreferences.setMockInitialValues({'server_url': serverUrl});
    FlutterSecureStorage.setMockInitialValues({'admin_token': 'active-token'});

    await _pumpAdminApp(tester);
    await _settleWithRealIO(tester);
    await _settleWithRealIO(tester);

    expect(find.text('Helix Panel'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sidebar_sign_out_button')));
    await tester.pumpAndSettle();

    expect(find.text('HELIX SERVER ADMIN'), findsOneWidget);
    expect(find.byKey(const Key('login_button')), findsOneWidget);
    expect(
      await const FlutterSecureStorage().read(key: 'admin_token'),
      isNull,
    );
  });

  testWidgets('an unauthorized saved token shows error banner on LoginScreen', (
    tester,
  ) async {
    late HttpServer server;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 401;
        await request.response.close();
      });
    });
    addTearDown(() => tester.runAsync(() => server.close(force: true)));
    final serverUrl = 'http://${server.address.address}:${server.port}';

    SharedPreferences.setMockInitialValues({'server_url': serverUrl});
    FlutterSecureStorage.setMockInitialValues({'admin_token': 'expired-token'});

    await _pumpAdminApp(tester);
    await _settleWithRealIO(tester);
    await _settleWithRealIO(tester);

    expect(find.text('HELIX SERVER ADMIN'), findsOneWidget);
    expect(find.byKey(const Key('login_error_text')), findsOneWidget);
    expect(
      find.textContaining('Session expired or admin password changed'),
      findsOneWidget,
    );
    expect(
      await const FlutterSecureStorage().read(key: 'admin_token'),
      isNull,
    );
  });

  testWidgets(
    'an unreachable saved server keeps the token and reports connection error on LoginScreen',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'server_url': 'http://127.0.0.1:1',
      });
      FlutterSecureStorage.setMockInitialValues({
        'admin_token': 'still-good-token',
      });

      await _pumpAdminApp(tester);
      await _settleWithRealIO(tester);
      await _settleWithRealIO(tester);

      expect(find.text('HELIX SERVER ADMIN'), findsOneWidget);
      expect(find.byKey(const Key('login_error_text')), findsOneWidget);
      expect(find.textContaining('Could not reach server'), findsOneWidget);
      expect(
        await const FlutterSecureStorage().read(key: 'admin_token'),
        equals('still-good-token'),
      );
    },
  );

  testWidgets('a wide viewport keeps the fixed sidebar when logged in', (
    tester,
  ) async {
    late HttpServer server;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'logs': <String>[]}));
        await request.response.close();
      });
    });
    addTearDown(() => tester.runAsync(() => server.close(force: true)));
    final serverUrl = 'http://${server.address.address}:${server.port}';

    SharedPreferences.setMockInitialValues({'server_url': serverUrl});
    FlutterSecureStorage.setMockInitialValues({'admin_token': 'valid-token'});

    await _pumpAdminApp(tester);
    await _settleWithRealIO(tester);
    await _settleWithRealIO(tester);

    expect(find.text('Helix Panel'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
  });

  testWidgets('a narrow phone viewport moves navigation into a Drawer behind a hamburger menu', (
    tester,
  ) async {
    late HttpServer server;
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'logs': <String>[]}));
        await request.response.close();
      });
    });
    addTearDown(() => tester.runAsync(() => server.close(force: true)));
    final serverUrl = 'http://${server.address.address}:${server.port}';

    SharedPreferences.setMockInitialValues({'server_url': serverUrl});
    FlutterSecureStorage.setMockInitialValues({'admin_token': 'valid-token'});

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const HelixAdminApp());
    await _settleWithRealIO(tester);
    await _settleWithRealIO(tester);

    expect(find.byIcon(Icons.menu), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('Helix Panel'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets(
    'uninitialized server opens in setup mode and allows creating admin password',
    (tester) async {
      late HttpServer server;
      var needsSetup = true;
      var setPasswordCalled = false;

      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          if (request.uri.path == '/api/v1/ops/setup-status') {
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'needs_setup': needsSetup,
                'server_id': 'setup-server',
              }),
            );
          } else if (request.uri.path == '/api/v1/ops/setup-admin-password') {
            setPasswordCalled = true;
            needsSetup = false;
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'success': true}));
          } else if (request.uri.path == '/api/v1/ops/config') {
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'server_id': 'setup-server',
                'server_name': 'Fresh Server',
                'federation': {'domain': 'setup.domain'},
              }),
            );
          } else if (request.uri.path == '/api/v1/ops/metrics') {
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'table_counts': {'accounts': 0},
                'websocket': {'connected_devices': 0},
                'database_quick_check_ok': true,
              }),
            );
          } else if (request.uri.path == '/api/v1/ops/logs') {
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'logs': <String>[]}));
          } else {
            request.response.statusCode = 200;
          }
          await request.response.close();
        });
      });
      addTearDown(() => tester.runAsync(() => server.close(force: true)));
      final serverUrl = 'http://${server.address.address}:${server.port}';

      await _pumpAdminApp(tester);
      await tester.pumpAndSettle();

      // Enter server url and trigger check
      await tester.enterText(
        find.byKey(const Key('login_url_field')),
        serverUrl,
      );
      await tester.runAsync(() async {
        final loginScreen = tester.widget<LoginScreen>(
          find.byType(LoginScreen),
        );
        await loginScreen.onCheckUrl?.call();
      });
      await tester.pumpAndSettle();

      expect(find.text('CREATE ADMIN PASSWORD'), findsOneWidget);
      expect(find.byKey(const Key('setup_password_field')), findsOneWidget);
      expect(find.byKey(const Key('setup_confirm_password_field')), findsOneWidget);

      // Enter new password and confirm
      await tester.enterText(
        find.byKey(const Key('setup_password_field')),
        'master_pass_123',
      );
      await tester.enterText(
        find.byKey(const Key('setup_confirm_password_field')),
        'master_pass_123',
      );
      await tester.ensureVisible(find.byKey(const Key('setup_submit_button')));
      await tester.tap(find.byKey(const Key('setup_submit_button')));
      await tester.pump();
      await _settleWithRealIO(tester);
      await tester.pumpAndSettle();

      expect(setPasswordCalled, isTrue);
      expect(find.text('DASHBOARD'), findsOneWidget);
    },
  );
}
