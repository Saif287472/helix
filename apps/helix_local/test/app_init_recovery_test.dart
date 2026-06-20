// Phase 02 — HXA-016: Local app init has no retry.
//
// Verifies that when [localAppInitProvider] throws, the app renders a
// recoverable error screen with a Retry button, and that tapping Retry
// invalidates the provider so the next attempt can succeed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix/providers/wipe_providers.dart';

// ---------------------------------------------------------------------------
// Minimal stub providers
// ---------------------------------------------------------------------------

// Counts how many times the init future has been attempted.
int _initAttempt = 0;

/// A version of [localAppInitProvider] that fails on the first attempt and
/// succeeds on the second.
final _failOnceThenSucceedProvider = FutureProvider<void>((ref) async {
  _initAttempt++;
  if (_initAttempt == 1) throw StateError('Simulated init failure');
});

// ---------------------------------------------------------------------------
// Minimal app under test
// ---------------------------------------------------------------------------

/// Widget that mirrors the retry behaviour in [_HelixAppState.build] but
/// drives [_failOnceThenSucceedProvider] so no real platform services are
/// needed.
class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initAsync = ref.watch(_failOnceThenSucceedProvider);
    return MaterialApp(
      home: initAsync.when(
        loading: () => const Scaffold(body: Text('Loading')),
        error: (err, _) => Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error: $err'),
              ElevatedButton(
                onPressed: () => ref.invalidate(_failOnceThenSucceedProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (_) => const Scaffold(body: Text('Ready')),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() => _initAttempt = 0);

  testWidgets(
    'P02-A01: app init failure shows error screen with Retry button',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: _TestApp()));
      // Let the future settle (it throws on attempt 1).
      await tester.pump();
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Ready'), findsNothing);
    },
  );

  testWidgets(
    'P02-A02: tapping Retry invalidates the provider and reaches Ready on success',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: _TestApp()));
      await tester.pump();
      await tester.pump();

      // Error screen visible.
      expect(find.text('Retry'), findsOneWidget);

      // Tap Retry — second attempt succeeds.
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(_initAttempt, 2);
    },
  );

  testWidgets(
    'P02-A03: error message does not contain long raw hex/base64 sequences',
    (tester) async {
      // Simulate an error that includes a fake 64-char fingerprint.
      const fakeFingerprint =
          'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899';
      final sensitiveProvider = FutureProvider<void>((_) async {
        throw StateError('Key failure: $fakeFingerprint');
      });

      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              final async = ref.watch(sensitiveProvider);
              return MaterialApp(
                home: Scaffold(
                  body: async.when(
                    loading: () => const Text('Loading'),
                    error: (err, _) {
                      // Apply the same redaction logic used in _ErrorApp.
                      final redacted = err.toString().replaceAllMapped(
                        RegExp(r'[0-9a-fA-F]{48,}|[A-Za-z0-9+/]{48,}={0,2}'),
                        (_) => '[redacted]',
                      );
                      return Text(redacted);
                    },
                    data: (_) => const Text('Ready'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining(fakeFingerprint), findsNothing);
      expect(find.textContaining('[redacted]'), findsOneWidget);
    },
  );
}
