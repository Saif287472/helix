import 'package:flutter/material.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'package:helix_remote/screens/call/call_format.dart';

/// The calm dark gradient every non-video call layout sits on.
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

/// Large initials avatar with an optional slow pulse ring.
///
/// The ring is decoration only: it is skipped entirely when the platform
/// asks for reduced motion.
class CallAvatar extends StatefulWidget {
  const CallAvatar({
    super.key,
    required this.status,
    required this.diameter,
    this.pulse = false,
  });

  final RemoteCallStatus status;
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
    final status = widget.status;
    final initials = callInitials(status);
    final palette = HelixColorTokens.avatarPalette;
    final seed = status.peerDisplayName ?? status.peerAccountId;
    final fill = initials == null
        ? HelixScrimColors.controlSurface
        : palette[seed.hashCode.abs() % palette.length];
    final diameter = widget.diameter;
    final ringExtent = diameter * 0.28;

    final face = Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: initials == null
          ? Icon(
              Icons.person,
              size: diameter * 0.5,
              color: HelixScrimColors.onBackdrop,
            )
          : Padding(
              padding: HelixInsets.all(diameter * 0.16),
              child: FittedBox(
                child: Text(
                  initials,
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
      label: 'Picture of ${status.displayName}',
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

/// "End-to-end encrypted" with a lock — the reassurance line at the top of
/// every call layout.
class EncryptedCallLabel extends StatelessWidget {
  const EncryptedCallLabel({super.key, this.prefix});

  /// Optional leading text, e.g. "Helix voice call".
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: HelixScrimColors.onBackdropMuted,
    );
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
                'End-to-end encrypted',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The status line: state text, or the running/frozen timer once the call
/// has connected, with a spinner while reconnecting.
class CallStatusLine extends StatelessWidget {
  const CallStatusLine({
    super.key,
    required this.status,
    required this.elapsed,
    this.style,
  });

  final RemoteCallStatus status;

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
    final state = status.state;
    final label = callStateLabel(state);
    final showTimer =
        elapsed != null &&
        (state == RemoteCallState.active || isTerminalCallState(state));
    final spinner = state == RemoteCallState.reconnecting;

    final children = <Widget>[
      if (spinner) ...[
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
          showTimer && state == RemoteCallState.active
              ? formatCallDuration(elapsed!)
              : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle,
        ),
      ),
    ];

    return Semantics(
      liveRegion: true,
      label: showTimer && state == RemoteCallState.active
          ? 'Call duration ${formatCallDuration(elapsed!)}'
          : label,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: children),
          // The frozen timer under a terminal state ("Call ended · 04:12").
          if (showTimer && isTerminalCallState(state))
            Padding(
              padding: HelixInsets.only(top: 2),
              child: Text(
                formatCallDuration(elapsed!),
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

/// Small amber chip shown while the link is weak.
class PoorConnectionChip extends StatelessWidget {
  const PoorConnectionChip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: 'Poor connection',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: HelixCallColors.noticeSurface,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: HelixInsets.symmetric(horizontal: 10, vertical: 4),
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
                  'Poor connection',
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

/// Inline notice for a friendly error or warning sentence.
class CallNotice extends StatelessWidget {
  const CallNotice({super.key, required this.message, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: HelixCallColors.noticeSurface,
          borderRadius: HelixRadius.card,
        ),
        child: Padding(
          padding: HelixInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.info_outline,
                size: 18,
                color: isError
                    ? HelixCallColors.endCall
                    : HelixStatusColors.caution,
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
            ],
          ),
        ),
      ),
    );
  }
}
