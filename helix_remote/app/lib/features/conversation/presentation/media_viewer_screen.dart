import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/media_content.dart';
import 'package:helix_remote/features/conversation/application/media_viewer.dart';
import 'package:helix_remote/features/conversation/application/video_session.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: the photos and videos of one message, full screen, drawn by
/// `orbit_ui`'s viewer (`contracts/conversation.md`).
///
/// Photos zoom and pan. The video on screen plays in the in-app player (play
/// and pause, seek, speed); where the device has no player it is handed to
/// the system (share sheet) instead, and it pauses when the app goes to the
/// background. A view-once message is opened here exactly once: once its
/// file is on screen it is marked viewed and the sender is told, and closing
/// the viewer deletes the file.
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

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen>
    with WidgetsBindingObserver {
  late int _index = widget.initialIndex;
  bool _openedViewOnce = false;

  /// The file of the video on screen, whose session is watched.
  String? _videoPath;

  // Kept in a field: `ref` cannot be used from `dispose`.
  late final ViewOnceSession _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = ref.read(viewOnceSessionProvider(widget.rowid));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Closing the viewer is what ends a view-once message.
    unawaited(_session.close());
    super.dispose();
  }

  /// A video does not keep playing behind the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final path = _videoPath;
    if (path == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(ref.read(videoSessionProvider(path).notifier).pause());
    }
  }

  static String? _pathOf(MediaPart part) =>
      part.view?.localPath ?? part.row.localPath;

  static bool _isVideo(MediaPart part) =>
      part.row.kind == 'video' || part.row.kind == 'video_note';

  static String _speedLabel(double speed) =>
      speed == speed.roundToDouble() ? '${speed.round()}x' : '${speed}x';

  orbit.VideoView _videoOf(VideoViewState v) => orbit.VideoView(
    phase: switch (v.phase) {
      VideoPhase.failed => orbit.VideoPhase.failed,
      VideoPhase.ready when v.surface != null => orbit.VideoPhase.ready,
      _ => orbit.VideoPhase.opening,
    },
    playing: v.playing,
    // A paused video that has not buffered yet shows its play button.
    buffering: v.buffering && v.playing,
    completed: v.completed,
    fraction: v.fraction,
    positionLabel: v.positionLabel,
    durationLabel: v.durationLabel,
    speed: _speedLabel(v.speed),
    surface: v.surface,
    message: v.message,
  );

  @override
  Widget build(BuildContext context) {
    final meta = ref.watch(viewerMetaProvider(widget.rowid)).value;
    final parts = ref.watch(messageMediaProvider(widget.rowid)).value;
    _videoPath = null;

    orbit.MediaViewerModel model;
    var visual = const <MediaPart>[];
    if (meta != null && meta.viewOnce && meta.outgoing) {
      model = const orbit.MediaViewerModel(
        state: orbit.ViewerState.viewOnceMine,
        title: 'View once',
        canShare: false,
      );
    } else if (meta != null &&
        meta.viewOnce &&
        meta.alreadyOpened &&
        !_openedViewOnce) {
      model = orbit.MediaViewerModel(
        state: orbit.ViewerState.viewOnceOpened,
        title: meta.senderName,
        canShare: false,
      );
    } else if (parts == null) {
      model = orbit.MediaViewerModel(
        state: orbit.ViewerState.loading,
        title: meta?.senderName ?? '',
      );
    } else {
      visual = [
        for (final p in parts)
          if (p.isVisual) p,
      ];
      if (meta != null &&
          meta.viewOnce &&
          !_openedViewOnce &&
          parts.isNotEmpty &&
          parts.every((p) => p.ready)) {
        // Only count it as opened once the file is on screen.
        _openedViewOnce = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _session.open());
      }
      if (visual.isEmpty) {
        model = orbit.MediaViewerModel(
          state: orbit.ViewerState.empty,
          title: meta?.senderName ?? '',
          canShare: false,
        );
      } else {
        final index = _index.clamp(0, visual.length - 1);
        final current = visual[index];
        final path = _pathOf(current);
        orbit.VideoView? video;
        if (_isVideo(current) && current.ready && path != null) {
          _videoPath = path;
          video = _videoOf(ref.watch(videoSessionProvider(path)));
        }
        model = orbit.MediaViewerModel(
          title: meta?.senderName ?? '',
          timeLabel: meta?.timeLabel ?? '',
          caption: meta?.caption ?? '',
          initialIndex: widget.initialIndex.clamp(0, visual.length - 1),
          canShare: !(meta?.viewOnce ?? false),
          video: video,
          items: [
            for (final p in visual)
              orbit.ViewerItem(
                isVideo: _isVideo(p),
                onDevice: p.ready && _pathOf(p) != null,
                image: _isVideo(p) || !p.ready || _pathOf(p) == null
                    ? mediaThumbnailOf(p)
                    : FileImage(File(_pathOf(p)!)),
              ),
          ],
        );
      }
    }

    VideoSession? session() {
      final path = _videoPath;
      return path == null
          ? null
          : ref.read(videoSessionProvider(path).notifier);
    }

    return orbit.MediaViewerScreen(
      model: model,
      actions: orbit.MediaViewerActions(
        onPageChanged: (i) => setState(() => _index = i),
        onShare: (i) {
          if (i < visual.length) {
            unawaited(ref.read(mediaActionsProvider).share(visual[i]));
          }
        },
        onOpenVideoElsewhere: (i) {
          if (i < visual.length) {
            unawaited(ref.read(mediaActionsProvider).share(visual[i]));
          }
        },
        onVideoToggle: () => unawaited(session()?.toggle()),
        onVideoSeek: (fraction) => unawaited(session()?.seek(fraction)),
        onVideoSpeed: () => unawaited(session()?.cycleSpeed()),
      ),
    );
  }
}
