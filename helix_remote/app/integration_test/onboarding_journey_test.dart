import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/helix_remote_app_shell.dart';
import 'package:helix_remote/screens/server_choice_screen.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P8 integration: invite onboarding reaches personal-server entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const HelixRemoteAppShell(home: ServerChoiceScreen()),
    );

    expect(find.text('Join a personal server'), findsOneWidget);
    await tester.tap(find.text('Join a personal server'));
    await tester.pumpAndSettle();

    expect(find.text('Paste your invite link'), findsOneWidget);
  });
}
