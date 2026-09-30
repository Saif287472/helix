import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoRenderer;
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'package:helix_remote/screens/call/call_format.dart';
import 'package:helix_remote/screens/call/call_parts.dart';

/// Full-bleed video layout: the main video fills the screen, the local
/// camera floats in a draggable corner preview, and [header] / [tray] fade
/// in and out over gradient scrims.
class VideoCallView extends StatefulWidget {
  const VideoCallView({
    super.key,
    required this.status,
    required this.header,
    required this.tray,
    required this.controlsVisible,
    required this.onStageTap,
    this.notice,
  });

  final RemoteCallStatus status;
  final Widget header;
  final Widget tray;
  final Widget? notice;
  final bool controlsVisible;
  final VoidCallback onStageTap;

  @override
  State<VideoCallView> createState() => _VideoCallViewState();
}

class _VideoCallViewState extends State<VideoCallView> {
  static const _margin = 12.0;

  /// Which corner the preview rests in; x/y are -1 or 1.
  Alignment _corner = Alignment.topRight;

  /// Top-left of the preview while a drag is in progress.
  Offset? _drag;

  /// True shows the local camera full-screen and the peer in the preview.
  bool _swapped = false;

  bool get _connected => isConnectedCallState(widget.status.state);

  @override
  void didUpdateWidget(VideoCallView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_swapped && !_hasLocalPreview) _swapped = false;
  }

  bool get _hasLocalPreview {
    final status = widget.status;
    return status.localRenderer != null && status.isLocalVideoEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final media = MediaQuery.of(context);
    final reduceMotion = media.disableAnimations;
    final fade = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final remote = _connected ? status.remoteRenderer : null;
    final local = _hasLocalPreview ? status.localRenderer : null;

    // Before the peer's video exists, your own camera fills the screen.
    final Widget stage;
    Widget? preview;
    if (remote == null) {
      stage = local == null
          ? _AvatarStage(status: status)
          : RemoteCallVideoView(renderer: local, mirror: status.isFrontCamera);
    } else if (_swapped && local != null) {
      stage = RemoteCallVideoView(
        renderer: local,
        mirror: status.isFrontCamera,
      );
      preview = _RemoteVideo(renderer: remote, status: status, compact: true);
    } else {
      stage = _RemoteVideo(renderer: remote, status: status);
      if (local != null) {
        preview = RemoteCallVideoView(
          renderer: local,
          mirror: status.isFrontCamera,
        );
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final landscape = size.width > size.height;
        final previewSize = landscape
            ? const Size(144, 96)
            : size.width >= HelixBreakpoints.compact
            ? const Size(132, 188)
            : const Size(100, 142);
        final topInset =
            media.padding.top + (widget.controlsVisible ? 80.0 : _margin);
        final bottomInset =
            media.padding.bottom + (widget.controlsVisible ? 140.0 : _margin);

        Offset restingPosition() => Offset(
          _corner.x < 0 ? _margin : size.width - previewSize.width - _margin,
          _corner.y < 0
              ? topInset
              : size.height - previewSize.height - bottomInset,
        );
        final position = _drag ?? restingPosition();

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onStageTap,
                child: Semantics(
                  label: remote == null
                      ? 'Your camera'
                      : 'Video from ${status.displayName}',
                  child: stage,
                ),
              ),
            ),
            // Top scrim + header.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _Fading(
                visible: widget.controlsVisible,
                duration: fade,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [HelixScrimColors.barrier, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: HelixInsets.fromLTRB(4, 4, 4, 28),
                      child: widget.header,
                    ),
                  ),
                ),
              ),
            ),
            if (preview != null)
              AnimatedPositioned(
                duration: _drag != null || reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                left: position.dx,
                top: position.dy,
                width: previewSize.width,
                height: previewSize.height,
                child: Semantics(
                  button: true,
                  label: _swapped
                      ? 'Show ${status.displayName} full screen'
                      : 'Show your camera full screen',
                  child: GestureDetector(
                    onTap: () => setState(() => _swapped = !_swapped),
                    onPanStart: (_) => setState(() => _drag = position),
                    onPanUpdate: (details) {
                      final next = (_drag ?? position) + details.delta;
                      setState(() {
                        _drag = Offset(
                          next.dx.clamp(
                            _margin,
                            size.width - previewSize.width - _margin,
                          ),
                          next.dy.clamp(
                            media.padding.top + _margin,
                            size.height -
                                previewSize.height -
                                media.padding.bottom -
                                _margin,
                          ),
                        );
                      });
                    },
                    onPanEnd: (_) {
                      final drag = _drag ?? position;
                      final centre =
                          drag +
                          Offset(previewSize.width / 2, previewSize.height / 2);
                      setState(() {
                        _corner = Alignment(
                          centre.dx < size.width / 2 ? -1 : 1,
                          centre.dy < size.height / 2 ? -1 : 1,
                        );
                        _drag = null;
                      });
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: HelixNeutralColors.videoPlaceholder,
                        borderRadius: HelixRadius.card,
                        border: Border.all(
                          color: HelixScrimColors.onBackdropSubtle,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: HelixScrimColors.barrierSoft,
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: HelixRadius.card,
                        child: preview,
                      ),
                    ),
                  ),
                ),
              ),
            // Bottom scrim + notice + tray.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Fading(
                visible: widget.controlsVisible,
                duration: fade,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [HelixScrimColors.barrier, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: HelixInsets.fromLTRB(12, 32, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.notice != null) ...[
                            widget.notice!,
                            const SizedBox(height: 10),
                          ],
                          widget.tray,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Fading extends StatelessWidget {
  const _Fading({
    required this.visible,
    required this.duration,
    required this.child,
  });

  final bool visible;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        child: ExcludeSemantics(excluding: !visible, child: child),
      ),
    );
  }
}

/// The peer's video, or their avatar while no frames are arriving (camera
/// off, or the first frame has not landed yet).
class _RemoteVideo extends StatelessWidget {
  const _RemoteVideo({
    required this.renderer,
    required this.status,
    this.compact = false,
  });

  final RTCVideoRenderer renderer;
  final RemoteCallStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: renderer,
      builder: (context, _) {
        if (renderer.renderVideo && renderer.videoWidth > 0) {
          return RemoteCallVideoView(renderer: renderer);
        }
        return compact
            ? ColoredBox(
                color: HelixNeutralColors.videoPlaceholder,
                child: Center(child: CallAvatar(status: status, diameter: 48)),
              )
            : _AvatarStage(status: status);
      },
    );
  }
}

class _AvatarStage extends StatelessWidget {
  const _AvatarStage({required this.status});

  final RemoteCallStatus status;

  @override
  Widget build(BuildContext context) {
    return CallSurface(
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: CallAvatar(
            status: status,
            diameter: (constraints.biggest.shortestSide * 0.36).clamp(
              64.0,
              148.0,
            ),
          ),
        ),
      ),
    );
  }
}
