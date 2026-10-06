import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Backup.
///
/// What is on this page is what the engine can do and no more: an automatic
/// daily backup of the history, a manual "back up now", and the two ways of
/// getting history onto another phone (restore from the backup, or send it
/// device to device). The schedule is fixed at once a day by the engine, so it
/// is stated rather than offered as a choice.
class BackupPage extends ConsumerWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(backupPageViewProvider);
    final run = ref.watch(backupRunProvider);
    final overMobile = ref.watch(backupOverMobileProvider).value ?? false;
    final offers = ref.watch(incomingOffersProvider).value ?? const [];
    final waiting = offers.where((o) => !o.isFinished).length;
    final actions = ref.read(backupSettingsActionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: switch (view) {
        AsyncError() => HelixErrorState(
          message: 'The backup settings could not be loaded.',
          onRetry: () => ref.invalidate(backupSummaryProvider),
        ),
        AsyncData(:final value) => ListView(
          children: [
            const PageIntro(
              text:
                  'Your backup holds your chats and messages, with references '
                  'to photos, videos and files but not the files themselves. '
                  'It is encrypted with a key only your devices have, so '
                  'Helix cannot read it. Messages that were never sent and '
                  'view-once messages are left out.',
            ),
            if (value.problem != null)
              InlineNotice(
                kind: InlineNoticeKind.error,
                message: 'The last backup did not finish. ${value.problem}',
              ),
            HelixSettingsSection(
              title: 'Chat history backup',
              footer:
                  'Runs once a day while Helix is open, and when a new '
                  'device joins your account.',
              children: [
                HelixSettingsSwitchTile(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Back up automatically',
                  value: value.autoBackup,
                  onChanged: (on) => actions.setAutoBackup(on),
                ),
                HelixSettingsSwitchTile(
                  icon: Icons.signal_cellular_alt,
                  title: 'Use mobile data',
                  subtitle: 'Otherwise backups wait for Wi-Fi',
                  value: overMobile,
                  onChanged: (on) => actions.setOverMobile(on),
                ),
                HelixSettingsTile(
                  icon: Icons.history,
                  title: 'Last backup',
                  subtitle: value.lastBackupDetail == null
                      ? value.lastBackup
                      : '${value.lastBackup}. ${value.lastBackupDetail}',
                ),
              ],
            ),
            if (run.running)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HelixSpace.md,
                  vertical: HelixSpace.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      run.messages > 0
                          ? 'Backing up... ${run.messages} messages'
                          : 'Backing up...',
                    ),
                    const SizedBox(height: HelixSpace.xs),
                    const LinearProgressIndicator(),
                  ],
                ),
              ),
            if (run.error != null)
              InlineNotice(kind: InlineNoticeKind.error, message: run.error!),
            if (run.finished)
              InlineNotice(
                kind: InlineNoticeKind.success,
                message: run.skipped
                    ? 'There is no history to back up yet.'
                    : 'Your history is backed up.',
              ),
            BusyFilledButton(
              label: 'Back up now',
              icon: Icons.backup_outlined,
              busy: run.running,
              onPressed: () => ref.read(backupRunProvider.notifier).backUpNow(),
            ),
            HelixSettingsSection(
              title: 'Get your history on another phone',
              children: [
                HelixSettingsTile(
                  icon: Icons.download_for_offline_outlined,
                  title: 'Restore history',
                  subtitle: 'Add the messages from your backup to this phone',
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.backupRestore),
                ),
                HelixSettingsTile(
                  icon: Icons.devices_other_outlined,
                  title: 'Send to my other devices',
                  subtitle: waiting > 0
                      ? '$waiting waiting to be received'
                      : 'Copy this phone\'s history straight to another device',
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.backupTransfer),
                ),
              ],
            ),
            HelixSettingsSection(
              title: 'Recovery backup',
              footer:
                  'A second backup, locked with a secret that only you hold. '
                  'It lets you bring your chats back on a new phone even if '
                  'you have no other device. Helix cannot recover the secret '
                  'if you lose it.',
              children: [
                HelixSettingsTile(
                  icon: Icons.key_outlined,
                  title: 'Recovery backup',
                  subtitle: value.recoveryBackup,
                  showChevron: true,
                  onTap: () => context.push(RoutePaths.backupRecovery),
                ),
              ],
            ),
            HelixSettingsSection(
              footer:
                  'Deleting removes the copy on the server. The messages on '
                  'your devices stay.',
              children: [
                HelixSettingsTile(
                  icon: Icons.delete_outline,
                  title: 'Delete my server backup',
                  destructive: true,
                  onTap: () => _confirmDelete(context, ref),
                ),
              ],
            ),
            const SizedBox(height: HelixSpace.lg),
          ],
        ),
        _ => const HelixAsyncPanel(loading: true, child: SizedBox.shrink()),
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showHelixConfirmDialog(
      context,
      title: 'Delete the server backup?',
      message:
          'The copy of your history on the server will be removed. A new '
          'phone will not be able to restore from it until you back up again. '
          'Your messages on your devices are not touched.',
      confirmLabel: 'Delete',
    );
    if (confirmed) {
      await ref.read(backupRunProvider.notifier).deleteServerBackup();
    }
  }
}
