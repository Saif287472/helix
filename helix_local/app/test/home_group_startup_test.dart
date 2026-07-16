// Phase 02 — HXA-018: Local public-lobby failure invisible.
//
// Verifies:
//   P02-C01  lobbyInitErrorProvider starts null.
//   P02-C02  Writing an error to lobbyInitErrorProvider makes it visible.
//   P02-C03  Clearing the provider (simulating successful retry) resets to null.
//   P02-C04  Multiple lobby failures overwrite — only the latest error is held.
//   P02-C05  Lobby error is independent of sessionStateProvider (DM health).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/groups_providers.dart';
import 'package:helix/providers/session_provider.dart';

void main() {
  group('lobbyInitErrorProvider semantics', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('P02-C01: starts null — no lobby error at boot', () {
      expect(container.read(lobbyInitErrorProvider), isNull);
    });

    test('P02-C02: writing an error makes it visible to watchers', () {
      container.read(lobbyInitErrorProvider.notifier).state =
          'Multicast socket bind failed';

      expect(
        container.read(lobbyInitErrorProvider),
        'Multicast socket bind failed',
      );
    });

    test('P02-C03: clearing the provider simulates a successful retry', () {
      container.read(lobbyInitErrorProvider.notifier).state = 'Init error';
      expect(container.read(lobbyInitErrorProvider), isNotNull);

      // Simulate successful retry: clear the error.
      container.read(lobbyInitErrorProvider.notifier).state = null;

      expect(container.read(lobbyInitErrorProvider), isNull);
    });

    test(
      'P02-C04: successive failures overwrite — only latest is retained',
      () {
        final notifier = container.read(lobbyInitErrorProvider.notifier);
        notifier.state = 'Error A';
        notifier.state = 'Error B';

        expect(container.read(lobbyInitErrorProvider), 'Error B');
      },
    );

    test('P02-C05: lobby error and session error are independent', () {
      // Set lobby error.
      container.read(lobbyInitErrorProvider.notifier).state = 'Lobby down';

      // Session stays healthy.
      container.read(sessionStateProvider.notifier).startSession('sess-ok');

      expect(container.read(lobbyInitErrorProvider), isNotNull);
      expect(container.read(sessionStateProvider).phase, SessionPhase.active);
      expect(container.read(sessionStateProvider).error, isNull);
    });

    test('P02-C06: clearing lobby error does not affect session state', () {
      container.read(sessionStateProvider.notifier).startSession('sess-ok');
      container.read(lobbyInitErrorProvider.notifier).state = 'Lobby down';

      // Lobby retry succeeds.
      container.read(lobbyInitErrorProvider.notifier).state = null;

      expect(container.read(lobbyInitErrorProvider), isNull);
      expect(container.read(sessionStateProvider).phase, SessionPhase.active);
    });
  });
}
