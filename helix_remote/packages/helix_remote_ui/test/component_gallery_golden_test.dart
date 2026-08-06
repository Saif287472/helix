import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

void main() {
  testWidgets(
    'P8 component gallery matches its approved light-theme baseline',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HelixThemes.light(),
          home: Scaffold(
            body: ListView(
              padding: HelixInsets.all(HelixSpace.md),
              children: const [
                HelixStatusBadge(label: 'End-to-end encrypted'),
                SizedBox(height: HelixSpace.md),
                HelixSkeleton(height: 24),
                SizedBox(height: HelixSpace.md),
                HelixErrorState(message: 'The server is unavailable.'),
                SizedBox(height: HelixSpace.md),
                HelixEmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No conversations yet',
                  message: 'Start a secure conversation with a contact.',
                ),
              ],
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/component_gallery_light.png'),
      );
    },
  );
}
