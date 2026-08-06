import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

void main() {
  testWidgets(
    'P7 shared controls meet text contrast and Android touch targets',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HelixThemes.light(),
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Continue')),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                  const HelixStatusBadge(label: 'End-to-end encrypted'),
                ],
              ),
            ),
          ),
        ),
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    },
  );

  testWidgets('P7 shared controls remain usable at 2× text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: HelixThemes.light(),
          home: Scaffold(
            body: FilledButton(onPressed: () {}, child: const Text('Continue')),
          ),
        ),
      ),
    );

    expect(find.text('Continue'), findsOneWidget);
  });
}
