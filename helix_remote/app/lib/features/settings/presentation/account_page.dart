import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/account_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Account.
///
/// Shows who this device is signed in as (the phone number is masked, never
/// shown in full), then the things that change the account: the password,
/// exporting what the server holds, signing out and deleting the account.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(accountOverviewProvider);
    final passwordSubtitle = ref.watch(passwordSubtitleProvider);
    final action = ref.watch(accountActionsProvider);
    final actions = ref.read(accountActionsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        children: [
          if (action.busy) const LinearProgressIndicator(),
          if (action.error != null)
            InlineNotice(kind: InlineNoticeKind.error, message: action.error!),
          if (action.notice != null) InlineNotice(message: action.notice!),
          switch (overview) {
            AsyncData(:final value) => HelixSettingsSection(
              title: 'You',
              children: [
                HelixSettingsTile(
                  icon: Icons.phone_outlined,
                  title: value.phoneMasked ?? 'Phone number hidden',
                  subtitle: 'Your number is shown here only in part',
                ),
                if (value.helixName != null)
                  HelixSettingsTile(
                    icon: Icons.alternate_email,
                    title: '~${value.helixName}',
                    subtitle: 'Your ~Helix name',
                    showChevron: true,
                    onTap: () => context.push(RoutePaths.profile),
                  ),
              ],
            ),
            AsyncError() => InlineNotice(
              kind: InlineNoticeKind.error,
              message:
                  'Your account details could not be loaded. You may be '
                  'offline.',
              action: TextButton(
                onPressed: () => ref.invalidate(accountOverviewProvider),
                child: const Text('Try again'),
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(HelixSpace.md),
              child: LinearProgressIndicator(),
            ),
          },
          HelixSettingsSection(
            title: 'Sign-in',
            footer:
                'Your password never leaves this phone. It unlocks your '
                'account on a new phone; Helix cannot read it or reset it. '
                'If you forget it, you can still sign in with a code sent to '
                'your number, which moves your account to the new phone and '
                'signs your other devices out.',
            children: [
              HelixSettingsTile(
                icon: Icons.password_outlined,
                title: overview.value?.hasPassword ?? false
                    ? 'Change password'
                    : 'Set a password',
                subtitle: passwordSubtitle,
                showChevron: true,
                onTap: () => context.push(RoutePaths.changePassword),
              ),
              HelixSettingsTile(
                icon: Icons.history,
                title: 'Security activity',
                subtitle: 'Sign-ins, new devices and key changes',
                showChevron: true,
                onTap: () => context.push(RoutePaths.devicesActivity),
              ),
            ],
          ),
          HelixSettingsSection(
            title: 'Your data',
            footer:
                'The export holds what the Helix server keeps about your '
                'account: your devices, settings and activity. It holds no '
                'messages, because the server never has any it can read.',
            children: [
              HelixSettingsTile(
                icon: Icons.file_download_outlined,
                title: 'Export my data',
                subtitle: 'Save a copy of what the server holds',
                onTap: action.busy ? null : actions.exportData,
              ),
            ],
          ),
          HelixSettingsSection(
            footer:
                'Signing out deletes this phone\'s messages, keys and '
                'history. There is no way to keep them: a phone that kept '
                'its keys could sign itself back in.',
            children: [
              HelixSettingsTile(
                icon: Icons.logout,
                title: 'Sign out',
                subtitle: 'Removes this device from your account',
                destructive: true,
                onTap: action.busy
                    ? null
                    : () => _confirmSignOut(context, actions),
              ),
            ],
          ),
          HelixSettingsSection(
            footer:
                'Deleting your account removes it, your devices and your '
                'profile from the server for good. It cannot be undone.',
            children: [
              HelixSettingsTile(
                icon: Icons.delete_forever_outlined,
                title: 'Delete my account',
                destructive: true,
                onTap: action.busy
                    ? null
                    : () => _confirmDelete(context, ref, actions),
              ),
            ],
          ),
          const SizedBox(height: HelixSpace.lg),
        ],
      ),
    );
  }

  /// Sign out is destructive and permanent, so it is confirmed, not done on
  /// the tap.
  Future<void> _confirmSignOut(
    BuildContext context,
    AccountActions actions,
  ) async {
    final ok = await showHelixDestructiveDialog(
      context,
      title: 'Sign out?',
      message:
          'This removes Helix from this phone and deletes its messages, '
          'keys and history. Your other devices stay signed in.',
      action: 'Sign out',
    );
    if (ok) await actions.signOut();
  }

  /// Deleting is the one action that cannot be undone, so it takes three
  /// steps: an offer to export first, a warning, and then the page that asks
  /// for DELETE and proof that this is the account's owner.
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AccountActions actions,
  ) async {
    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your account, devices and profile will be removed from the server '
          'and this phone will be wiped. People you chatted with keep their '
          'own copies of the messages. You cannot undo this.\n\n'
          'Want a copy of your account data first?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _DeleteChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _DeleteChoice.export),
            child: const Text('Export first'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, _DeleteChoice.go),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (choice == null || choice == _DeleteChoice.cancel) return;
    if (choice == _DeleteChoice.export) {
      await actions.exportData();
    }
    if (!context.mounted) return;
    // The last step (the word DELETE and the proof of ownership) is its own
    // page, because what it asks for depends on the account.
    await context.push(RoutePaths.deleteAccount);
  }
}

enum _DeleteChoice { cancel, export, go }
