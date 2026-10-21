import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/shared/format.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Settings > Storage and data, drawn by `orbit_ui`'s
/// [orbit.StorageScreen]: what Orbit keeps on this phone.
///
/// Everything is read, nothing is deleted from here yet. The split between
/// photos and documents, and the biggest chats, need the engine's sums by kind
/// and by chat (GAPS E2); until then the bar shows messages against all media
/// and the chat list is empty.
class StoragePage extends ConsumerWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageSummaryProvider);
    final value = storage.value;
    final total = value?.totalBytes ?? 0;

    return orbit.StorageScreen(
      model: orbit.StorageModel(
        status: switch (storage) {
          AsyncData() => orbit.StorageStatus.ready,
          AsyncError() when value == null => orbit.StorageStatus.failed,
          _ when value != null => orbit.StorageStatus.ready,
          _ => orbit.StorageStatus.loading,
        },
        totalLabel: '${formatBytes(total)} on this phone',
        splitLabel: value == null
            ? ''
            : '${formatBytes(value.databaseBytes)} messages and keys · '
                  '${formatBytes(value.mediaBytes)} media',
        messagesShare: total == 0 ? 1 : value!.databaseBytes / total,
        mediaShare: total == 0 ? 0 : value!.mediaBytes / total,
        filesShare: 0,
        downloadSummary: downloadSummary(
          photos:
              ref.watch(mediaImagesProvider).value ?? MediaDownloadPolicy.wifi,
          voice:
              ref.watch(mediaAudioProvider).value ?? MediaDownloadPolicy.always,
          videos:
              ref.watch(mediaVideoProvider).value ?? MediaDownloadPolicy.never,
          documents:
              ref.watch(mediaDocumentsProvider).value ??
              MediaDownloadPolicy.never,
        ),
        backupOverMobile:
            ref.watch(backupOverMobileSettingProvider).value ?? false,
      ),
      actions: orbit.StorageActions(
        onOpenChatsSettings: () => context.push(RoutePaths.chats),
        onOpenBackup: () => context.push(RoutePaths.backup),
        onRetry: () => ref.invalidate(storageSummaryProvider),
      ),
    );
  }
}
