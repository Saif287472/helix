import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'package:helix_remote/screens/call/call_controls.dart';
import 'package:helix_remote/screens/call/call_format.dart';
import 'package:helix_remote/screens/call/call_parts.dart';
import 'package:helix_remote/screens/call/incoming_call_view.dart';
import 'package:helix_remote/screens/call/video_call_view.dart';

/// The 1:1 call screen for every [RemoteCallState].
///
/// - Incoming ringing: full-screen answer surface (Decline / Accept, and
///   optionally Message).
/// - Outgoing and voice calls: avatar, name, status or timer, and a compact
///   one-row control tray.
/// - Video: full-bleed remote video with a draggable self preview; the
///   controls fade out after a few seconds and come back on tap.
/// - Terminal states: the final word ("Call ended") with the timer frozen
///   and every control disabled.
///
/// Back minimises the call through [onMinimize] and never pops the screen
/// on its own while a minimise target exists; on the incoming screen back
/// does nothing.
class CallScreen extends StatefulWidget {
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
    this.onMinimize,
    this.peerSubtitle,
    this.onMessage,
  });

  final RemoteCallStatus callStatus;
  final VoidCallback? onAccept;
  final VoidCallback onDecline;
  final VoidCallback onEnd;
  final void Function({required bool muted})? onMute;
  final void Function({required bool enabled})? onSpeaker;
  final void Function({required bool enabled})? onVideo;
  final VoidCallback? onSwitchCamera;

  /// Collapse back to the app while the call continues.
  final VoidCallback? onMinimize;

  /// Secondary line under the name, e.g. the peer's phone number.
  final String? peerSubtitle;

  /// Incoming screen only: decline and open the chat with the caller.
  final VoidCallback? onMessage;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  static const _autoHideDelay = Duration(seconds: 4);

  Timer? _ticker;
  Timer? _hideTimer;
  bool _controlsVisible = true;

  /// The call length captured when the call reached a terminal state, so the
  /// timer stops instead of counting on under "Call ended".
  Duration? _frozenElapsed;

  RemoteCallStatus get _status => widget.callStatus;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && isConnectedCallState(_status.state)) setState(() {});
    });
    if (isTerminalCallState(_status.state)) _freeze();
    _syncAutoHide();
  }

  @override
  void didUpdateWidget(CallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.callStatus;
    if (old.callId != _status.callId) {
      _frozenElapsed = null;
      _controlsVisible = true;
    }
    if (isTerminalCallState(_status.state) &&
        (!isTerminalCallState(old.state) || old.callId != _status.callId)) {
      _freeze();
    }
    if (_autoHideEligible(old) != _autoHideEligible(_status)) {
      _controlsVisible = true;
      _syncAutoHide();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _freeze() {
    final startedAt = _status.startedAt;
    _frozenElapsed = startedAt == null
        ? null
        : DateTime.now().difference(startedAt);
  }

  Duration? get _elapsed {
    if (isTerminalCallState(_status.state)) return _frozenElapsed;
    final startedAt = _status.startedAt;
    if (startedAt == null || !isConnectedCallState(_status.state)) {
      return null;
    }
    return DateTime.now().difference(startedAt);
  }

  /// Controls only auto-hide over live remote video on a connected call.
  bool _autoHideEligible(RemoteCallStatus status) =>
      status.isVideo &&
      status.state == RemoteCallState.active &&
      status.remoteRenderer != null;

  void _syncAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_autoHideEligible(_status) || !_controlsVisible) return;
    _hideTimer = Timer(_autoHideDelay, () {
      if (!mounted || !_autoHideEligible(_status)) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    _syncAutoHide();
  }

  void _noteInteraction() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _syncAutoHide();
  }

  void _handleBack(bool didPop, Object? _) {
    if (didPop || isIncomingRinging(_status)) return;
    widget.onMinimize?.call();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final incoming = isIncomingRinging(status);

    final Widget body;
    if (incoming) {
      body = IncomingCallView(
        status: status,
        onAccept: widget.onAccept,
        onDecline: widget.onDecline,
        peerSubtitle: widget.peerSubtitle,
        onMessage: widget.onMessage,
      );
    } else if (_showsVideoLayout(status)) {
      body = _buildVideo(context);
    } else {
      body = _buildVoice(context);
    }

    return PopScope(
      canPop: !incoming && widget.onMinimize == null,
      onPopInvokedWithResult: _handleBack,
      child: Material(color: HelixCallColors.surfaceBottom, child: body),
    );
  }

  /// Full-bleed video once the peer's stream exists, or while your own
  /// camera previews before the call connects.
  bool _showsVideoLayout(RemoteCallStatus status) {
    if (!status.isVideo || isTerminalCallState(status.state)) return false;
    if (isConnectedCallState(status.state) && status.remoteRenderer != null) {
      return true;
    }
    return status.localRenderer != null && status.isLocalVideoEnabled;
  }

  bool get _finished => isTerminalCallState(_status.state);

  bool get _poorConnection => !_finished && (_status.quality?.isWeak ?? false);

  Widget? _notice() {
    // While the link is merely weak the chip says it; the sentence would
    // repeat it at twice the size.
    if (_poorConnection) return null;
    final message = friendlyCallError(_status.errorMessage);
    if (message == null) return null;
    return CallNotice(message: message, isError: _finished);
  }

  Widget _tray() {
    final status = _status;
    return Listener(
      onPointerDown: (_) => _noteInteraction(),
      child: CallControlTray(
        controls: buildCallControls(
          status: status,
          finished: _finished,
          onEnd: widget.onEnd,
          onMute: widget.onMute,
          onSpeaker: widget.onSpeaker,
          onVideo: widget.onVideo,
          onSwitchCamera: widget.onSwitchCamera,
        ),
      ),
    );
  }

  Widget _minimiseButton() {
    if (widget.onMinimize == null) return const SizedBox(width: 48);
    return IconButton(
      tooltip: 'Minimise call',
      onPressed: widget.onMinimize,
      color: HelixScrimColors.onBackdrop,
      icon: const Icon(Icons.keyboard_arrow_down),
    );
  }

  Widget _buildVoice(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    final subtitle = widget.peerSubtitle?.trim() ?? '';
    final notice = _notice();
    final pulse =
        status.state == RemoteCallState.dialing ||
        status.state == RemoteCallState.ringing ||
        status.state == RemoteCallState.preparing;

    return CallSurface(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: HelixInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  _minimiseButton(),
                  Expanded(
                    child: EncryptedCallLabel(
                      prefix: status.isVideo
                          ? 'Helix video call'
                          : 'Helix voice call',
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final avatar = (constraints.maxHeight * 0.36).clamp(
                    64.0,
                    136.0,
                  );
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                        minWidth: constraints.maxWidth,
                      ),
                      child: Padding(
                        padding: HelixInsets.symmetric(
                          horizontal: HelixSpace.lg,
                          vertical: HelixSpace.xs,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CallAvatar(
                              status: status,
                              diameter: avatar,
                              pulse: pulse,
                            ),
                            const SizedBox(height: 12),
                            Semantics(
                              header: true,
                              child: Text(
                                status.displayName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: HelixScrimColors.onBackdrop,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Padding(
                                padding: HelixInsets.only(top: 2),
                                child: Text(
                                  subtitle,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: HelixScrimColors.onBackdropMuted,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            CallStatusLine(status: status, elapsed: _elapsed),
                            if (status.isVideo &&
                                !status.isLocalVideoEnabled &&
                                !_finished)
                              Padding(
                                padding: HelixInsets.only(top: 6),
                                child: Text(
                                  'Camera off',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: HelixScrimColors.onBackdropFaint,
                                  ),
                                ),
                              ),
                            if (_poorConnection)
                              Padding(
                                padding: HelixInsets.only(top: 10),
                                child: const PoorConnectionChip(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (notice != null)
              Padding(
                padding: HelixInsets.fromLTRB(16, 0, 16, 10),
                child: notice,
              ),
            Padding(
              padding: HelixInsets.fromLTRB(12, 0, 12, 12),
              child: _tray(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideo(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    final visible = !_autoHideEligible(status) || _controlsVisible;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _minimiseButton(),
        Expanded(
          child: Padding(
            padding: HelixInsets.only(top: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    status.displayName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: HelixScrimColors.onBackdrop,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                CallStatusLine(
                  status: status,
                  elapsed: _elapsed,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: HelixScrimColors.onBackdropMuted,
                  ),
                ),
                if (_poorConnection)
                  Padding(
                    padding: HelixInsets.only(top: 6),
                    child: const PoorConnectionChip(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );

    return VideoCallView(
      status: status,
      header: header,
      tray: _tray(),
      notice: _notice(),
      controlsVisible: visible,
      onStageTap: _toggleControls,
    );
  }
}
