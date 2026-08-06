import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'dart:async';

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
    this.onSpeaker,
    this.onVideo,
    this.onSwitchCamera,
  });

  final RemoteCallStatus callStatus;
  final VoidCallback? onAccept;
  final VoidCallback onDecline;
  final VoidCallback onEnd;
  final void Function({required bool muted})? onMute;
  final void Function({required bool enabled})? onSpeaker;
  final void Function({required bool enabled})? onVideo;
  final VoidCallback? onSwitchCamera;

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
      onSpeaker: onSpeaker,
      onVideo: onVideo,
      onSwitchCamera: onSwitchCamera,
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
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 44,
              child: Icon(
                callStatus.isVideo ? Icons.video_call : Icons.call,
                size: 48,
              ),
            ),
            const SizedBox(height: 18),
            Text('Ringing', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              'Incoming ${callStatus.isVideo ? 'video' : 'audio'} call',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(callStatus.displayName, style: theme.textTheme.bodyLarge),
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
    required this.onSpeaker,
    required this.onVideo,
    required this.onSwitchCamera,
  });

  final RemoteCallStatus callStatus;
  final VoidCallback onEnd;
  final void Function({required bool muted})? onMute;
  final void Function({required bool enabled})? onSpeaker;
  final void Function({required bool enabled})? onVideo;
  final VoidCallback? onSwitchCamera;

  @override
  State<_ActiveCallOverlay> createState() => _ActiveCallOverlayState();
}

class _ActiveCallOverlayState extends State<_ActiveCallOverlay> {
  Offset _previewOffset = const Offset(20, 72);
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    _durationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.callStatus;
    final hasRemoteVideo =
        status.isVideo &&
        status.remoteRenderer != null &&
        status.state == RemoteCallState.active;
    final hasLocalPreview =
        status.isVideo &&
        status.isLocalVideoEnabled &&
        status.localRenderer != null;

    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: hasRemoteVideo
                ? RemoteCallVideoView(renderer: status.remoteRenderer!)
                : _VideoPlaceholder(status: status),
          ),
          if (hasLocalPreview)
            Positioned(
              left: _previewOffset.dx,
              top: _previewOffset.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  final size = MediaQuery.sizeOf(context);
                  setState(() {
                    _previewOffset = Offset(
                      (_previewOffset.dx + details.delta.dx).clamp(
                        8,
                        size.width - 132,
                      ),
                      (_previewOffset.dy + details.delta.dy).clamp(
                        48,
                        size.height - 196,
                      ),
                    );
                  });
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 124,
                    height: 168,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: RemoteCallVideoView(
                        renderer: status.localRenderer!,
                        mirror: status.isFrontCamera,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: HelixInsets.all(20),
              child: Column(
                children: [
                  _CallHeader(status: status),
                  const Spacer(),
                  if (status.errorMessage != null)
                    _CallErrorBanner(message: status.errorMessage!),
                  const SizedBox(height: 16),
                  _CallControls(
                    status: status,
                    onEnd: widget.onEnd,
                    onMute: widget.onMute,
                    onSpeaker: widget.onSpeaker,
                    onVideo: widget.onVideo,
                    onSwitchCamera: widget.onSwitchCamera,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({required this.status});

  final RemoteCallStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          status.displayName,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          _stateLabel(status.state),
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
        ),
        if (status.startedAt != null && status.state == RemoteCallState.active)
          Padding(
            padding: HelixInsets.only(top: 6),
            child: Text(
              _formatDuration(DateTime.now().difference(status.startedAt!)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
          ),
      ],
    );
  }

  String _stateLabel(RemoteCallState state) {
    return switch (state) {
      RemoteCallState.preparing || RemoteCallState.dialing => 'Calling',
      RemoteCallState.ringing => 'Ringing',
      RemoteCallState.connecting => 'Connecting',
      RemoteCallState.active => 'Connected',
      RemoteCallState.reconnecting => 'Reconnecting',
      RemoteCallState.busy => 'Busy',
      RemoteCallState.declined => 'Declined',
      RemoteCallState.failed => 'Failed',
      RemoteCallState.ended => 'Ended',
    };
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    return hours > 0
        ? '$hours:$minutes:$seconds'
        : '${duration.inMinutes}:$seconds';
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({required this.status});

  final RemoteCallStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: HelixColorTokens.cFF101418,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 54,
              backgroundColor: Colors.white12,
              child: Text(
                status.displayName.isEmpty
                    ? '?'
                    : status.displayName.characters.first.toUpperCase(),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              status.isVideo && !status.isLocalVideoEnabled
                  ? 'Camera off'
                  : status.isVideo
                  ? 'Waiting for video'
                  : 'Audio call',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallErrorBanner extends StatelessWidget {
  const _CallErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(220),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: HelixInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.status,
    required this.onEnd,
    required this.onMute,
    required this.onSpeaker,
    required this.onVideo,
    required this.onSwitchCamera,
  });

  final RemoteCallStatus status;
  final VoidCallback onEnd;
  final void Function({required bool muted})? onMute;
  final void Function({required bool enabled})? onSpeaker;
  final void Function({required bool enabled})? onVideo;
  final VoidCallback? onSwitchCamera;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 14,
      children: [
        _CallActionButton(
          icon: status.isMuted ? Icons.mic_off : Icons.mic,
          label: status.isMuted ? 'Unmute' : 'Mute',
          color: Colors.white24,
          onPressed: onMute == null
              ? null
              : () => onMute!(muted: !status.isMuted),
        ),
        _CallActionButton(
          icon: status.isSpeakerOn ? Icons.volume_up : Icons.hearing,
          label: status.isSpeakerOn ? 'Speaker' : 'Earpiece',
          color: Colors.white24,
          onPressed: onSpeaker == null
              ? null
              : () => onSpeaker!(enabled: !status.isSpeakerOn),
        ),
        if (status.isVideo)
          _CallActionButton(
            icon: status.isLocalVideoEnabled
                ? Icons.videocam
                : Icons.videocam_off,
            label: status.isLocalVideoEnabled ? 'Video' : 'Video off',
            color: Colors.white24,
            onPressed: onVideo == null
                ? null
                : () => onVideo!(enabled: !status.isLocalVideoEnabled),
          ),
        if (status.isVideo)
          _CallActionButton(
            icon: Icons.cameraswitch,
            label: 'Switch',
            color: Colors.white24,
            onPressed: onSwitchCamera,
          ),
        _CallActionButton(
          icon: Icons.call_end,
          label: 'End',
          color: Colors.red,
          onPressed: onEnd,
        ),
      ],
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
          heroTag: 'call_$label',
          backgroundColor: onPressed != null ? color : Colors.grey,
          onPressed: onPressed,
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
