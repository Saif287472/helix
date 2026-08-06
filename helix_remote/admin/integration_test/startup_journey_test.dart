import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P8 integration: operator console starts with an accessible shell', (
    tester,
  ) async {
    await tester.pumpWidget(const HelixAdminApp());
    await tester.pump();

    expect(find.bySemanticsLabel('Helix Admin'), findsOneWidget);
  });
}
