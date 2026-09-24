import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/screens/server_choice_screen.dart';
import 'package:helix_remote/screens/invite_entry_screen.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';

void main() {
  group('ServerChoiceScreen', () {
    testWidgets('renders first-launch options matching welcome flow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: ServerChoiceScreen(),
        ),
      );

      expect(find.text('Helix Global Server'), findsOneWidget);
      expect(find.text('Others'), findsOneWidget);
      expect(find.text('Continue offline for now'), findsOneWidget);
    });

    testWidgets('continue offline pops a ContinueOfflineChoice', (
      tester,
    ) async {
      Object? popped;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<Object?>(
                  MaterialPageRoute(builder: (_) => const ServerChoiceScreen()),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Continue offline for now'));
      await tester.tap(find.text('Continue offline for now'));
      await tester.pumpAndSettle();

      expect(popped, isA<ContinueOfflineChoice>());
    });

    testWidgets('navigating to Others displays custom server options', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: ServerChoiceScreen(),
        ),
      );

      await tester.ensureVisible(find.text('Others'));
      await tester.tap(find.text('Others'));
      await tester.pumpAndSettle();

      // Tap Continue to enter Others Hub
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Join a personal server'), findsOneWidget);
      expect(find.text('Host your own server'), findsOneWidget);
    });
  });

  group('InviteEntryScreen', () {
    testWidgets('renders code entry step', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: HelixLocalizations.localizationsDelegates,
          supportedLocales: HelixLocalizations.supportedLocales,
          home: InviteEntryScreen(),
        ),
      );

      expect(find.text('Enter invitation or recovery code'), findsOneWidget);
      expect(find.text('Verify & Connect'), findsOneWidget);
    });
  });
}
