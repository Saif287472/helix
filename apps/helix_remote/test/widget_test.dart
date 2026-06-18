import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/main.dart';

void main() {
  testWidgets('HelixRemoteApp placeholder launch smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HelixRemoteApp());
    expect(find.text('Helix Remote Placeholder'), findsOneWidget);
  });
}
