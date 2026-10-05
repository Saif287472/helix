import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/video_session.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A video in the full-screen viewer: its thumbnail until the player is up,
/// then the picture with play / pause, a seek bar, the time, and the speed.
///
/// Only the page that is on screen ([active]) opens a player; a page swiped
/// away is just its thumbnail again, which frees the decoder. When the device
/// cannot play the file, [onOpenElsewhere] hands it to another app, which is
/// what every video did before the player existed.
class VideoPlayerView extends ConsumerStatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.path,
    required this.active,
    required this.onOpenElsewhere,
    this.thumbnail,
  });

  final String path;
  final bool active;
  final ImageProvider? thumbnail;
  final VoidCallback onOpenElsewhere;

  @override
  ConsumerState<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends ConsumerState<VideoPlayerView>
    with WidgetsBindingObserver {
  /// Controls show while paused; while playing a tap shows them for a moment.
  bool _controlsShown = true;
  Timer? _hide;

  /// While the thumb is dragged the bar follows the finger, not the video.
  double? _dragging;

  static const _hideAfter = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hide?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A video does not keep playing behind the app.
    if (!widget.active) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(ref.read(videoSessionProvider(widget.path).notifier).pause());
    }
  }

  void _toggleControls(VideoViewState view) {
    _hide?.cancel();
    setState(() => _controlsShown = !_controlsShown);
    if (_controlsShown && view.playing) _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(_hideAfter, () {
      if (mounted) setState(() => _controlsShown = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return _Poster(thumbnail: widget.thumbnail, busy: false);
    }
    final session = videoSessionProvider(widget.path);
    final view = ref.watch(session);
    final notifier = ref.read(session.notifier);
    // The controls fade a moment after playback starts.
    ref.listen(session.select((s) => s.playing), (_, playing) {
      if (playing && _controlsShown) _scheduleHide();
    });

    if (view.phase == VideoPhase.failed) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _Poster(thumbnail: widget.thumbnail, busy: false),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(HelixSpace.md),
                  child: Text(
                    view.message ?? 'This video cannot be played.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: HelixScrimColors.onBackdrop),
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.onOpenElsewhere,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open video'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (view.phase == VideoPhase.opening || view.surface == null) {
      return _Poster(thumbnail: widget.thumbnail, busy: true);
    }

    final showControls = _controlsShown || !view.playing;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleControls(view),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: view.surface),
          if (view.buffering && view.playing)
            const Center(
              child: CircularProgressIndicator(
                color: HelixScrimColors.onBackdrop,
              ),
            ),
          if (showControls) ...[
            Center(
              child: IconButton.filled(
                tooltip: view.completed
                    ? 'Play again'
                    : view.playing
                    ? 'Pause'
                    : 'Play',
                iconSize: 40,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(72),
                  backgroundColor: HelixScrimColors.barrier,
                  foregroundColor: HelixScrimColors.onBackdrop,
                ),
                icon: Icon(
                  view.completed
                      ? Icons.replay
                      : view.playing
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
                onPressed: () async {
                  await notifier.toggle();
                  if (mounted && !view.playing) _scheduleHide();
                },
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _Controls(
                view: view,
                dragging: _dragging,
                onDrag: (value) => setState(() => _dragging = value),
                onDragEnd: (value) {
                  setState(() => _dragging = null);
                  unawaited(notifier.seek(value));
                },
                onSpeed: () => unawaited(notifier.cycleSpeed()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.thumbnail, required this.busy});

  final ImageProvider? thumbnail;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (thumbnail != null)
          Image(
            image: thumbnail!,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        Center(
          child: busy
              ? const CircularProgressIndicator(
                  color: HelixScrimColors.onBackdrop,
                )
              : const Icon(
                  Icons.play_circle_outline,
                  size: 72,
                  color: HelixScrimColors.onBackdrop,
                ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.view,
    required this.dragging,
    required this.onDrag,
    required this.onDragEnd,
    required this.onSpeed,
  });

  final VideoViewState view;
  final double? dragging;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onSpeed;

  @override
  Widget build(BuildContext context) {
    final speed = view.speed == view.speed.roundToDouble()
        ? '${view.speed.round()}x'
        : '${view.speed}x';
    return DecoratedBox(
      decoration: const BoxDecoration(color: HelixScrimColors.barrier),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: HelixSpace.sm),
          child: Row(
            children: [
              Text(
                view.positionLabel,
                style: const TextStyle(color: HelixScrimColors.onBackdrop),
              ),
              Expanded(
                // A slider fills whatever height it is given; a bar is 48.
                child: SizedBox(
                  height: 48,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: HelixScrimColors.onBackdrop,
                      inactiveTrackColor: HelixScrimColors.onBackdropSubtle,
                      thumbColor: HelixScrimColors.onBackdrop,
                    ),
                    child: Slider(
                      value: (dragging ?? view.fraction).clamp(0.0, 1.0),
                      semanticFormatterCallback: (_) =>
                          '${view.positionLabel} of ${view.durationLabel}',
                      onChanged: onDrag,
                      onChangeEnd: onDragEnd,
                    ),
                  ),
                ),
              ),
              Text(
                view.durationLabel,
                style: const TextStyle(color: HelixScrimColors.onBackdrop),
              ),
              const SizedBox(width: HelixSpace.xxs),
              Tooltip(
                message: 'Playback speed',
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: HelixScrimColors.onBackdrop,
                  ),
                  onPressed: onSpeed,
                  child: Text(speed),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
