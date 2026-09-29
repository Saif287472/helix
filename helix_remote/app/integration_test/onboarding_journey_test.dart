import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/helix_remote_app_shell.dart';
import 'package:helix_remote/screens/setup/setup_screen.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'P8 integration: the hidden corner reaches personal-server entry',
    (tester) async {
      await tester.pumpWidget(const HelixRemoteAppShell(home: SetupScreen()));

      expect(find.text('Sign in'), findsOneWidget);
      final corner = find.byKey(const ValueKey('advanced-mode-corner'));
      for (var i = 0; i < 3; i++) {
        await tester.tap(corner);
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.tap(find.text('Advanced mode'));
      await tester.pumpAndSettle();

      expect(find.text('Personal server'), findsOneWidget);
    },
  );
}
