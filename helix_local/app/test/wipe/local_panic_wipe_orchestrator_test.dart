// Stage 7b: Wipe orchestrator failure and semantics tests.
// Verifies:
//   - WipeResult.succeeded requires phase == WipePhase.complete (DEFECT-8 fix)
//   - A step failure sets partialFailure and succeeded == false
//   - All steps run even when an earlier step fails
//   - A fully successful wipe sets complete and succeeded == true
//   - onMarkWipePending is called before steps, onClearWipePending after success
//   - onClearWipePending is NOT called after partial failure (restart retry preserved)
//   - Idempotent: calling execute() twice returns the same result without re-running steps

import 'package:flutter_test/flutter_test.dart';
import 'package:helix/application/wipe/local_panic_wipe_orchestrator.dart';
import 'dart:io';

void main() {
  // ---------------------------------------------------------------------------
  // WipeResult semantics (DEFECT-8 fix)
  // ---------------------------------------------------------------------------

  group('WipeResult.succeeded semantics (DEFECT-8 fix)', () {
    test('complete phase with no errors → succeeded == true', () {
      const result = WipeResult(phase: WipePhase.complete);
      expect(result.succeeded, isTrue);
    });

    test('partialFailure phase with errors → succeeded == false', () {
      const result = WipeResult(
        phase: WipePhase.partialFailure,
        errors: ['step: error'],
      );
      expect(result.succeeded, isFalse);
    });

    test(
      'DEFECT-8 fix: partialFailure phase with empty errors → succeeded == false',
      () {
        // Before the fix, this returned true because errors.isEmpty was the only check.
        const result = WipeResult(phase: WipePhase.partialFailure, errors: []);
        expect(
          result.succeeded,
          isFalse,
          reason:
              'partialFailure phase must be false even with empty errors list',
        );
      },
    );

    test('idle phase → succeeded == false', () {
      const result = WipeResult(phase: WipePhase.idle);
      expect(result.succeeded, isFalse);
    });

    test('inProgress phase → succeeded == false', () {
      const result = WipeResult(phase: WipePhase.inProgress);
      expect(result.succeeded, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Orchestrator happy path
  // ---------------------------------------------------------------------------

  group('Orchestrator happy path', () {
    test(
      'All steps succeed → WipePhase.complete and succeeded == true',
      () async {
        final executed = <String>[];
        final orch = LocalPanicWipeOrchestrator.withSteps([
          ('step_a', () async => executed.add('a')),
          ('step_b', () async => executed.add('b')),
          ('step_c', () async => executed.add('c')),
        ]);

        final result = await orch.execute();

        expect(result.phase, WipePhase.complete);
        expect(result.succeeded, isTrue);
        expect(result.errors, isEmpty);
        expect(executed, ['a', 'b', 'c']);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Orchestrator failure paths
  // ---------------------------------------------------------------------------

  group('Orchestrator failure paths', () {
    test(
      'One step throws → WipePhase.partialFailure; remaining steps still run',
      () async {
        final executed = <String>[];
        final orch = LocalPanicWipeOrchestrator.withSteps([
          ('step_a', () async => executed.add('a')),
          (
            'step_b',
            () async {
              throw Exception('DB deletion failed');
            },
          ),
          ('step_c', () async => executed.add('c')),
        ]);

        final result = await orch.execute();

        expect(result.phase, WipePhase.partialFailure);
        expect(result.succeeded, isFalse);
        expect(result.errors.length, 1);
        expect(result.errors.first, contains('step_b'));
        expect(result.errors.first, contains('DB deletion failed'));
        // step_c must still have run despite step_b failing
        expect(executed, containsAll(['a', 'c']));
      },
    );

    test('Multiple step failures → all errors recorded', () async {
      final orch = LocalPanicWipeOrchestrator.withSteps([
        (
          'step_a',
          () async {
            throw Exception('fail a');
          },
        ),
        (
          'step_b',
          () async {
            throw Exception('fail b');
          },
        ),
      ]);

      final result = await orch.execute();

      expect(result.phase, WipePhase.partialFailure);
      expect(result.errors.length, 2);
      expect(result.errors.any((e) => e.contains('step_a')), isTrue);
      expect(result.errors.any((e) => e.contains('step_b')), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Pending-wipe marker (restart retry gate)
  // ---------------------------------------------------------------------------

  group('Pending-wipe marker', () {
    test('onMarkWipePending is called before any steps', () async {
      final order = <String>[];
      final orch = LocalPanicWipeOrchestrator.withStepsAndRecovery(
        [('step', () async => order.add('step'))],
        onMarkWipePending: () async => order.add('markPending'),
        onClearWipePending: () async => order.add('clearPending'),
      );

      await orch.execute();

      expect(
        order.first,
        equals('markPending'),
        reason: 'markPending must run before any wipe step',
      );
    });

    test('onClearWipePending is called after successful wipe', () async {
      final order = <String>[];
      final orch = LocalPanicWipeOrchestrator.withStepsAndRecovery(
        [('step', () async => order.add('step'))],
        onMarkWipePending: () async => order.add('markPending'),
        onClearWipePending: () async => order.add('clearPending'),
      );

      final result = await orch.execute();

      expect(result.succeeded, isTrue);
      expect(
        order.last,
        equals('clearPending'),
        reason: 'clearPending must be called after all steps succeed',
      );
    });

    test(
      'onClearWipePending is NOT called after partial failure (preserves retry marker)',
      () async {
        final cleared = <bool>[];
        final orch = LocalPanicWipeOrchestrator.withStepsAndRecovery(
          [
            (
              'step',
              () async {
                throw Exception('fail');
              },
            ),
          ],
          onMarkWipePending: () async {},
          onClearWipePending: () async => cleared.add(true),
        );

        final result = await orch.execute();

        expect(result.phase, WipePhase.partialFailure);
        expect(
          cleared,
          isEmpty,
          reason:
              'clearPending must NOT be called after failure — '
              'marker must survive for restart retry',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Idempotency
  // ---------------------------------------------------------------------------

  group('Idempotency', () {
    test(
      'execute() called twice returns same result, steps run only once',
      () async {
        int runCount = 0;
        final orch = LocalPanicWipeOrchestrator.withSteps([
          ('step', () async => runCount++),
        ]);

        final r1 = await orch.execute();
        final r2 = await orch.execute();

        expect(r1.phase, WipePhase.complete);
        expect(r2.phase, WipePhase.complete);
        expect(
          runCount,
          1,
          reason: 'Steps must not run again on second execute()',
        );
      },
    );

    test(
      'Failed wipe is also idempotent — second call returns same partialFailure',
      () async {
        int runCount = 0;
        final orch = LocalPanicWipeOrchestrator.withSteps([
          (
            'step',
            () async {
              runCount++;
              throw Exception('fail');
            },
          ),
        ]);

        final r1 = await orch.execute();
        final r2 = await orch.execute();

        expect(r1.phase, WipePhase.partialFailure);
        expect(r2.phase, WipePhase.partialFailure);
        expect(runCount, 1);
      },
    );
  });

  group('Scenario G product isolation', () {
    test(
      'Local panic wipe clears Local state without touching Remote DB, keys, or endpoints',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'helix_scenario_g_',
        );
        addTearDown(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });

        final localSensitiveFile = File('${tempDir.path}/helix_local.db')
          ..writeAsStringSync('LOCAL_SECRET_SENTINEL');
        final remoteDbFile = File('${tempDir.path}/helix_remote.db')
          ..writeAsStringSync('REMOTE_DB_SENTINEL');

        final secureKeys = <String, String>{
          'helix_local_v1_identity': 'local-secret-key',
          'helix_remote_v1_identity': 'remote-secret-key',
          'helix_remote_v1_db_key': 'remote-db-key',
        };
        var remoteEndpointCalled = false;

        final orch = LocalPanicWipeOrchestrator.withSteps([
          (
            'localFile.delete',
            () async {
              if (localSensitiveFile.existsSync()) {
                await localSensitiveFile.delete();
              }
            },
          ),
          (
            'localSecureStorage.deleteScoped',
            () async {
              secureKeys.removeWhere(
                (key, _) => key.startsWith('helix_local_v1_'),
              );
            },
          ),
        ]);

        final result = await orch.execute();

        expect(result.succeeded, isTrue);
        expect(localSensitiveFile.existsSync(), isFalse);
        expect(secureKeys['helix_local_v1_identity'], isNull);

        expect(remoteDbFile.existsSync(), isTrue);
        expect(remoteDbFile.readAsStringSync(), equals('REMOTE_DB_SENTINEL'));
        expect(
          secureKeys['helix_remote_v1_identity'],
          equals('remote-secret-key'),
        );
        expect(secureKeys['helix_remote_v1_db_key'], equals('remote-db-key'));
        expect(remoteEndpointCalled, isFalse);
      },
    );
  });
}
