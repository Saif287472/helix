import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Backup, drawn by `orbit_ui`'s [orbit.BackupScreen]: the last
/// backup and Back up now, automatic backup and mobile data, moving your
/// history, the recovery backup, and deleting the server copy (the screen
/// asks first). The backup is encrypted on this phone before it leaves.
class BackupPage extends ConsumerWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(backupPageViewProvider);
    final view = page.value;
    if (view == null) {
      return orbit.OrbitYouPage(
        title: 'Backup',
        children: [
          if (page.hasError)
            orbit.OrbitLoadFailed(
              title: 'The backup details could not be loaded.',
              onRetry: () => ref.invalidate(backupSummaryProvider),
            )
          else
            const orbit.OrbitPageLoading(),
        ],
      );
    }
    final run = ref.watch(backupRunProvider);
    ref.listen(backupRunProvider.select((r) => r.finished), (was, now) {
      if (now && !(was ?? false)) {
        orbit.showOrbitToast(context, 'Your history is backed up.');
      }
    });
    final summary = ref.watch(backupSummaryProvider).value;
    final offers = ref.watch(incomingOffersProvider).value ?? const [];
    final actions = ref.read(backupSettingsActionsProvider);
    final failed = run.error ?? view.problem;

    return orbit.BackupScreen(
      model: orbit.BackupModel(
        state: run.running
            ? orbit.BackupState.running
            : failed != null
            ? orbit.BackupState.failed
            : summary?.lastBackupAt == null
            ? orbit.BackupState.never
            : orbit.BackupState.ok,
        lastLabel: view.lastBackup,
        detail: run.running
            ? (run.messages > 0 ? '${run.messages} messages' : '')
            : view.lastBackupDetail ?? '',
        failedReason: failed ?? '',
        daily: view.autoBackup,
        mobileData: ref.watch(backupOverMobileProvider).value ?? false,
        transfersWaiting: offers.length,
        recoveryMade: summary?.lastRecoveryBackupAt != null,
        recoveryLabel: view.recoveryBackup,
      ),
      actions: orbit.BackupActions(
        onBackUp: run.running
            ? null
            : ref.read(backupRunProvider.notifier).backUpNow,
        onDaily: actions.setAutoBackup,
        onMobileData: actions.setOverMobile,
        onRestore: () => context.push(RoutePaths.backupRestore),
        onTransfer: () => context.push(RoutePaths.backupTransfer),
        onRecovery: () => context.push(RoutePaths.backupRecovery),
        onDeleteServerBackup: ref
            .read(backupRunProvider.notifier)
            .deleteServerBackup,
      ),
    );
  }
}
