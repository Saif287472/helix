import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/main.dart';

void main() {
  testWidgets('Helix Admin login screen renders successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const HelixAdminApp());

    // Verify login title and buttons exist
    expect(find.text('HELIX SERVER ADMIN'), findsOneWidget);
    expect(find.text('AUTHENTICATE'), findsOneWidget);

    // Verify inputs exist
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
