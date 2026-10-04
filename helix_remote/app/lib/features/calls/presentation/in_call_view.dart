import 'package:flutter/material.dart';
import 'package:helix_remote/features/calls/application/call_audio.dart';
import 'package:helix_remote/features/calls/application/call_screen_state.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote/features/calls/presentation/call_parts.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What the in-call controls do. Null callbacks leave a control disabled.
class CallCallbacks {
  const CallCallbacks({
    required this.onHangUp,
    this.onMute,
    this.onCamera,
    this.onFlipCamera,
    this.onRoute,
    this.onDismissNotice,
  });

  final VoidCallback? onHangUp;
  final void Function({required bool muted})? onMute;
  final void Function({required bool enabled})? onCamera;
  final VoidCallback? onFlipCamera;

  /// The person tapped the audio route control.
  final VoidCallback? onRoute;
  final VoidCallback? onDismissNotice;
}

/// The icon and words of the audio route control for [audio].
({IconData icon, String label, String tooltip, bool toggled}) routeFace(
  CallAudioState audio,
) {
  switch (audio.route) {
    case CallAudioRoute.speaker:
      return (
        icon: Icons.volume_up,
        label: 'Speaker',
        tooltip: audio.available.length > 2
            ? 'Audio output: Speaker'
            : 'Turn speaker off',
        toggled: true,
      );
    case CallAudioRoute.bluetooth:
      return (
        icon: Icons.bluetooth_audio,
        label: 'Bluetooth',
        tooltip: 'Audio output: Bluetooth',
        toggled: true,
      );
    case CallAudioRoute.wiredHeadset:
      return (
        icon: Icons.headset,
        label: 'Headset',
        tooltip: 'Audio output: Headset',
        toggled: true,
      );
    case CallAudioRoute.earpiece:
      return (
        icon: Icons.volume_up_outlined,
        label: 'Speaker',
        tooltip: audio.available.length > 2
            ? 'Audio output: Phone'
            : 'Turn speaker on',
        toggled: false,
      );
  }
}

/// Builds the tray contents for [state].
///
/// Voice: Speaker, Video (unavailable), Mute, End. Video: Flip camera, Video,
/// Mute, Speaker, End. Everything but the audio-less case waits until the call
/// can use it, and is disabled once the call has finished.
List<CallControl> buildCallControls(
  CallScreenState state,
  CallCallbacks callbacks,
) {
  final finished = !state.isLive;
  VoidCallback? live(VoidCallback? action) => finished ? null : action;

  final route = routeFace(state.audio);
  final speaker = CallControl(
    icon: route.icon,
    label: route.label,
    tooltip: route.tooltip,
    toggled: route.toggled,
    onPressed: live(state.audio.canChoose ? callbacks.onRoute : null),
  );
  final mute = CallControl(
    icon: state.muted ? Icons.mic_off : Icons.mic,
    label: 'Mute',
    tooltip: state.muted ? 'Unmute microphone' : 'Mute microphone',
    toggled: state.muted,
    onPressed: live(
      callbacks.onMute == null || !state.hasControls
          ? null
          : () => callbacks.onMute!(muted: !state.muted),
    ),
  );
  // A voice call cannot be upgraded to video, so the button keeps the layout
  // stable and says why it is not available.
  final video = CallControl(
    icon: state.cameraOn ? Icons.videocam : Icons.videocam_off,
    label: 'Video',
    tooltip: !state.video
        ? 'Video is not available on a voice call'
        : state.cameraOn
        ? 'Turn camera off'
        : 'Turn camera on',
    toggled: state.video ? !state.cameraOn : null,
    onPressed: live(
      !state.video || callbacks.onCamera == null || !state.hasControls
          ? null
          : () => callbacks.onCamera!(enabled: !state.cameraOn),
    ),
  );
  final end = CallControl(
    icon: Icons.call_end,
    label: 'End',
    tooltip: 'End call',
    danger: true,
    onPressed: live(callbacks.onHangUp),
  );
  if (!state.video) return [speaker, video, mute, end];
  final flip = CallControl(
    icon: Icons.cameraswitch,
    label: 'Flip',
    tooltip: 'Flip camera',
    onPressed: live(state.cameraOn ? callbacks.onFlipCamera : null),
  );
  return [flip, video, mute, speaker, end];
}

/// The screen of a call that is not ringing here: dialing, connecting, live,
/// or just ended. Voice calls (and a video call before the picture arrives)
/// sit on the calm gradient; a video call fills the screen with the other
/// person's video and floats the camera preview in a corner.
class InCallView extends StatefulWidget {
  const InCallView({
    super.key,
    required this.state,
    required this.elapsed,
    required this.callbacks,
  });

  final CallScreenState state;
  final Duration? elapsed;
  final CallCallbacks callbacks;

  @override
  State<InCallView> createState() => _InCallViewState();
}

class _InCallViewState extends State<InCallView> {
  bool _controlsVisible = true;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final tray = CallControlTray(
      controls: buildCallControls(state, widget.callbacks),
    );
    final notice = state.notice == null
        ? null
        : CallNoticeBar(
            message: state.notice!,
            onDismiss: widget.callbacks.onDismissNotice,
          );
    final video = state.showsVideo && state.stage != CallStage.ended;
    if (!video) {
      return _VoiceLayout(
        state: state,
        elapsed: widget.elapsed,
        notice: notice,
        tray: tray,
      );
    }
    return _VideoLayout(
      state: state,
      elapsed: widget.elapsed,
      notice: notice,
      tray: tray,
      controlsVisible: _controlsVisible,
      onStageTap: () => setState(() => _controlsVisible = !_controlsVisible),
    );
  }
}

