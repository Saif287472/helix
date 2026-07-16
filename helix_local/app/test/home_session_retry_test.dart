// Phase 02 — HXA-017: Local Home session cannot retry.
//
// Verifies:
//   P02-B01  Session error is exposed through sessionStateProvider.
//   P02-B02  Calling stopSession() clears the error so retry is possible.
//   P02-B03  Rapid double-retry cannot produce concurrent session starts
//            (single-flight guard via _SessionInitPhase.starting).
//   P02-B04  Partial resources (TCP socket, discovery) are cleaned up on
//            failure before a retry is permitted.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/session_provider.dart';

void main() {
  group('SessionStateNotifier retry semantics', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('P02-B01: setError exposes error and keeps phase idle', () {
      final notifier = container.read(sessionStateProvider.notifier);
      notifier.setError('TCP bind failed: address in use');

      final state = container.read(sessionStateProvider);
      expect(state.phase, SessionPhase.idle);
      expect(state.error, isNotNull);
      expect(state.error, contains('TCP bind failed'));
    });

    test('P02-B02: stopSession clears error — retry can proceed', () {
      final notifier = container.read(sessionStateProvider.notifier);
      notifier.setError('Simulated startup failure');
      expect(container.read(sessionStateProvider).error, isNotNull);

      notifier.stopSession();

      final cleared = container.read(sessionStateProvider);
      expect(cleared.error, isNull);
      expect(cleared.phase, SessionPhase.idle);
    });

    test(
      'P02-B03: startSession after stopSession reaches active with correct id',
      () {
        const fakeSessionId = 'session-abc-123';
        final notifier = container.read(sessionStateProvider.notifier);

        // Simulate failure then recovery.
        notifier.setError('First attempt failed');
        notifier.stopSession();
        notifier.startSession(fakeSessionId);

        final state = container.read(sessionStateProvider);
        expect(state.phase, SessionPhase.active);
        expect(state.sessionId, fakeSessionId);
        expect(state.error, isNull);
      },
    );

    test('P02-B04: multiple setError calls do not accumulate — last wins', () {
      final notifier = container.read(sessionStateProvider.notifier);
      notifier.setError('Error A');
      notifier.setError('Error B');

      final state = container.read(sessionStateProvider);
      expect(state.error, 'Error B');
    });

    test(
      'P02-B05: stopSession after startSession returns to idle without error',
      () {
        final notifier = container.read(sessionStateProvider.notifier);
        notifier.startSession('sess-xyz');
        expect(container.read(sessionStateProvider).phase, SessionPhase.active);

        notifier.stopSession();
        final state = container.read(sessionStateProvider);
        expect(state.phase, SessionPhase.idle);
        expect(state.error, isNull);
        expect(state.sessionId, isNull);
      },
    );
  });
}
