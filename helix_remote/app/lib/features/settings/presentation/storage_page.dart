import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:helix_remote/shared/format.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Storage and data: what Helix keeps on this phone.
///
/// Everything is read, nothing is deleted from here. Received media stays
/// until its message goes, so the way to free space is to delete messages or
/// chats; the engine then removes the files nothing refers to.
class StoragePage extends ConsumerWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageSummaryProvider);

    return HelixSettingsScaffold(
      title: 'Storage and data',
      body: ListView(
        children: [
          switch (storage) {
            AsyncData(:final value) => HelixSettingsSection(
              title: 'On this phone',
              children: [
                HelixSettingsTile(
                  icon: Icons.sd_storage_outlined,
                  title: 'Total',
                  subtitle: formatBytes(value.totalBytes),
                ),
                HelixSettingsTile(
                  icon: Icons.forum_outlined,
                  title: 'Messages and keys',
                  subtitle: formatBytes(value.databaseBytes),
                ),
                HelixSettingsTile(
                  icon: Icons.perm_media_outlined,
                  title: 'Photos, videos and files',
                  subtitle: formatBytes(value.mediaBytes),
                ),
              ],
            ),
            AsyncError() => HelixErrorState(
              message: 'The storage figures could not be read.',
              onRetry: () => ref.invalidate(storageSummaryProvider),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(HelixSpace.lg),
              child: LinearProgressIndicator(),
            ),
          },
          const PageIntro(
            text:
                'Photos, videos and files you receive stay on this phone for '
                'as long as their message does. To free space, delete '
                'messages or a whole chat: the files go with them.',
          ),
          HelixSettingsSection(
            title: 'Data use',
            children: [
              HelixSettingsTile(
                icon: Icons.download_outlined,
                title: 'Media auto-download',
                subtitle: 'Choose what downloads on Wi-Fi and mobile data',
                showChevron: true,
                onTap: () => context.push(RoutePaths.chats),
              ),
              HelixSettingsTile(
                icon: Icons.backup_outlined,
                title: 'Backup over mobile data',
                subtitle: 'Choose whether backups may use your data plan',
                showChevron: true,
                onTap: () => context.push(RoutePaths.backup),
              ),
            ],
          ),
          const SizedBox(height: HelixSpace.lg),
        ],
      ),
    );
  }
}
