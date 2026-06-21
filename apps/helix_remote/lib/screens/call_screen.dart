import 'package:flutter/material.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

class CallScreen extends StatelessWidget {
  const CallScreen({
    super.key,
    required this.callStatus,
    this.onAccept,
    required this.onDecline,
    required this.onEnd,
    this.onMute,
  });

  final RemoteCallStatus callStatus;
  final VoidCallback? onAccept;
  final VoidCallback onDecline;
  final VoidCallback onEnd;
  final void Function({required bool muted})? onMute;

  @override
  Widget build(BuildContext context) {
    if (callStatus.state == RemoteCallState.ringing &&
        callStatus.direction == kCallDirectionIncoming) {
      return _IncomingCallOverlay(
        callStatus: callStatus,
        onAccept: onAccept,
        onDecline: onDecline,
      );
    }
    return _ActiveCallOverlay(
      callStatus: callStatus,
      onEnd: onEnd,
      onMute: onMute,
    );
  }
}

class _IncomingCallOverlay extends StatelessWidget {
  const _IncomingCallOverlay({
    required this.callStatus,
    required this.onAccept,
    required this.onDecline,
  });

  final RemoteCallStatus callStatus;
  final VoidCallback? onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withAlpha(230),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              callStatus.isVideo ? Icons.video_call : Icons.call,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Incoming ${callStatus.isVideo ? 'video' : 'audio'} call',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(callStatus.peerId, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallActionButton(
                  icon: Icons.call_end,
                  label: 'Decline',
                  color: Colors.red,
                  onPressed: onDecline,
                ),
                _CallActionButton(
                  icon: Icons.call,
                  label: 'Accept',
                  color: Colors.green,
                  onPressed: onAccept,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveCallOverlay extends StatefulWidget {
  const _ActiveCallOverlay({
    required this.callStatus,
    required this.onEnd,
    required this.onMute,
  });

  final RemoteCallStatus callStatus;
  final VoidCallback onEnd;
  final void Function({required bool muted})? onMute;

  @override
  State<_ActiveCallOverlay> createState() => _ActiveCallOverlayState();
}

class _ActiveCallOverlayState extends State<_ActiveCallOverlay> {
  bool _muted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.callStatus.state == RemoteCallState.offering
        ? 'Calling…'
        : 'Connected';

    return Material(
      color: theme.colorScheme.surface.withAlpha(230),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.callStatus.isVideo ? Icons.video_call : Icons.call,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(label, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(widget.callStatus.peerId, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CallActionButton(
                  icon: _muted ? Icons.mic_off : Icons.mic,
                  label: _muted ? 'Unmute' : 'Mute',
                  color: Colors.grey,
                  onPressed: widget.onMute == null
                      ? null
                      : () {
                          setState(() => _muted = !_muted);
                          widget.onMute!(muted: _muted);
                        },
                ),
                _CallActionButton(
                  icon: Icons.call_end,
                  label: 'End',
                  color: Colors.red,
                  onPressed: widget.onEnd,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: label,
          backgroundColor: onPressed != null ? color : Colors.grey,
          onPressed: onPressed,
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}
