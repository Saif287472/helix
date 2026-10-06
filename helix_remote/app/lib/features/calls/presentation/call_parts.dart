import 'package:flutter/material.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/call_screen_state.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The calm dark gradient every call layout without video sits on.
class CallSurface extends StatelessWidget {
  const CallSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [HelixCallColors.surfaceTop, HelixCallColors.surfaceBottom],
        ),
      ),
      child: child,
    );
  }
}

/// A large avatar for the call screens: the person's initials on their
/// palette colour, with an optional slow pulse while a call rings. The pulse
/// is decoration only and is skipped when the platform asks for reduced
/// motion.
class CallAvatar extends StatefulWidget {
  const CallAvatar({
    super.key,
    required this.avatar,
    required this.diameter,
    this.pulse = false,
  });

  final HelixAvatarModel avatar;
  final double diameter;
  final bool pulse;

  @override
  State<CallAvatar> createState() => _CallAvatarState();
}

class _CallAvatarState extends State<CallAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool get _shouldAnimate =>
      widget.pulse && !MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(CallAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (_shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = widget.avatar;
    final palette = HelixColorTokens.avatarPalette;
    final fill = palette[avatar.colorIndex.abs() % palette.length];
    final diameter = widget.diameter;
    final ringExtent = diameter * 0.28;

    final face = Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(diameter * 0.16),
        child: FittedBox(
          child: Text(
            avatar.initials,
            style: TextStyle(
              fontSize: diameter * 0.36,
              fontWeight: FontWeight.w600,
              color: HelixScrimColors.onBackdrop,
            ),
          ),
        ),
      ),
    );

    return Semantics(
      image: true,
      label: 'Picture of ${avatar.name}',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: diameter + ringExtent * 2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (widget.pulse)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  if (!_controller.isAnimating) return const SizedBox.shrink();
                  return Container(
                    width: diameter + ringExtent * 2 * t,
                    height: diameter + ringExtent * 2 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HelixScrimColors.onBackdrop.withValues(
                        alpha: 0.16 * (1 - t),
                      ),
                    ),
                  );
                },
              ),
            face,
          ],
        ),
      ),
    );
  }
}

/// "End-to-end encrypted" with a lock: the reassurance line at the top of
/// every call layout.
class EncryptedCallLabel extends StatelessWidget {
  const EncryptedCallLabel({super.key, this.prefix});

  /// Optional leading text, e.g. "Helix voice call".
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prefix != null)
          Text(
            prefix!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: HelixScrimColors.onBackdrop,
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock,
              size: 12,
              color: HelixScrimColors.onBackdropMuted,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                CallCopy.encrypted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: HelixScrimColors.onBackdropMuted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The status line: the state in words, or the running timer once the call
/// connected, with a spinner while reconnecting and the frozen talk time under
/// an ended call.
class CallStatusLine extends StatelessWidget {
  const CallStatusLine({
    super.key,
    required this.state,
    required this.elapsed,
    this.style,
  });

  final CallScreenState state;

  /// Time since connection, or null before the call connected.
  final Duration? elapsed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle =
        style ??
        theme.textTheme.titleMedium?.copyWith(
          color: HelixScrimColors.onBackdropMuted,
        );
    final timerShown =
        elapsed != null &&
        state.stage == CallStage.active &&
        state.quality != CallQuality.reconnecting;
    final text = timerShown ? formatCallDuration(elapsed!) : state.statusText;
    final reconnecting = state.quality == CallQuality.reconnecting;
    final frozen = state.stage == CallStage.ended ? state.talkTime : null;

    return Semantics(
      liveRegion: true,
      label: timerShown ? 'Call duration $text' : text,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (reconnecting) ...[
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: HelixScrimColors.onBackdropMuted,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  text,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                ),
              ),
            ],
          ),
          if (frozen != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                formatCallDuration(frozen),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: HelixScrimColors.onBackdropFaint,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small amber chip shown while the link is weak.
class PoorConnectionChip extends StatelessWidget {
  const PoorConnectionChip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: CallCopy.poorConnection,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: HelixCallColors.noticeSurface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.network_check,
                size: 14,
                color: HelixStatusColors.caution,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  CallCopy.poorConnection,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: HelixScrimColors.onBackdrop,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An inline notice for a refusal or failure, with a dismiss button.
class CallNoticeBar extends StatelessWidget {
  const CallNoticeBar({super.key, required this.message, this.onDismiss});

  final String message;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: HelixCallColors.noticeSurface,
          borderRadius: HelixRadius.card,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 14,
            top: 4,
            bottom: 4,
            end: 4,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.error_outline,
                size: 18,
                color: HelixStatusColors.caution,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: HelixScrimColors.onBackdrop,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: HelixScrimColors.onBackdropMuted,
                  ),
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One control in the in-call tray.
class CallControl {
  const CallControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.toggled,
    this.danger = false,
  });

  final IconData icon;

  /// The short word under the button ("Mute").
  final String label;

  /// What the button will do, for the tooltip and screen readers
  /// ("Unmute microphone"). Defaults to [label].
  final String? tooltip;
  final VoidCallback? onPressed;

  /// Non-null for a toggle; true paints the button filled.
  final bool? toggled;

  /// The red hang-up button.
  final bool danger;
}

/// A round button with its label underneath. Used by the tray and by the
/// incoming screen's big Accept / Decline pair.
class CallRoundButton extends StatelessWidget {
  const CallRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.diameter,
    this.tooltip,
    this.toggled,
    this.fill,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double diameter;
  final bool? toggled;

  /// Overrides the idle/toggled fill (Accept, Decline, End).
  final Color? fill;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final isOn = toggled ?? false;
    final background = !enabled
        ? (fill == null
              ? HelixScrimColors.controlSurface
              : HelixCallColors.controlDisabled)
        : fill ??
              (isOn
                  ? HelixCallColors.controlToggled
                  : HelixCallColors.controlIdle);
    final foreground = !enabled
        ? HelixScrimColors.onBackdropFaint
        : iconColor ??
              (isOn && fill == null
                  ? HelixCallColors.onControlToggled
                  : HelixScrimColors.onBackdrop);
    final size = diameter < 48 ? 48.0 : diameter;

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      toggled: toggled,
      label: tooltip ?? label,
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip ?? label,
        excludeFromSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: background,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: SizedBox.square(
                  dimension: size,
                  child: Icon(icon, color: foreground, size: size * 0.44),
                ),
              ),
            ),
            // The label is part of the target, so a tap on the word works.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPressed,
              child: SizedBox(
                width: size + 16,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: enabled
                            ? HelixScrimColors.onBackdrop
                            : HelixScrimColors.onBackdropFaint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The compact rounded tray: exactly one row of evenly spaced controls, sized
/// from the available width so five buttons fit a 360 dp phone.
class CallControlTray extends StatelessWidget {
  const CallControlTray({super.key, required this.controls});

  final List<CallControl> controls;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: HelixCallColors.controlPanel,
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / controls.length;
            final diameter = (slot - 12).clamp(48.0, 60.0);
            // Top-aligned so a label shrunk by FittedBox never nudges its
            // button off the shared row.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final control in controls)
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: CallRoundButton(
                        icon: control.icon,
                        label: control.label,
                        tooltip: control.tooltip,
                        onPressed: control.onPressed,
                        toggled: control.toggled,
                        diameter: diameter,
                        fill: control.danger && control.onPressed != null
                            ? HelixCallColors.endCall
                            : null,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
