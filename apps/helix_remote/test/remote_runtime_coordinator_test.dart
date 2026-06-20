import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_runtime_coordinator.dart';
import 'package:helix_remote/app/remote_sync_gateway.dart';

void main() {
  group('RemoteRuntimeCoordinator', () {
    test(
      'startup sequence validates, catches up, drains, connects, and readies',
      () async {
        final calls = <String>[];
        final coordinator = RemoteRuntimeCoordinator(
          validateSession: () async {
            calls.add('validate');
            return true;
          },
          catchUpInbound: () async {
            calls.add('catch-up');
            return 2;
          },
          refreshSession: () async {
            calls.add('refresh');
          },
          drainOutbox: () async {
            calls.add('drain');
            return 1;
          },
          connectRealtime: () async {
            calls.add('connect');
          },
          disconnectRealtime: () async {
            calls.add('disconnect');
          },
        );
        addTearDown(coordinator.dispose);

        await coordinator.start();

        expect(calls, ['validate', 'refresh', 'catch-up', 'drain', 'connect']);
        expect(coordinator.snapshot.state, RemoteRuntimeState.ready);
        expect(coordinator.snapshot.failedOperationCount, equals(0));
      },
    );

    test('outbound drain is single-flight', () async {
      final release = Completer<void>();
      var drainCalls = 0;
      final coordinator = RemoteRuntimeCoordinator(
        validateSession: () async => true,
        catchUpInbound: () async => 0,
        drainOutbox: () async {
          drainCalls++;
          await release.future;
          return 1;
        },
        connectRealtime: () async {},
        disconnectRealtime: () async {},
      );
      addTearDown(coordinator.dispose);

      final first = coordinator.drainOutbox();
      final second = coordinator.drainOutbox();
      await Future<void>.delayed(Duration.zero);

      expect(drainCalls, equals(1));
      release.complete();
      expect(await first, equals(1));
      expect(await second, equals(1));
    });

    test('dispose cancels scheduled reconnect and closes realtime', () async {
      var disconnects = 0;
      final coordinator = RemoteRuntimeCoordinator(
        validateSession: () async => throw StateError('offline'),
        catchUpInbound: () async => 0,
        drainOutbox: () async => 0,
        connectRealtime: () async {},
        disconnectRealtime: () async {
          disconnects++;
        },
        reconnectBaseDelay: const Duration(milliseconds: 50),
      );

      await coordinator.start();
      expect(coordinator.snapshot.state, RemoteRuntimeState.retryScheduled);

      await coordinator.dispose();
      expect(coordinator.snapshot.state, RemoteRuntimeState.disposed);
      expect(disconnects, equals(1));
    });

    test(
      'network loss moves offline and recovery schedules reconnect',
      () async {
        final coordinator = RemoteRuntimeCoordinator(
          validateSession: () async => true,
          catchUpInbound: () async => 0,
          drainOutbox: () async => 0,
          connectRealtime: () async {},
          disconnectRealtime: () async {},
          reconnectBaseDelay: const Duration(milliseconds: 50),
        );
        addTearDown(coordinator.dispose);

        coordinator.setNetworkAvailable(false);
        expect(coordinator.snapshot.state, RemoteRuntimeState.offline);

        coordinator.setNetworkAvailable(true);
        expect(coordinator.snapshot.state, RemoteRuntimeState.retryScheduled);
        expect(coordinator.snapshot.nextRetryAt, isNotNull);
      },
    );
  });

  group('RemoteOutboundOperationRegistry', () {
    test(
      'known operations are explicitly mapped and unknown operations fail closed',
      () {
        final registry = RemoteOutboundOperationRegistry();

        expect(registry.require('SEND_MESSAGE').path, 'messages/send');
        expect(
          () => registry.require('FUTURE_UNKNOWN_OPERATION'),
          throwsStateError,
        );
        expect(
          registry.knownTypes,
          containsAll(['SEND_MESSAGE', 'CONTACT_REQUEST', 'SAFETY_REPORT']),
        );
      },
    );
  });
}
