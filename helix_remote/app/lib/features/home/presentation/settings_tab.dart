import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/home/application/home_tab.dart';
import 'package:helix_remote/features/home/application/settings_tab_provider.dart';
import 'package:helix_remote/features/home/application/sign_out_action.dart';
import 'package:helix_remote/features/home/presentation/home_screen.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings.
///
/// A1 carries the account header, which server this device is on, and sign
/// out. A3 adds the rest of the pages (devices, backup, profile, privacy,
/// groups) as settings sections.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Everything the screen draws comes from one value object in the application
    // layer, so no widget here knows that a server has a URL or that an
    // account has an id. Before the runtime is up, the placeholders are shown.
    final settings =
        ref.watch(settingsTabProvider).value ?? const SettingsTabModel();
    final account = settings.account;

    return HomeTabScaffold(
      title: 'Settings',
      tab: HomeTab.settings,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: HelixSpace.sm),
        children: [
          HelixProfileHeaderTile(
            avatar: HelixAvatarModel(
              name: account.displayName,
              colorIndex: HelixAvatarModel.colorIndexFor(
                account.accountId.isEmpty ? 'helix' : account.accountId,
              ),
            ),
            name: account.displayName,
            about: settings.serverHost,
          ),
          const SizedBox(height: HelixSpace.sm),
          HelixSettingsSection(
            children: [
              HelixSettingsTile(
                icon: Icons.dns_outlined,
                title: 'Server',
                subtitle: settings.serverHost.isEmpty
                    ? 'Not chosen'
                    : settings.serverHost,
              ),
              HelixSettingsTile(
                icon: Icons.devices_outlined,
                title: 'Devices',
                subtitle: 'Signed in on this phone',
                showChevron: true,
                onTap: () => _notYet(context, 'Devices'),
              ),
              HelixSettingsTile(
                icon: Icons.lock_outline,
                title: 'Privacy',
                subtitle: 'Who can see your last seen and profile',
                showChevron: true,
                onTap: () => _notYet(context, 'Privacy'),
              ),
              HelixSettingsTile(
                icon: Icons.backup_outlined,
                title: 'Backup',
                subtitle: 'Encrypted history and transfer',
                showChevron: true,
                onTap: () => _notYet(context, 'Backup'),
              ),
            ],
          ),
          const SizedBox(height: HelixSpace.md),
          HelixSettingsSection(
            footer:
                'Signing out deletes this phone\'s messages, keys and history. '
                'There is no way to keep them: a phone that kept its keys '
                'could sign itself back in.',
            children: [
              HelixSettingsTile(
                icon: Icons.logout,
                title: 'Sign out',
                subtitle: 'Removes this device from your account',
                destructive: true,
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Sign out is destructive and permanent, so it is confirmed rather than
  /// done on the tap.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This removes Helix from this phone and deletes its messages, keys '
          'and history. Your other devices stay signed in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(signOutActionProvider)();
    }
  }

  void _notYet(BuildContext context, String page) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$page is not part of this build yet.')),
    );
  }
}
