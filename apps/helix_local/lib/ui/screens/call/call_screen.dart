// lib/ui/screens/call/call_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:helix_domain/domain/call/call_state.dart';
import 'package:helix/providers/app_providers.dart';

/// Full-screen overlay shown for incoming, outgoing, and active calls.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, required this.call});

  final CallState call;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  late final AnimationController _pulseController;
  bool _localIsMain = false;
  Offset _pipOffset = const Offset(16, 80);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    if (widget.call.isActive && widget.call.startedAt != null) {
      _startTimer(widget.call.startedAt!);
    }
  }

  @override
  void didUpdateWidget(CallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final became = widget.call.status;
    final was = oldWidget.call.status;
    if (became == CallStatus.active &&
        was != CallStatus.active &&
        widget.call.startedAt != null) {
      _startTimer(widget.call.startedAt!);
    }
    if (widget.call.isEnded) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer(DateTime startedAt) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed = DateTime.now().difference(startedAt));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  bool get _isPulsing {
    switch (widget.call.status) {
      case CallStatus.offering:
      case CallStatus.ringing:
      case CallStatus.connecting:
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final isIncomingRinging =
        call.direction == CallDirection.incoming &&
        call.status == CallStatus.ringing;

    final svc = ref.watch(callServiceProvider);
    final showRemoteVideo = call.isRemoteVideoEnabled && svc.remoteVideoRenderer != null;
    final showLocalVideo = call.isVideoEnabled && svc.localVideoRenderer != null;
    final isVideo = showRemoteVideo || showLocalVideo;

    final textStyleShadow = isVideo
        ? const [Shadow(color: Colors.black87, blurRadius: 8.0, offset: Offset(0, 2))]
        : null;

    final mainRenderer = (_localIsMain && showLocalVideo)
        ? svc.localVideoRenderer!
        : (showRemoteVideo ? svc.remoteVideoRenderer! : (showLocalVideo ? svc.localVideoRenderer! : null));
    // Only mirror local video when the front ("selfie") camera is active —
    // the rear camera should display normally, like a regular viewfinder.
    final mirrorMain =
        mainRenderer == svc.localVideoRenderer && call.isFrontCamera;

    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Stack(
          children: [
            if (isVideo && mainRenderer != null)
              Positioned.fill(
                child: RTCVideoView(
                  mainRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: mirrorMain,
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 80),
                if (!isVideo)
                  _Avatar(
                    peerDisplayName: call.peerDisplayName,
                    pulse: _isPulsing,
                    controller: _pulseController,
                  ),
                const SizedBox(height: 24),
                Text(
                  call.peerDisplayName,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: textStyleShadow,
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _statusLabel(call),
                    key: ValueKey(_statusLabel(call)),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                      shadows: textStyleShadow,
                    ),
                  ),
                ),
                const Spacer(),
                if (!call.isEnded)
                  isIncomingRinging
                      ? _IncomingControlsRow(call: call)
                      : _ControlsRow(call: call, elapsed: _elapsed),
                const SizedBox(height: 56),
              ],
            ),
            if (showRemoteVideo && showLocalVideo)
              Positioned(
                left: _pipOffset.dx,
                top: _pipOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      final size = MediaQuery.of(context).size;
                      final newX = (_pipOffset.dx + details.delta.dx)
                          .clamp(8.0, (size.width - 108.0).clamp(8.0, double.infinity));
                      final newY = (_pipOffset.dy + details.delta.dy)
                          .clamp(8.0, (size.height - 148.0).clamp(8.0, double.infinity));
                      _pipOffset = Offset(newX, newY);
                    });
                  },
                  onTap: () => setState(() => _localIsMain = !_localIsMain),
                  child: Container(
                    width: 100,
                    height: 140,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white54, width: 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RTCVideoView(
                      _localIsMain ? svc.remoteVideoRenderer! : svc.localVideoRenderer!,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      mirror: !_localIsMain && call.isFrontCamera,
                    ),
                  ),
                ),
              ),
            if (!isIncomingRinging)
              Positioned(
                top: 8,
                left: 8,
                child: _MinimizeButton(),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(CallState call) {
    switch (call.status) {
      case CallStatus.offering:
        return 'Calling…';
      case CallStatus.ringing:
        return call.direction == CallDirection.outgoing
            ? 'Ringing…'
            : 'Incoming call';
      case CallStatus.connecting:
        return 'Connecting…';
      case CallStatus.active:
        return _fmt(_elapsed);
      case CallStatus.ending:
        return 'Ending call…';
      case CallStatus.ended:
        switch (call.endReason) {
          case CallEndReason.declined:
            return 'Call declined';
          case CallEndReason.noAnswer:
            return 'No answer';
          case CallEndReason.busy:
            return 'Line busy';
          case null:
            return 'Call ended';
        }
      case CallStatus.failed:
        return 'Call failed';
      case CallStatus.idle:
        return '';
    }
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ---------------------------------------------------------------------------

class _MinimizeButton extends ConsumerWidget {
  const _MinimizeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      onPressed: () => ref.read(callMinimizedProvider.notifier).state = true,
      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
      tooltip: 'Minimize',
    );
  }
}

// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.peerDisplayName,
    required this.pulse,
    required this.controller,
  });

  final String peerDisplayName;
  final bool pulse;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final initials = peerDisplayName.isNotEmpty
        ? peerDisplayName.characters.first.toUpperCase()
        : '?';
    final avatar = CircleAvatar(
      radius: 56,
      backgroundColor: Colors.white24,
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );

    if (!pulse) return avatar;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final scale = 0.95 + (controller.value * 0.1);
        return Transform.scale(scale: scale, child: child);
      },
      child: avatar,
    );
  }
}

// ---------------------------------------------------------------------------

class _IncomingControlsRow extends ConsumerWidget {
  const _IncomingControlsRow({required this.call});

  final CallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(callServiceProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CircleButton(
          icon: Icons.call_end,
          label: 'Decline',
          onTap: () => svc.declineIncomingCall(),
          fillColor: Colors.red,
          size: 72,
        ),
        _CircleButton(
          icon: Icons.call,
          label: 'Accept',
          onTap: () => svc.acceptIncomingCall(),
          fillColor: Colors.green,
          size: 72,
        ),
      ],
    );
  }
}

class _ControlsRow extends ConsumerWidget {
  const _ControlsRow({required this.call, required this.elapsed});

  final CallState call;
  final Duration elapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(callServiceProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CircleButton(
              icon: call.isMuted ? Icons.mic_off : Icons.mic,
              label: call.isMuted ? 'Unmute' : 'Mute',
              onTap: () => svc.toggleMute(),
              // Highlighted when muted — the state that differs from default.
              active: call.isMuted,
            ),
            const SizedBox(width: 16),
            _CircleButton(
              icon: call.isVideoEnabled ? Icons.videocam : Icons.videocam_off,
              label: call.isVideoEnabled ? 'Cam Off' : 'Cam On',
              onTap: () => svc.toggleVideo(),
              // A video call's default state is camera-on, so highlight the
              // button for the state that differs from that default
              // (camera off) instead — otherwise it'd render as a solid
              // white circle with an invisible white icon for the entire
              // (most common) duration of any video call.
              active: !call.isVideoEnabled,
            ),
            const SizedBox(width: 16),
            _CircleButton(
              icon: Icons.call_end,
              label: 'End',
              onTap: () => svc.endCurrentCall(),
              fillColor: Colors.red,
              size: 72,
            ),
            const SizedBox(width: 16),
            _CircleButton(
              icon: call.isSpeakerOn ? Icons.volume_up : Icons.hearing,
              label: call.isSpeakerOn ? 'Speaker' : 'Earpiece',
              onTap: () => svc.toggleSpeaker(),
              // Highlighted when speakerphone is on — the non-default state.
              active: call.isSpeakerOn,
            ),
            if (call.isVideoEnabled) ...[
              const SizedBox(width: 16),
              _CircleButton(
                icon: Icons.cameraswitch,
                label: 'Flip',
                onTap: () => svc.switchCamera(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.fillColor,
    this.size = 56,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Highlighted ("engaged") state — rendered as a solid white circle with
  /// a dark icon, the way other calling apps indicate a control that's been
  /// actively toggled away from its default (e.g. mute, speakerphone).
  /// Ignored when [fillColor] is set.
  final bool active;

  /// Fixed solid background for action buttons that always look the same
  /// regardless of state (End call, Accept, Decline) — always paired with
  /// a white icon. Takes precedence over [active].
  final Color? fillColor;

  final double size;

  @override
  Widget build(BuildContext context) {
    final background =
        fillColor ??
        (active ? Colors.white : Colors.white.withValues(alpha: 0.18));
    final iconColor = fillColor != null
        ? Colors.white
        : (active ? Colors.black87 : Colors.white);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: background,
            ),
            child: Icon(icon, color: iconColor, size: size * 0.5),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
