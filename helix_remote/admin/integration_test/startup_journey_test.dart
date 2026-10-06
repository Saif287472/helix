// Runs on a device or desktop (`flutter test integration_test`): the console
// starts, asks for a server and, against an in-memory fake server, signs in.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the operator console starts at sign-in and signs in', (
    tester,
  ) async {
    final h = AdminHarness()..configured();
    await h.pumpApp(tester);

    expect(find.bySemanticsLabel('Helix Admin'), findsOneWidget);
    await enter(tester, 'Server address', 'helix.test');
    await tapText(tester, 'Continue');
    await enter(tester, 'Admin password', adminPassword);
    await tapText(tester, 'Sign in');

    expect(find.text('Overview'), findsWidgets);
  });
}
