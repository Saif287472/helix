import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/engine_lease.dart';
import 'package:helix_remote/shared/widgets/reset_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'support/orbit_theme.dart';

/// The screen the app falls back to when it cannot open its own data.
///
/// What it may offer is the whole point: a destructive reset deletes the
/// database and the key and is not recoverable, so it must never be offered
/// because of an error that has not been shown to be permanent, and it must
/// never be offered with wording that guesses at a cause.
void main() {
  /// What the app is currently failing with. A retry re-reads the startup and
  /// comes back with a fresh failure, so the fake is re-read the same way.
  Object? failure;
  late ProviderContainer container;

  Future<void> show(WidgetTester tester, Object error) async {
    failure = error;
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream<AppAuthState>.error(failure!),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: orbitTestTheme(),
          builder: orbitTestBuilder,
          home: const ResetScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  /// The retry came back and failed again, with a new error.
  Future<void> failsAgain(WidgetTester tester, Object error) async {
    failure = error;
    container.invalidate(authStateProvider);
    await settle(tester);
  }

  final resetButton = find.text('Reset Orbit');

  group('a key that is gone or wrong', () {
    resetTest('is offered the reset at once, and says what is lost', (
      tester,
    ) async {
      await show(tester, const KeyUnavailable());

      // The bar's title and the page's.
      expect(find.text('Reset required'), findsNWidgets(2));
      expect(find.textContaining('encryption key is not'), findsOneWidget);
      expect(resetButton, findsOneWidget);
      // Retrying cannot help a missing key, so it is not offered.
      expect(find.text('Try again'), findsNothing);
    });

    resetTest('a database that cannot be decrypted says so', (tester) async {
      await show(
        tester,
        const DbEncryptionException('the database does not decrypt'),
      );

      // The bar's title and the page's.
      expect(find.text('Reset required'), findsNWidgets(2));
      expect(find.textContaining('could not be decrypted'), findsOneWidget);
      expect(resetButton, findsOneWidget);
    });
  });

  group('another window holding the database', () {
    resetTest('is a retry, and never a reset', (tester) async {
      await show(
        tester,
        const EngineAlreadyRunning(byRole: LeaseRole.foreground),
      );

      expect(find.text('Try again'), findsOneWidget);
      expect(resetButton, findsNothing);
      expect(find.textContaining('decrypt'), findsNothing);
    });
  });

  group('an error we cannot name', () {
    resetTest('says only that Helix could not start', (tester) async {
      // A passing error: a file that would not lock, a platform channel that
      // was not ready yet, a schema step that would not run.
      await show(tester, StateError('the file could not be locked'));

      expect(find.text('Orbit could not start'), findsOneWidget);
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    resetTest('never claims the data could not be decrypted', (tester) async {
      await show(tester, StateError('the file could not be locked'));

      // The old screen said this for every error, which told the person their
      // messages were unreadable when nobody knows that.
      expect(find.textContaining('decrypt'), findsNothing);
      expect(find.text('Reset required'), findsNothing);
      expect(resetButton, findsNothing);
    });

    resetTest('offers no reset until a retry has failed as well', (
      tester,
    ) async {
      await show(tester, StateError('the file could not be locked'));

      expect(resetButton, findsNothing);
      expect(find.text('Type DELETE to confirm'), findsNothing);

      await tester.tap(find.text('Try again'));
      await settle(tester);

      // The retry was asked for, but nothing has come back yet: still no way
      // to delete anything.
      expect(resetButton, findsNothing);

      await failsAgain(tester, StateError('the file could not be locked'));
      expect(resetButton, findsOneWidget);
      expect(
        find.textContaining('Every message and key stored here'),
        findsOneWidget,
      );
    });

    resetTest('a startup that works shows the data is fine', (tester) async {
      await show(tester, StateError('the file could not be locked'));
      expect(find.text('Orbit could not start'), findsOneWidget);

      final healthy = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<AppAuthState>.value(AppAuthState.signedOut),
          ),
        ],
      );
      addTearDown(healthy.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: healthy,
          child: MaterialApp(
            theme: orbitTestTheme(),
            builder: orbitTestBuilder,
            home: const ResetScreen(),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Your local data is fine'), findsOneWidget);
      expect(resetButton, findsNothing);
    });
  });
}

/// A test that takes the app down afterwards: the typed confirmation is a text
/// field, and its cursor keeps a timer alive past the end of the tree.
void resetTest(String name, Future<void> Function(WidgetTester tester) body) =>
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

/// Lets the stream provider really re-read before the next frame.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}
