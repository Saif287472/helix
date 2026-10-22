import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/backup/application/backup_copy.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Connector: Settings > Backup > Recovery backup, drawn by `orbit_ui`'s
/// [RecoveryScreen].
///
/// A recovery backup is sealed under a secret that only the person holds, so
/// chats can come back on a new phone with no other device to copy from. The
/// secret is made by the engine (random, not chosen: a chosen phrase can be
/// guessed offline by anyone who gets the stored backup) and shown once, here,
/// with Copy and Share to put it somewhere safe. It is never stored, sent or
/// logged by the app, and it is gone from this phone once the backup is made.
/// Helix cannot recover it, and the page says so.
class RecoveryBackupPage extends ConsumerWidget {
  const RecoveryBackupPage({super.key, this.initialTab = RecoveryTab.create});

  /// Restore history opens it on Restore ("I have a recovery secret").
  final RecoveryTab initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recoveryBackupProvider);
    final controller = ref.read(recoveryBackupProvider.notifier);
    final backup = ref.watch(backupPageViewProvider).value;

    return RecoveryScreen(
      model: recoveryModel(
        state,
        initialTab: initialTab,
        made: backup != null && backup.recoveryBackup != 'Not made',
        madeLabel: backup != null && backup.recoveryBackup != 'Not made'
            ? 'Made ${backup.recoveryBackup.toLowerCase()}'
            : 'Made today',
      ),
      actions: RecoveryActions(
        onCopy: controller.copy,
        onShare: controller.share,
        onSaved: controller.setWritten,
        onCreate: controller.create,
        onRestore: controller.restore,
        onDelete: controller.deleteBackup,
      ),
    );
  }
}

/// The screen's model for [state] (`orbit/contracts/devices_backup.md`,
/// Recovery backup).
@visibleForTesting
RecoveryModel recoveryModel(
  RecoveryBackupState state, {
  required RecoveryTab initialTab,
  required bool made,
  required String madeLabel,
}) {
  final restored = state.restored;
  return RecoveryModel(
    secret: state.secret,
    initialTab: initialTab,
    made: made,
    madeLabel: madeLabel,
    created: state.stage == RecoveryStage.created,
    createdNothing: state.created?.skipped ?? false,
    restored: restored == null
        ? null
        : restored.added == 0
        ? 'The backup is already on this phone.'
        : 'Restored ${messageCount(restored.added)} messages.',
    handoffNote: state.handoffNote,
    error: state.error,
    busy: state.busy,
    saved: state.written,
  );
}
