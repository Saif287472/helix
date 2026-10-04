import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/media_content.dart';
import 'package:helix_remote/features/conversation/application/media_viewer.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Full-screen view of the photos and videos of one message.
///
/// Photos zoom and pan. There is no video player in this build, so a video is
/// handed to the system (share sheet) to play. A view-once message is opened
/// here exactly once: opening marks it as viewed and tells the sender, and
/// closing the viewer deletes the file.
class MediaViewerScreen extends ConsumerStatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.rowid,
    this.initialIndex = 0,
  });

  final int rowid;
  final int initialIndex;

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  int _index = 0;
  bool _openedViewOnce = false;
  late final ViewOnceSession _session;

  @override
  void initState() {
    super.initState();
    _session = ref.read(viewOnceSessionProvider(widget.rowid));
    _index = widget.initialIndex;
  }

  @override
  void dispose() {
    // Closing the viewer is what ends a view-once message.
    _session.close();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = ref.watch(viewerMetaProvider(widget.rowid)).value;
    final parts = ref.watch(messageMediaProvider(widget.rowid)).value;

    if (meta != null && meta.viewOnce && !meta.outgoing && !_openedViewOnce) {
      if (meta.alreadyOpened) {
        return _Frame(
          title: meta.senderName,
          child: const Center(
            child: Text(
              'This view-once message has already been opened.',
              style: TextStyle(color: HelixScrimColors.onBackdrop),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      // Only count it as opened once the file is on screen.
      if (parts != null && parts.isNotEmpty && parts.every((p) => p.ready)) {
        _openedViewOnce = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _session.open());
      }
    }
    if (meta != null && meta.viewOnce && meta.outgoing) {
      return const _Frame(
        title: 'View once',
        child: Center(
          child: Text(
            'You cannot open a view-once message you sent.',
            style: TextStyle(color: HelixScrimColors.onBackdrop),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (parts == null) {
      return const _Frame(
        title: '',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final visual = [
      for (final p in parts)
        if (p.isVisual) p,
    ];
    if (visual.isEmpty) {
      return const _Frame(
        title: '',
        child: Center(
          child: Text(
            'There is nothing to show here.',
            style: TextStyle(color: HelixScrimColors.onBackdrop),
          ),
        ),
      );
    }
    return _Frame(
      title: meta?.senderName ?? '',
      subtitle: meta == null
          ? null
          : visual.length > 1
          ? '${meta.timeLabel}  (${_index + 1} of ${visual.length})'
          : meta.timeLabel,
      actions: [
        IconButton(
          icon: const Icon(Icons.ios_share, color: HelixScrimColors.onBackdrop),
          tooltip: 'Share',
          onPressed: meta?.viewOnce ?? false
              ? null
              : () => ref
                    .read(mediaActionsProvider)
                    .share(visual[_index.clamp(0, visual.length - 1)]),
        ),
      ],
      caption: meta?.caption,
      child: PageView.builder(
        controller: _pages,
        itemCount: visual.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, index) => _MediaPage(part: visual[index]),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.caption,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final String? caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HelixScrimColors.backdrop,
      appBar: AppBar(
        backgroundColor: HelixScrimColors.backdrop,
        foregroundColor: HelixScrimColors.onBackdrop,
        iconTheme: const IconThemeData(color: HelixScrimColors.onBackdrop),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: HelixScrimColors.onBackdrop,
                fontSize: 16,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: const TextStyle(
                  color: HelixScrimColors.onBackdropMuted,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        actions: actions,
      ),
      body: Column(
        children: [
          Expanded(child: child),
          if (caption != null && caption!.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(HelixSpace.md),
                child: Text(
                  caption!,
                  style: const TextStyle(color: HelixScrimColors.onBackdrop),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaPage extends ConsumerWidget {
  const _MediaPage({required this.part});

  final MediaPart part;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = part.view?.localPath ?? part.row.localPath;
    if (!part.ready || path == null) {
      return const Center(
        child: Text(
          'This file is not on your device yet.',
          style: TextStyle(color: HelixScrimColors.onBackdrop),
        ),
      );
    }
    final isVideo = part.row.kind == 'video' || part.row.kind == 'video_note';
    if (isVideo) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline,
              size: 72,
              color: HelixScrimColors.onBackdrop,
            ),
            const SizedBox(height: HelixSpace.sm),
            FilledButton.icon(
              onPressed: () => ref.read(mediaActionsProvider).share(part),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open video'),
            ),
          ],
        ),
      );
    }
    return InteractiveViewer(
      maxScale: 6,
      child: Center(
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          semanticLabel: 'Photo',
          errorBuilder: (context, error, stack) => const Text(
            'This picture cannot be shown.',
            style: TextStyle(color: HelixScrimColors.onBackdrop),
          ),
        ),
      ),
    );
  }
}
