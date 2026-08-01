import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/screens/pairing_code_screen.dart';
import 'package:helix_admin/screens/scan_token_screen.dart';
import 'package:helix_admin/screens/settings_tab.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

SettingsTab _settingsTab({
  required TextEditingController tokenController,
  TextEditingController? urlController,
  VoidCallback? onOpenConnectGuide,
}) {
  return SettingsTab(
    isDarkMode: true,
    onDarkModeChanged: (_) {},
    urlController: urlController ?? TextEditingController(),
    tokenController: tokenController,
    isConnected: false,
    isConnecting: false,
    errorMessage: null,
    onConnect: () {},
    onDisconnect: () {},
    onOpenConnectGuide: onOpenConnectGuide ?? () {},
  );
}

void main() {
  testWidgets('the help icon on the token field opens the connect guide', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _wrap(
        _settingsTab(
          tokenController: TextEditingController(),
          onOpenConnectGuide: () => opened = true,
        ),
      ),
    );

    await tester.ensureVisible(find.byIcon(Icons.help_outline));
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('the scan button opens the camera scan screen', (tester) async {
    await tester.pumpWidget(
      _wrap(_settingsTab(tokenController: TextEditingController())),
    );

    await tester.tap(find.byKey(const Key('settings_scan_token_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ScanTokenScreen), findsOneWidget);
  });

  testWidgets('a scanned token result is trimmed into the token field', (
    tester,
  ) async {
    final tokenController = TextEditingController();
    await tester.pumpWidget(
      _wrap(_settingsTab(tokenController: tokenController)),
    );

    await tester.tap(find.byKey(const Key('settings_scan_token_button')));
    await tester.pumpAndSettle();

    // Simulate a successful scan by popping the scan route with a result,
    // the way ScanTokenScreen does on barcode detection.
    Navigator.of(
      tester.element(find.byType(ScanTokenScreen)),
    ).pop('  AbCdEfGhIjKlMnOpQrStUvWxYz012345  ');
    await tester.pumpAndSettle();

    expect(tokenController.text, equals('AbCdEfGhIjKlMnOpQrStUvWxYz012345'));
  });

  testWidgets(
    'the pairing code button opens the pairing code screen with the '
    'current URL field value',
    (tester) async {
      final urlController = TextEditingController(
        text: 'https://helix.example.com',
      );
      await tester.pumpWidget(
        _wrap(
          _settingsTab(
            tokenController: TextEditingController(),
            urlController: urlController,
          ),
        ),
      );

      await tester.tap(
        find.byKey(const Key('settings_pairing_code_button')),
      );
      await tester.pumpAndSettle();

      final screen = tester.widget<PairingCodeScreen>(
        find.byType(PairingCodeScreen),
      );
      expect(screen.baseUrl, equals('https://helix.example.com'));
    },
  );

  testWidgets('a redeemed pairing code result fills the token field', (
    tester,
  ) async {
    final tokenController = TextEditingController();
    await tester.pumpWidget(
      _wrap(_settingsTab(tokenController: tokenController)),
    );

    await tester.tap(find.byKey(const Key('settings_pairing_code_button')));
    await tester.pumpAndSettle();

    // Simulate a successful redemption by popping the pairing route with a
    // result, the way PairingCodeScreen does after a successful exchange.
    Navigator.of(
      tester.element(find.byType(PairingCodeScreen)),
    ).pop('freshly-rotated-admin-token');
    await tester.pumpAndSettle();

    expect(tokenController.text, equals('freshly-rotated-admin-token'));
  });
}
