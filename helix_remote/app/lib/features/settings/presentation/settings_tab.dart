import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The Settings tab: who you are, then the pages.
///
/// The header opens the profile. Every row below opens a page of its own, so
/// this screen holds no switches and no state beyond what it reads.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = ref.watch(settingsHeaderProvider).value;
    final avatar = ref.watch(settingsAvatarProvider);
    final name = header?.name ?? 'Helix';
    final about = (header?.about ?? '').isNotEmpty
        ? header!.about
        : header?.serverHost;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: HelixSpace.sm),
        children: [
          HelixProfileHeaderTile(
            avatar: HelixAvatarModel(
              name: name,
              image: avatar == null ? null : MemoryImage(avatar),
              colorIndex: HelixAvatarModel.colorIndexFor(
                (header?.accountId ?? '').isEmpty ? 'helix' : header!.accountId,
              ),
            ),
            name: name,
            about: about,
            onTap: () => context.push(RoutePaths.profile),
          ),
          const SizedBox(height: HelixSpace.sm),
          HelixSettingsSection(
            children: [
              _tile(
                context,
                Icons.key_outlined,
                'Account',
                'Password, export, sign out, delete',
                RoutePaths.account,
              ),
              _tile(
                context,
                Icons.lock_outline,
                'Privacy',
                'Last seen, receipts, blocked, app lock',
                RoutePaths.privacy,
              ),
              _tile(
                context,
                Icons.notifications_outlined,
                'Notifications',
                'Messages, groups and calls',
                RoutePaths.notifications,
              ),
              _tile(
                context,
                Icons.chat_outlined,
                'Chats',
                'Text size, Enter key, media downloads',
                RoutePaths.chats,
              ),
            ],
          ),
          const SizedBox(height: HelixSpace.md),
          HelixSettingsSection(
            children: [
              _tile(
                context,
                Icons.devices_outlined,
                'Devices',
                'Where you are signed in',
                RoutePaths.devices,
              ),
              _tile(
                context,
                Icons.backup_outlined,
                'Backup',
                'Encrypted history and transfer',
                RoutePaths.backup,
              ),
              _tile(
                context,
                Icons.storage_outlined,
                'Storage and data',
                'What Helix keeps on this phone',
                RoutePaths.storage,
              ),
            ],
          ),
          const SizedBox(height: HelixSpace.md),
          HelixSettingsSection(
            children: [
              _tile(
                context,
                Icons.info_outline,
                'Help and about',
                'Version, terms, privacy policy',
                RoutePaths.about,
              ),
              _tile(
                context,
                Icons.tune,
                'Advanced',
                'Server details and connection',
                RoutePaths.advanced,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    String path,
  ) => HelixSettingsTile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    showChevron: true,
    onTap: () => context.push(path),
  );
}
