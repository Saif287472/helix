import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';

import '../support/a3b_fakes.dart';

/// Backup flows that outlive their page, and the state they keep (B17).
void main() {
  /// Leaving the page while the engine works disposes its controller; the
  /// engine call goes on, and its answer used to write `state` on a notifier
  /// that was gone (AUD-15-6).
  group('a page left mid-flow', () {
    test('the restore flow writes nothing and throws nothing', () async {
      final backup = FakeBackupGateway()..holdRestore = Completer<void>();
      final container = ProviderContainer(
        overrides: a3bOverrides(backup: backup),
      );
      addTearDown(container.dispose);
      final page = container.listen(restoreFlowProvider, (_, _) {});
      final running = container.read(restoreFlowProvider.notifier).restore();
      await Future<void>.delayed(Duration.zero);

      page.close(); // the person pressed Back
      await Future<void>.delayed(Duration.zero);
      backup.holdRestore!.complete();
      await running; // an UnmountedRefException would end here
    });

    test('and so does the recovery backup, failing or not', () async {
      for (final fails in [null, BackupProblem.offline]) {
        final backup = FakeBackupGateway()..recoveryRestoreFails = fails;
        final container = ProviderContainer(
          overrides: a3bOverrides(backup: backup),
        );
        addTearDown(container.dispose);
        final page = container.listen(recoveryBackupProvider, (_, _) {});
        final restoring = container
            .read(recoveryBackupProvider.notifier)
            .restore('some secret');
        page.close();
        await restoring;
      }
    });
  });

  test('a resumed transfer sheds its old problem (AUD-15-8)', () {
    const failed = TransferView(
      id: 't',
      direction: TransferDirection.sending,
      stage: TransferStage.failed,
      problem: BackupProblem.offline,
    );
    expect(failed.copyWith(stage: TransferStage.offered).problem, isNotNull);
    expect(
      failed.copyWith(stage: TransferStage.offered, clearProblem: true).problem,
      isNull,
    );
  });

  test('a backup from an earlier key is a restore that says so '
      '(AUD-12q-3)', () async {
    const outcome = RestoreOutcome(added: 40, existing: 2);
    expect(outcome.earlierKey, isFalse);
    final marked = outcome.withEarlierKey();
    expect(marked.earlierKey, isTrue);
    expect((marked.added, marked.existing), (40, 2));

    final backup = FakeBackupGateway()..restoreOutcome = marked;
    final container = ProviderContainer(
      overrides: a3bOverrides(backup: backup),
    );
    addTearDown(container.dispose);
    final page = container.listen(recoveryBackupProvider, (_, _) {});
    addTearDown(page.close);
    await container.read(recoveryBackupProvider.notifier).restore('secret');
    final state = container.read(recoveryBackupProvider);
    expect(state.stage, RecoveryStage.restored);
    expect(state.restored!.earlierKey, isTrue);
    expect(state.error, isNull);
  });
}
