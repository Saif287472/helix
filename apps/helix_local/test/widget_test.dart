import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix/app.dart';

void main() {
  testWidgets('HelixApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: HelixApp()));
    // App builds without throwing
    expect(find.byType(ProviderScope), findsOneWidget);
  });
}