/// Name, number line and status, shared by both layouts.
class _CallHeader extends StatelessWidget {
  const _CallHeader({required this.state, required this.elapsed});

  final CallScreenState state;
  final Duration? elapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = state.subtitle?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            state.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: HelixScrimColors.onBackdrop,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: HelixScrimColors.onBackdropMuted,
              ),
            ),
          ),
        const SizedBox(height: 6),
        CallStatusLine(state: state, elapsed: elapsed),
        if (state.endDetail != null && state.notice == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              state.endDetail!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: HelixScrimColors.onBackdropFaint,
              ),
            ),
          ),
        if (state.quality == CallQuality.weak && state.isLive)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: PoorConnectionChip(),
          ),
      ],
    );
  }
}

class _VoiceLayout extends StatelessWidget {
  const _VoiceLayout({
    required this.state,
    required this.elapsed,
    required this.notice,
    required this.tray,
  });

  final CallScreenState state;
  final Duration? elapsed;
  final Widget? notice;
  final Widget tray;

  @override
  Widget build(BuildContext context) {
    return CallSurface(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 520;
            final avatar = (constraints.maxHeight * (compact ? 0.22 : 0.26))
                .clamp(72.0, 132.0);
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    HelixSpace.md,
                    compact ? HelixSpace.sm : HelixSpace.lg,
                    HelixSpace.md,
                    HelixSpace.md,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const EncryptedCallLabel(),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CallAvatar(
                            avatar: state.avatar,
                            diameter: avatar,
                            pulse: state.stage == CallStage.dialing,
                          ),
                          const SizedBox(height: HelixSpace.md),
                          _CallHeader(state: state, elapsed: elapsed),
                        ],
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (notice != null) ...[
                            notice!,
                            const SizedBox(height: 10),
                          ],
                          tray,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VideoLayout extends StatefulWidget {
  const _VideoLayout({
    required this.state,
    required this.elapsed,
    required this.notice,
    required this.tray,
    required this.controlsVisible,
    required this.onStageTap,
  });

  final CallScreenState state;
  final Duration? elapsed;
  final Widget? notice;
  final Widget tray;
  final bool controlsVisible;
  final VoidCallback onStageTap;

  @override
  State<_VideoLayout> createState() => _VideoLayoutState();
}

class _VideoLayoutState extends State<_VideoLayout> {
  /// True shows the local camera full-screen and the other person in the
  /// preview.
  bool _swapped = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final media = MediaQuery.of(context);
    final fade = media.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final remote = state.stage == CallStage.active ? state.remote : null;
    final local = state.cameraOn ? state.local : null;

    final Widget stage;
    Widget? preview;
    if (remote == null) {
      stage = local == null
          ? _AvatarStage(state: state)
          : _Surface(surface: local, mirror: state.frontCamera);
    } else if (_swapped && local != null) {
      stage = _Surface(surface: local, mirror: state.frontCamera);
      preview = _RemoteTile(surface: remote, state: state, compact: true);
    } else {
      stage = _RemoteTile(surface: remote, state: state);
      if (local != null) {
        preview = _Surface(surface: local, mirror: state.frontCamera);
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onStageTap,
            child: Semantics(
              label: remote == null
                  ? 'Your camera'
                  : 'Video from ${state.title}',
              child: stage,
            ),
          ),
        ),
        PositionedDirectional(
          start: 0,
          end: 0,
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: _CallHeader(state: state, elapsed: widget.elapsed),
                ),
              ),
            ),
          ),
        ),
        if (preview != null)
          PositionedDirectional(
            end: 12,
            top: media.padding.top + (widget.controlsVisible ? 120 : 12),
            width: 100,
            height: 142,
            child: Semantics(
              button: true,
              label: _swapped
                  ? 'Show ${state.title} full screen'
                  : 'Show your camera full screen',
              child: GestureDetector(
                onTap: () => setState(() => _swapped = !_swapped),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: HelixNeutralColors.videoPlaceholder,
                    borderRadius: HelixRadius.card,
                    border: Border.all(
                      color: HelixScrimColors.onBackdropSubtle,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: HelixRadius.card,
                    child: preview,
                  ),
                ),
              ),
            ),
          ),
        PositionedDirectional(
          start: 0,
          end: 0,
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
                  padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
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

class _Surface extends StatelessWidget {
  const _Surface({required this.surface, this.mirror = false});

  final CallVideoSurface surface;
  final bool mirror;

  @override
  Widget build(BuildContext context) => surface.build(mirror: mirror);
}

/// The other person's video, or their avatar while no frames are arriving (the
/// camera is off, or the first frame has not landed yet).
class _RemoteTile extends StatelessWidget {
  const _RemoteTile({
    required this.surface,
    required this.state,
    this.compact = false,
  });

  final CallVideoSurface surface;
  final CallScreenState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: surface.changes,
      builder: (context, _) {
        if (surface.hasFrames) return surface.build();
        return compact
            ? ColoredBox(
                color: HelixNeutralColors.videoPlaceholder,
                child: Center(
                  child: CallAvatar(avatar: state.avatar, diameter: 48),
                ),
              )
            : _AvatarStage(state: state);
      },
    );
  }
}

class _AvatarStage extends StatelessWidget {
  const _AvatarStage({required this.state});

  final CallScreenState state;

  @override
  Widget build(BuildContext context) {
    return CallSurface(
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: CallAvatar(
            avatar: state.avatar,
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
