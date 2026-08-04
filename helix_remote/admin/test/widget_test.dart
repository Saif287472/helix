import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AdminClient's auto-connect makes a real socket connection, which doesn't
/// interleave with pumpAndSettle()'s frame-pumping the way fake timers do.
/// tester.runAsync() steps outside the fake-async test zone so the real
/// Future actually resolves, then a couple of pumps flush the resulting
/// setState into the widget tree.
Future<void> _settleWithRealIO(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

/// The default 800x600 test surface is too narrow for the Settings status
/// card column (260px wide) plus its siblings, causing a RenderFlex
/// overflow - 1000x800 matches the width already proven to keep the fixed
/// sidebar (see "a wide viewport keeps the fixed sidebar" below) rather
/// than switching to the narrow/hamburger layout these tests don't expect.
/// Tests that deliberately exercise a specific width set their own size
/// after this and are unaffected.
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

  testWidgets('first launch shows the intro screen, not a login gate', (
    tester,
  ) async {
    await _pumpAdminApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('HELIX SERVER ADMIN'), findsOneWidget);
    expect(find.text('GET STARTED'), findsOneWidget);
    // No URL/token fields on the intro screen anymore - those live in
    // Settings now.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'Get Started reaches the shell with locked server-dependent tabs',
    (tester) async {
      await _pumpAdminApp(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      // Sidebar and locked Dashboard placeholder, no server connected.
      expect(find.text('Helix Panel'), findsOneWidget);
      expect(find.text('DASHBOARD'), findsOneWidget);
      expect(find.text('Connect a server first'), findsOneWidget);
      expect(find.text('No metrics available. Click refresh.'), findsNothing);
    },
  );

  testWidgets(
    'the Self-Hosting Guide stays reachable with no server connected',
    (tester) async {
      await _pumpAdminApp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Self-Hosting Guide'));
      await tester.pumpAndSettle();

      expect(find.text('Self-Hosting Guide'), findsOneWidget);
      expect(
        find.textContaining('Welcome to self-hosting Helix'),
        findsOneWidget,
      );
      expect(find.text('Connect a server first'), findsNothing);
    },
  );

  testWidgets(
    'Settings shows a status card that opens the connect form, reachable '
    'unconnected',
    (tester) async {
      await _pumpAdminApp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Not connected'), findsOneWidget);
      expect(find.byKey(const Key('settings_url_field')), findsNothing);

      await tester.tap(
        find.byKey(const Key('settings_connection_status_card')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_url_field')), findsOneWidget);
      expect(find.byKey(const Key('settings_token_field')), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    },
  );

  testWidgets('the locked dashboard\'s button jumps straight to Settings', (
    tester,
  ) async {
    await _pumpAdminApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('GET STARTED'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect a server first'));
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS'), findsOneWidget);
    expect(
      find.byKey(const Key('settings_connection_status_card')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Settings\' "Where do I find this?" link jumps straight to the guide\'s '
    'Connect Admin page, and a normal sidebar visit still starts at Welcome',
    (tester) async {
      await _pumpAdminApp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('settings_connection_status_card')),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.help_outline));
      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();

      expect(find.text('Connect Helix Admin'), findsOneWidget);
      expect(find.text('Welcome to self-hosting Helix'), findsNothing);
      // The connection screen should have gotten out of the way so the
      // guide page is actually visible, not hidden behind it.
      expect(find.byKey(const Key('settings_url_field')), findsNothing);

      // A normal sidebar visit to the guide afterwards still starts fresh,
      // rather than being stuck on Connect Admin from the earlier jump.
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      // The Settings tab's own "Self-Hosting Guide" help row has the same
      // text as the sidebar nav item - both are visible at once on a wide
      // viewport. The sidebar's is built first (unselected style: dimmer,
      // regular weight), so .first is it; this test wants specifically the
      // sidebar entry, not the Settings-tab shortcut to the same page.
      await tester.tap(find.text('Self-Hosting Guide').first);
      await tester.pumpAndSettle();

      expect(find.text('Welcome to self-hosting Helix'), findsOneWidget);
    },
  );

  testWidgets('relaunching after the intro was shown skips it', (tester) async {
    SharedPreferences.setMockInitialValues({'intro_shown': true});

    await _pumpAdminApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('HELIX SERVER ADMIN'), findsNothing);
    expect(find.text('Helix Panel'), findsOneWidget);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets(
    'a stored server URL pre-fills Settings but never auto-connects',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'intro_shown': true,
        'server_url': 'https://saved.example.com',
      });

      await _pumpAdminApp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Not connected'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('settings_connection_status_card')),
      );
      await tester.pumpAndSettle();

      final urlField = tester.widget<TextField>(
        find.byKey(const Key('settings_url_field')),
      );
      expect(urlField.controller?.text, equals('https://saved.example.com'));
    },
  );

  testWidgets('a wide viewport keeps the fixed sidebar, no hamburger menu', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const HelixAdminApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('GET STARTED'));
    await tester.pumpAndSettle();

    expect(find.text('Helix Panel'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
  });

  testWidgets(
    'a narrow phone viewport moves navigation into a Drawer behind a '
    'hamburger menu, with no overflow and working tab navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const HelixAdminApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Sidebar nav is now behind a hamburger, not laid out beside content.
      expect(find.byIcon(Icons.menu), findsOneWidget);
      expect(find.text('Connect a server first'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('Helix Panel'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Selecting a tab both navigates and closes the drawer.
      expect(
        find.byKey(const Key('settings_connection_status_card')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.menu), findsOneWidget);
    },
  );

  testWidgets(
    'an unauthorized saved token is cleared and reported on launch, not '
    'silently kept',
    (tester) async {
      // Bound/closed via runAsync, outside testWidgets' FakeAsync zone -
      // HttpServer.bind schedules a real internal idle-timeout Timer that,
      // created inside the fake zone, registers as a FakeTimer and trips
      // "A Timer is still pending" once the widget tree is disposed, since
      // close() doesn't necessarily cancel it before that check runs.
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

      SharedPreferences.setMockInitialValues({
        'intro_shown': true,
        'server_url': serverUrl,
      });
      FlutterSecureStorage.setMockInitialValues({'admin_token': 'dead-token'});

      await _pumpAdminApp(tester);
      await _settleWithRealIO(tester);
      await _settleWithRealIO(tester);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Not connected'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('settings_connection_status_card')),
      );
      // Not pumpAndSettle(): this triggers a real network call behind an
      // indeterminate spinner, which never "settles" - see
      // _settleWithRealIO's doc comment above.
      await _settleWithRealIO(tester);

      expect(find.textContaining('expired or was revoked'), findsOneWidget);
      final tokenField = tester.widget<TextField>(
        find.byKey(const Key('settings_token_field')),
      );
      expect(tokenField.controller?.text, isEmpty);
      expect(
        await const FlutterSecureStorage().read(key: 'admin_token'),
        isNull,
      );
    },
  );

  testWidgets(
    'an unreachable saved server keeps the token and reports connectivity, '
    'not "revoked" - a network blip must not force a full re-pair',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'intro_shown': true,
        // Nothing listens here - a fast, real connection-refused error.
        'server_url': 'http://127.0.0.1:1',
      });
      FlutterSecureStorage.setMockInitialValues({
        'admin_token': 'still-good-token',
      });

      await _pumpAdminApp(tester);
      await _settleWithRealIO(tester);
      await _settleWithRealIO(tester);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Not connected'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('settings_connection_status_card')),
      );
      // Not pumpAndSettle(): same reasoning as the matching comment in the
      // test above - this test happened to pass without it (connection
      // refused resolves almost instantly), but it's the same latent race.
      await _settleWithRealIO(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);
      final tokenField = tester.widget<TextField>(
        find.byKey(const Key('settings_token_field')),
      );
      expect(tokenField.controller?.text, equals('still-good-token'));
      expect(
        await const FlutterSecureStorage().read(key: 'admin_token'),
        equals('still-good-token'),
      );
    },
  );
}
