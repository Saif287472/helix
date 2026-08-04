import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/screens/pairing_code_screen.dart';
import 'package:helix_admin/theme/app_theme.dart';

// A bare MaterialApp() has no AppSurfaces ThemeExtension registered, so
// context.sunkenSurface (read by PairingCodeScreen) null-crashes - see the
// same fix in guide_wizard_test.dart.
Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

void main() {
  testWidgets('shows the command to run on the server', (tester) async {
    await tester.pumpWidget(
      _wrap(const PairingCodeScreen(baseUrl: 'https://helix.example.com')),
    );

    expect(
      find.textContaining('curl -s -X POST http://127.0.0.1:8080'),
      findsOneWidget,
    );
  });

  testWidgets('rejects a code that is not exactly 16 digits', (tester) async {
    await tester.pumpWidget(
      _wrap(const PairingCodeScreen(baseUrl: 'https://helix.example.com')),
    );

    await tester.enterText(
      find.byKey(const Key('pairing_code_field')),
      '123',
    );
    await tester.tap(find.byKey(const Key('pairing_code_redeem_button')));
    await tester.pump();

    expect(
      find.text('Enter the 16-digit code exactly as printed.'),
      findsOneWidget,
    );
  });

  testWidgets('rejects redemption when no server URL has been entered yet', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const PairingCodeScreen(baseUrl: '')));

    await tester.enterText(
      find.byKey(const Key('pairing_code_field')),
      '1234567890123456',
    );
    await tester.tap(find.byKey(const Key('pairing_code_redeem_button')));
    await tester.pump();

    expect(
      find.text('Enter your server URL above first, then redeem.'),
      findsOneWidget,
    );
  });
}
