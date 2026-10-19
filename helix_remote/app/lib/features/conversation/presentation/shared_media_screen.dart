import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/features/conversation/application/shared_media.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;
import 'package:url_launcher/url_launcher.dart';

/// Connector: the photos and videos, documents and links of one
/// conversation, in three tabs, drawn by `orbit_ui`'s shared page. Reached
/// from the conversation's menu and settings and from a person's contact
/// info; [initialTab] (`media`, `docs` or `links`) picks the tab it opens on.
class SharedMediaScreen extends ConsumerWidget {
  const SharedMediaScreen({
    super.key,
    required this.conversationId,
    this.initialTab,
  });

  final String conversationId;
  final String? initialTab;

  static orbit.LoadState _stateOf(AsyncValue<Object?> v) => v.value != null
      ? orbit.LoadState.ready
      : v.hasError
      ? orbit.LoadState.error
      : orbit.LoadState.loading;

  /// Taps follow a media bubble's rules: open it when it is here, download
  /// it when it is not.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref, {
    required SharedMediaTile? tile,
    required SharedDocument? document,
  }) async {
    final part = tile?.part ?? document!.part;
    final rowid = tile?.messageRowid ?? document!.messageRowid;
    final result = await ref.read(sharedOpenProvider)(part, rowid);
    if (!context.mounted) return;
    switch (result) {
      case SharedOpenResult.viewer:
        if (tile != null) {
          await context.push(
            mediaLocation(conversationId, rowid, index: tile.index),
          );
        }
      case SharedOpenResult.fetching:
        orbit.showOrbitToast(context, 'Downloading...');
      case SharedOpenResult.missing:
        orbit.showOrbitToast(
          context,
          'This file is no longer on this phone.',
          error: true,
        );
      case SharedOpenResult.handedOver || SharedOpenResult.cancelled:
        break;
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(conversationHeaderProvider(conversationId))?.title;
    final files = ref.watch(sharedFilesProvider(conversationId));
    final links = ref.watch(sharedLinksProvider(conversationId));
    final media = files.value?.media ?? const <SharedMediaTile>[];
    final documents = files.value?.documents ?? const <SharedDocument>[];
    final found = links.value ?? const <SharedLink>[];
    return orbit.SharedMediaScreen(
      model: orbit.SharedMediaModel(
        title: title ?? 'Media, links and docs',
        initialTab: switch (initialTab) {
          'docs' => orbit.SharedTab.docs,
          'links' => orbit.SharedTab.links,
          _ => orbit.SharedTab.media,
        },
        filesState: _stateOf(files),
        linksState: _stateOf(links),
        media: [
          for (final t in media)
            orbit.SharedTileItem(
              thumbnail: t.thumbnail,
              isVideo: t.isVideo,
              durationLabel: t.durationLabel ?? '',
              label: t.label,
            ),
        ],
        documents: [
          for (final d in documents)
            orbit.SharedDocItem(name: d.name, detail: d.detail),
        ],
        links: [
          for (final l in found)
            orbit.SharedLinkItem(
              url: l.url,
              detail: '${l.host}, ${l.whenLabel}',
              messageId: l.messageId,
            ),
        ],
      ),
      actions: orbit.SharedMediaActions(
        onOpenMedia: (i) {
          if (i < media.length) {
            unawaited(_open(context, ref, tile: media[i], document: null));
          }
        },
        onOpenDocument: (i) {
          if (i < documents.length) {
            unawaited(_open(context, ref, tile: null, document: documents[i]));
          }
        },
        onOpenLink: (url) => unawaited(_launch(url)),
        // The app's way: the chat opens at that message.
        onShowInChat: (messageId) =>
            context.push(chatLocation(conversationId, messageId: messageId)),
        onRetry: () {
          ref.invalidate(sharedFilesProvider(conversationId));
          ref.invalidate(sharedLinksProvider(conversationId));
        },
      ),
    );
  }
}
