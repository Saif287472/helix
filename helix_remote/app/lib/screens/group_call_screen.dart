import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:helix_remote_calls/helix_remote_calls.dart';

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({
    super.key,
    required this.service,
    required this.onLeave,
  });

  final RemoteGroupCallService service;
  final VoidCallback onLeave;

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  late StreamSubscription<GroupCallState> _sub;
  GroupCallState? _callState;

  @override
  void initState() {
    super.initState();
    _callState = widget.service.currentState;
    _sub = widget.service.stateStream.listen((s) {
      if (mounted) setState(() => _callState = s);
      if (s.status == GroupCallStatus.ended) widget.onLeave();
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _callState;
    if (state == null || state.status == GroupCallStatus.ended) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Participant grid
            _ParticipantGrid(state: state, service: widget.service),
            // Control bar at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ControlBar(
                state: state,
                onMute: () => widget.service.setMuted(!state.isMuted),
                onScreenShare: () =>
                    widget.service.toggleScreenShare(!state.isScreenSharing),
                onVideo: () => widget.service.setVideoEnabled(!state.isVideo),
                onLeave: () async {
                  await widget.service.leaveRoom();
                  widget.onLeave();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Participant grid (2×2 max)
// ---------------------------------------------------------------------------

class _ParticipantGrid extends StatelessWidget {
  const _ParticipantGrid({required this.state, required this.service});

  final GroupCallState state;
  final RemoteGroupCallService service;

  @override
  Widget build(BuildContext context) {
    final peers = state.peers;

    // Single remote peer: full-screen remote + PiP local.
    if (peers.length == 1) {
      return Stack(
        children: [
          _VideoTile(
            stream: peers[0].remoteStream,
            label: peers[0].participant.accountId,
            isActive:
                state.activeSpeakerDeviceId == peers[0].participant.deviceId,
            isScreenSharing: peers[0].participant.isScreenSharing,
          ),
          Positioned(
            right: 12,
            top: 12,
            width: 100,
            height: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _VideoTile(
                stream: service.localStream,
                label: 'You',
                isActive: false,
                isScreenSharing: state.isScreenSharing,
                isMuted: state.isMuted,
              ),
            ),
          ),
        ],
      );
    }

    // 2-4 peers: equal-sized grid.
    final allTiles = [
      _VideoTile(
        stream: service.localStream,
        label: 'You',
        isActive: false,
        isScreenSharing: state.isScreenSharing,
        isMuted: state.isMuted,
      ),
      for (final p in peers)
        _VideoTile(
          stream: p.remoteStream,
          label: p.participant.accountId,
          isActive: state.activeSpeakerDeviceId == p.participant.deviceId,
          isScreenSharing: p.participant.isScreenSharing,
        ),
    ];

    final crossAxisCount = allTiles.length <= 2 ? 1 : 2;
    return GridView.count(
      crossAxisCount: crossAxisCount,
      physics: const NeverScrollableScrollPhysics(),
      children: allTiles,
    );
  }
}

// ---------------------------------------------------------------------------
// Single video tile
// ---------------------------------------------------------------------------

class _VideoTile extends StatefulWidget {
  const _VideoTile({
    required this.stream,
    required this.label,
    required this.isActive,
    required this.isScreenSharing,
    this.isMuted = false,
  });

  final webrtc.MediaStream? stream;
  final String label;
  final bool isActive;
  final bool isScreenSharing;
  final bool isMuted;

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  final webrtc.RTCVideoRenderer _renderer = webrtc.RTCVideoRenderer();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _renderer.initialize();
    _renderer.srcObject = widget.stream;
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void didUpdateWidget(_VideoTile old) {
    super.didUpdateWidget(old);
    if (old.stream != widget.stream) {
      _renderer.srcObject = widget.stream;
    }
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_initialized && widget.stream != null)
            webrtc.RTCVideoView(
              _renderer,
              objectFit:
                  webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            const Center(
              child: Icon(Icons.person, color: Colors.white54, size: 48),
            ),
          // Active speaker ring
          if (widget.isActive)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent, width: 3),
                ),
              ),
            ),
          // Label + indicators
          Positioned(
            left: 8,
            bottom: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isMuted)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.mic_off,
                      color: Colors.redAccent,
                      size: 16,
                    ),
                  ),
                if (widget.isScreenSharing)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.screen_share,
                      color: Colors.blueAccent,
                      size: 16,
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.label,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Control bar
// ---------------------------------------------------------------------------

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.state,
    required this.onMute,
    required this.onScreenShare,
    required this.onVideo,
    required this.onLeave,
  });

  final GroupCallState state;
  final VoidCallback onMute;
  final VoidCallback onScreenShare;
  final VoidCallback onVideo;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlButton(
            icon: state.isMuted ? Icons.mic_off : Icons.mic,
            label: state.isMuted ? 'Unmute' : 'Mute',
            onTap: onMute,
            active: state.isMuted,
          ),
          if (state.isVideo)
            _ControlButton(
              icon: Icons.videocam,
              label: 'Camera',
              onTap: onVideo,
            ),
          _ControlButton(
            icon: state.isScreenSharing
                ? Icons.stop_screen_share
                : Icons.screen_share,
            label: state.isScreenSharing ? 'Stop Share' : 'Share',
            onTap: onScreenShare,
            active: state.isScreenSharing,
          ),
          _ControlButton(
            icon: Icons.call_end,
            label: 'Leave',
            onTap: onLeave,
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (active ? Colors.white24 : Colors.white12);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: bg,
            child: Icon(
              icon,
              color: color != null ? Colors.white : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
