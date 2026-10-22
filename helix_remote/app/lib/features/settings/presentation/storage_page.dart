import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:helix_remote/features/settings/application/settings_gateway.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/shared/format.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Settings > Storage and data, drawn by `orbit_ui`'s
/// [orbit.StorageScreen]: what Orbit keeps on this phone, its biggest chats,
/// and freeing a chat's photos, videos or documents without deleting its
/// messages.
class StoragePage extends ConsumerWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(storageDetailProvider);
    final value = detail.value;
    final summary = value?.summary;
    final media = value?.media;
    final total = summary?.totalBytes ?? 0;
    // The bar's three parts are the engine's known content, so they fill it;
    // the hero's total also counts thumbnails and work in progress.
    final known = (summary?.databaseBytes ?? 0) + (media?.totalBytes ?? 0);
    final photos = media?.photosVideosBytes ?? 0;
    final files = (media?.filesBytes ?? 0) + (media?.voiceNoteBytes ?? 0);
    final chats = value?.chats ?? const <ChatStorageSizes>[];
    final biggest = chats.isEmpty ? 0 : chats.first.totalBytes;
    final chatsById = <String, orbit.HelixChatListItem>{
      for (final item in [
        ...?ref.watch(chatListProvider).value,
        ...?ref.watch(archivedChatListProvider).value,
      ])
        item.id: item,
    };

    Future<String?> free(StorageFreeKind kind, String chatId) async {
      try {
        final freed = await ref
            .read(settingsGatewayProvider)
            .freeChatSpace(chatId, kind);
        ref.invalidate(storageDetailProvider);
        return '${formatBytes(freed)} freed';
      } on Object catch (error) {
        return describeFailure(error).message;
      }
    }

    return orbit.StorageScreen(
      model: orbit.StorageModel(
        status: switch (detail) {
          AsyncData() => orbit.StorageStatus.ready,
          AsyncError() when value == null => orbit.StorageStatus.failed,
          _ when value != null => orbit.StorageStatus.ready,
          _ => orbit.StorageStatus.loading,
        },
        totalLabel: '${formatBytes(total)} on this phone',
        splitLabel: summary == null
            ? ''
            : '${formatBytes(summary.databaseBytes)} messages and keys · '
                  '${formatBytes(summary.mediaBytes)} media',
        messagesShare: known == 0 ? 1 : (summary?.databaseBytes ?? 0) / known,
        mediaShare: known == 0 ? 0 : photos / known,
        filesShare: known == 0 ? 0 : files / known,
        chats: [
          for (final chat in chats)
            orbit.StorageChatItem(
              id: chat.chatId,
              title: chatsById[chat.chatId]?.title ?? 'Chat',
              avatar:
                  chatsById[chat.chatId]?.avatar ??
                  orbit.HelixAvatarModel(
                    name: 'Chat',
                    colorIndex: orbit.HelixAvatarModel.colorIndexFor(
                      chat.chatId,
                    ),
                  ),
              sizeLabel: formatBytes(chat.totalBytes),
              share: biggest == 0 ? 0 : chat.totalBytes / biggest,
              mediaLabel: formatBytes(chat.photosVideosBytes),
              documentsLabel: formatBytes(chat.filesBytes),
            ),
        ],
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
        onFreeMedia: (chatId) => free(StorageFreeKind.photosVideos, chatId),
        onFreeDocuments: (chatId) => free(StorageFreeKind.documents, chatId),
        onOpenChatsSettings: () => context.push(RoutePaths.chats),
        onOpenBackup: () => context.push(RoutePaths.backup),
        onRetry: () => ref.invalidate(storageDetailProvider),
      ),
    );
  }
}
