// Phase 06 — first-launch server-choice screen and invite entry.
//
// Covers the four tiles rendering, the "continue offline" pop result, and
// invite-link parsing/validation feedback. The Global/Global-invite and
// personal-server invite-lookup network calls are intentionally not
// exercised here (they hit real HTTP), only the offline-safe parsing and
// navigation paths are.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/screens/invite_entry_screen.dart';
import 'package:helix_remote/screens/server_choice_screen.dart';

void main() {
  group('ServerChoiceScreen', () {
    testWidgets('renders all four first-launch options', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ServerChoiceScreen()));

      expect(find.text('Helix Global'), findsOneWidget);
      expect(find.text('Join a personal server'), findsOneWidget);
      expect(find.text('Host your own server'), findsOneWidget);
      expect(find.text('Continue offline'), findsOneWidget);
    });

    testWidgets('continue offline pops a ContinueOfflineChoice', (
      tester,
    ) async {
      Object? popped;
      await tester.pumpWidget(
        MaterialApp(
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

      await tester.ensureVisible(find.text('Continue offline'));
      await tester.tap(find.text('Continue offline'));
      await tester.pumpAndSettle();

      expect(popped, isA<ContinueOfflineChoice>());
    });

    testWidgets('host your own opens an informational screen with a way back', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ServerChoiceScreen()));

      await tester.ensureVisible(find.text('Host your own server'));
      await tester.tap(find.text('Host your own server'));
      await tester.pumpAndSettle();

      expect(find.text('Run your own Helix Remote server'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);

      await tester.ensureVisible(find.text('Back'));
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Helix Remote'), findsOneWidget);
    });

    testWidgets('join a personal server navigates to InviteEntryScreen', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ServerChoiceScreen()));

      await tester.ensureVisible(find.text('Join a personal server'));
      await tester.tap(find.text('Join a personal server'));
      await tester.pumpAndSettle();

      expect(find.byType(InviteEntryScreen), findsOneWidget);
    });
  });

  group('InviteEntryScreen', () {
    testWidgets(
      'rejects a link missing an invite code without any network call',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: InviteEntryScreen()));

        await tester.enterText(
          find.byType(TextField).first,
          'https://server.example/join',
        );
        await tester.tap(find.text('Continue'));
        await tester.pump();

        expect(
          find.textContaining('Paste the full link your admin shared'),
          findsOneWidget,
        );
      },
    );

    testWidgets('rejects an empty field', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: InviteEntryScreen()));

      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(
        find.textContaining('Paste the full link your admin shared'),
        findsOneWidget,
      );
    });
  });
}
