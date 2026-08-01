import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('first launch shows the intro screen, not a login gate', (
    tester,
  ) async {
    await tester.pumpWidget(const HelixAdminApp());
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
      await tester.pumpWidget(const HelixAdminApp());
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
      await tester.pumpWidget(const HelixAdminApp());
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

  testWidgets('Settings hosts the connect form and is reachable unconnected', (
    tester,
  ) async {
    await tester.pumpWidget(const HelixAdminApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('GET STARTED'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings_url_field')), findsOneWidget);
    expect(find.byKey(const Key('settings_token_field')), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('the locked dashboard\'s button jumps straight to Settings', (
    tester,
  ) async {
    await tester.pumpWidget(const HelixAdminApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('GET STARTED'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect a server first'));
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.byKey(const Key('settings_url_field')), findsOneWidget);
  });

  testWidgets(
    'Settings\' "Where do I find this?" link jumps straight to the guide\'s '
    'Connect Admin page, and a normal sidebar visit still starts at Welcome',
    (tester) async {
      await tester.pumpWidget(const HelixAdminApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('GET STARTED'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.help_outline));
      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();

      expect(find.text('Connect Helix Admin'), findsOneWidget);
      expect(find.text('Welcome to self-hosting Helix'), findsNothing);

      // A normal sidebar visit to the guide afterwards still starts fresh,
      // rather than being stuck on Connect Admin from the earlier jump.
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Self-Hosting Guide'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to self-hosting Helix'), findsOneWidget);
    },
  );

  testWidgets('relaunching after the intro was shown skips it', (tester) async {
    SharedPreferences.setMockInitialValues({'intro_shown': true});

    await tester.pumpWidget(const HelixAdminApp());
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

      await tester.pumpWidget(const HelixAdminApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      final urlField = tester.widget<TextField>(
        find.byKey(const Key('settings_url_field')),
      );
      expect(urlField.controller?.text, equals('https://saved.example.com'));
      expect(find.text('Not connected'), findsOneWidget);
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
      expect(find.byKey(const Key('settings_url_field')), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);
    },
  );
}
