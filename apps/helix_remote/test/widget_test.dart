import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/main.dart';
import 'package:helix_remote/app/composition_root.dart';

void main() {
  testWidgets('HelixRemoteApp placeholder launch smoke test', (WidgetTester tester) async {
    final root = RemoteCompositionRoot.production();
    await tester.pumpWidget(HelixRemoteApp(root: root));
    expect(find.text('Helix Remote Placeholder'), findsOneWidget);
  });
}
