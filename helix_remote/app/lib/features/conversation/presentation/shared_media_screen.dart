import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/features/conversation/application/shared_media.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// The photos and videos, documents and links of one conversation, in three
/// tabs. Reached from the conversation's menu and settings and from a
/// person's contact info.
class SharedMediaScreen extends ConsumerWidget {
  const SharedMediaScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(conversationHeaderProvider(conversationId))?.title;
    final files = ref.watch(sharedFilesProvider(conversationId));
    final links = ref.watch(sharedLinksProvider(conversationId));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title ?? 'Media, links and docs'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Media'),
              Tab(text: 'Docs'),
              Tab(text: 'Links'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Async<SharedFiles>(
              value: files,
              isEmpty: (files) => files.media.isEmpty,
              empty: const HelixEmptyState(
                icon: Icons.photo_library_outlined,
                title: 'No media yet',
                message:
                    'Photos and videos you share in this chat show up here.',
              ),
              builder: (files) => _MediaGrid(
                tiles: files.media,
                conversationId: conversationId,
              ),
            ),
            _Async<SharedFiles>(
              value: files,
              isEmpty: (files) => files.documents.isEmpty,
              empty: const HelixEmptyState(
                icon: Icons.description_outlined,
                title: 'No documents yet',
                message: 'Files you share in this chat show up here.',
              ),
              builder: (files) => ListView.builder(
                itemCount: files.documents.length,
                itemBuilder: (context, index) =>
                    _DocumentTile(document: files.documents[index]),
              ),
            ),
            _Async<List<SharedLink>>(
              value: links,
              isEmpty: (links) => links.isEmpty,
              empty: const HelixEmptyState(
                icon: Icons.link,
                title: 'No links yet',
                message: 'Web links sent in this chat show up here.',
              ),
              builder: (links) => ListView.builder(
                itemCount: links.length,
                itemBuilder: (context, index) => _LinkTile(
                  link: links[index],
                  conversationId: conversationId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading, error and empty states around one tab's content.
class _Async<T> extends StatelessWidget {
  const _Async({
    required this.value,
    required this.isEmpty,
    required this.empty,
    required this.builder,
  });

  final AsyncValue<T> value;
  final bool Function(T value) isEmpty;
  final Widget empty;
  final Widget Function(T value) builder;

  @override
  Widget build(BuildContext context) {
    final data = value.value;
    if (data == null) {
      return value.hasError
          ? const HelixErrorState(message: 'This could not be loaded.')
          : const Center(child: CircularProgressIndicator());
    }
    return isEmpty(data) ? empty : builder(data);
  }
}

class _MediaGrid extends ConsumerWidget {
  const _MediaGrid({required this.tiles, required this.conversationId});

  final List<SharedMediaTile> tiles;
  final String conversationId;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    SharedMediaTile tile,
  ) async {
    final result = await ref.read(sharedOpenProvider)(
      tile.part,
      tile.messageRowid,
    );
    if (!context.mounted) return;
    switch (result) {
      case SharedOpenResult.viewer:
        await context.push(
          mediaLocation(conversationId, tile.messageRowid, index: tile.index),
        );
      case SharedOpenResult.fetching:
        showHelixSnackBar(context, 'Downloading...');
      case SharedOpenResult.missing:
        showHelixSnackBar(context, 'This file is no longer on this phone.');
      case SharedOpenResult.handedOver || SharedOpenResult.cancelled:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(HelixSpace.xxs),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 128,
        mainAxisSpacing: HelixSpace.xxs,
        crossAxisSpacing: HelixSpace.xxs,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, index) {
        final tile = tiles[index];
        return Semantics(
          button: true,
          label: tile.label,
          child: InkWell(
            onTap: () => _open(context, ref, tile),
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: scheme.surfaceContainerHigh,
                    child: tile.thumbnail == null
                        ? Icon(
                            tile.isVideo
                                ? Icons.videocam_outlined
                                : Icons.image_outlined,
                            color: scheme.onSurfaceVariant,
                          )
                        : Image(image: tile.thumbnail!, fit: BoxFit.cover),
                  ),
                  if (tile.isVideo)
                    Positioned(
                      left: HelixSpace.xs,
                      bottom: HelixSpace.xs,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_circle_outline,
                            size: 18,
                            color: HelixScrimColors.onBackdrop,
                          ),
                          if (tile.durationLabel != null)
                            Text(
                              ' ${tile.durationLabel}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: HelixScrimColors.onBackdrop,
                                  ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DocumentTile extends ConsumerWidget {
  const _DocumentTile({required this.document});

  final SharedDocument document;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    leading: const Icon(Icons.description_outlined),
    title: Text(document.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(document.detail),
    onTap: () async {
      final result = await ref.read(sharedOpenProvider)(
        document.part,
        document.messageRowid,
      );
      if (!context.mounted) return;
      switch (result) {
        case SharedOpenResult.fetching:
          showHelixSnackBar(context, 'Downloading...');
        case SharedOpenResult.missing:
          showHelixSnackBar(context, 'This file is no longer on this phone.');
        case SharedOpenResult.viewer ||
            SharedOpenResult.handedOver ||
            SharedOpenResult.cancelled:
          break;
      }
    },
  );
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.link, required this.conversationId});

  final SharedLink link;
  final String conversationId;

  Future<void> _launch() async {
    final uri = Uri.tryParse(link.url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.link),
    title: Text(link.url, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text('${link.host}, ${link.whenLabel}'),
    onTap: _launch,
    trailing: IconButton(
      icon: const Icon(Icons.chat_bubble_outline),
      tooltip: 'Show in chat',
      onPressed: () =>
          context.push(chatLocation(conversationId, messageId: link.messageId)),
    ),
  );
}
