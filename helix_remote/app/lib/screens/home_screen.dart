import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/call_screen.dart';
import 'package:helix_remote/screens/calls_tab_screen.dart';
import 'package:helix_remote/screens/conversation_list_screen.dart';
import 'package:helix_remote/screens/conversation_screen.dart';
import 'package:helix_remote/screens/settings_screen.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_groups/helix_remote_groups.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.root, this.onChangeServerUrl});

  final RemoteCompositionRoot root;
  final Future<void> Function()? onChangeServerUrl;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  StreamSubscription<RemoteCallStatus?>? _callSub;
  bool _callScreenShowing = false;

  /// The tabs are pages side by side: swipe left/right between them, or tap
  /// the bar below.
  final PageController _pages = PageController();

  /// The call running now, shown as a "return to call" bar while its
  /// screen is minimised.
  RemoteCallStatus? _liveCall;

  @override
  void initState() {
    super.initState();
    _callSub = widget.root.callService.callStatusChanges.listen(_onCallStatus);
    // A call already ringing or connected when Home appears (the app was
    // opened from the call notification) is shown at once.
    final active = widget.root.callService.activeCall;
    if (active != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onCallStatus(active),
      );
    }
  }

  static bool _isLive(RemoteCallStatus status) => switch (status.state) {
    RemoteCallState.declined ||
    RemoteCallState.busy ||
    RemoteCallState.failed ||
    RemoteCallState.ended => false,
    _ => true,
  };

  void _onCallStatus(RemoteCallStatus? status) {
    if (!mounted) return;
    final live = status != null && _isLive(status) ? status : null;
    if (live?.callId != _liveCall?.callId ||
        (live == null) != (_liveCall == null)) {
      setState(() => _liveCall = live);
    } else {
      _liveCall = live;
    }
    // Only a live call opens the screen - ringing included. A call that is
    // already over never pops a screen up just to say so.
    if (live != null && !_callScreenShowing) _openCallScreen(live);
  }

  void _openCallScreen(RemoteCallStatus status) {
    _callScreenShowing = true;
    AppLogger.instance.info(
      'CALL_NAV',
      'pushing call screen state=${status.state.name} '
          'direction=${status.direction}',
    );
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/call'),
            fullscreenDialog: true,
            builder: (_) => _CallScreenWrapper(root: widget.root),
          ),
        )
        .then((_) {
          _callScreenShowing = false;
          if (mounted) setState(() {});
        });
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() => _tab = index);
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          if (_liveCall != null && !_callScreenShowing)
            _ReturnToCallBar(
              status: _liveCall!,
              onTap: () => _openCallScreen(_liveCall!),
            ),
          Expanded(
            // The bar already covers the status bar area.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: _liveCall != null && !_callScreenShowing,
              child: PageView(
                controller: _pages,
                onPageChanged: (index) => setState(() => _tab = index),
                children: [
                  for (final page in <Widget>[
                    ConversationListScreen(
                      messagingService: widget.root.messagingService,
                      root: widget.root,
                    ),
                    CallsTabScreen(
                      root: widget.root,
                      messagingService: widget.root.messagingService,
                    ),
                    SettingsScreen(
                      root: widget.root,
                      messagingService: widget.root.messagingService,
                      onChangeServerUrl: widget.onChangeServerUrl,
                    ),
                  ])
                    _KeepAlivePage(child: page),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 74,
        backgroundColor: cs.surface,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: cs.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Calls',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// The bar across the top while a call's screen is minimised - tap to go
/// back to it, like the phone app's "return to call".
class _ReturnToCallBar extends StatefulWidget {
  const _ReturnToCallBar({required this.status, required this.onTap});

  final RemoteCallStatus status;
  final VoidCallback onTap;

  @override
  State<_ReturnToCallBar> createState() => _ReturnToCallBarState();
}

class _ReturnToCallBarState extends State<_ReturnToCallBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _label {
    final started = widget.status.startedAt;
    if (widget.status.state != RemoteCallState.active || started == null) {
      return switch (widget.status.state) {
        RemoteCallState.ringing
            when widget.status.direction == kCallDirectionIncoming =>
          'Incoming call',
        RemoteCallState.reconnecting => 'Reconnecting…',
        _ => 'Calling…',
      };
    }
    final elapsed = DateTime.now().difference(started);
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return elapsed.inHours > 0 ? '${elapsed.inHours}:$m:$sec' : '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HelixCallColors.callBar,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: widget.onTap,
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.status.isVideo ? Icons.videocam : Icons.call,
                  size: 18,
                  color: HelixCallColors.onCallBar,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Tap to return to call · ${widget.status.displayName} · $_label',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: HelixCallColors.onCallBar,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps a tab alive while another is on screen, so a tab's scroll position
/// and loaded data survive swiping away from it.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Subscribes to [RemoteCallService.callStatusChanges] and renders [CallScreen]
/// reactively. Pops itself when the call status becomes null (call ended).
class _CallScreenWrapper extends StatefulWidget {
  const _CallScreenWrapper({required this.root});

  final RemoteCompositionRoot root;

  @override
  State<_CallScreenWrapper> createState() => _CallScreenWrapperState();
}

class _CallScreenWrapperState extends State<_CallScreenWrapper> {
  RemoteCallStatus? _status;
  StreamSubscription<RemoteCallStatus?>? _sub;

  @override
  void initState() {
    super.initState();
    _status = widget.root.callService.activeCall;
    _sub = widget.root.callService.callStatusChanges.listen(_onStatus);
  }

  void _onStatus(RemoteCallStatus? status) {
    if (!mounted || _leaving) return;
    final String logMsg;
    if (status == null) {
      logMsg = 'call ended — popping screen';
    } else if (status.errorMessage != null) {
      logMsg = 'state=${status.state.name} error=${status.errorMessage}';
    } else {
      logMsg = 'state=${status.state.name} dir=${status.direction}';
    }
    AppLogger.instance.info('CALL_SCREEN', logMsg);
    if (status == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _status = status);
  }

  /// Set once this screen hands over to a chat, so the call ending does not
  /// pop the chat that replaced it.
  bool _leaving = false;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  RemoteMessagingService? get _messaging {
    try {
      return widget.root.messagingService;
    } catch (_) {
      return null;
    }
  }

  /// "Message" on a ringing call: decline it and open the chat with the
  /// caller, to write "can't talk now".
  void _declineAndMessage(RemoteCallStatus status) {
    final messaging = _messaging;
    if (messaging == null) return;
    final String conversationId;
    try {
      conversationId = messaging.directChatWith(status.peerAccountId);
    } catch (_) {
      return;
    }
    _leaving = true;
    _sub?.cancel();
    unawaited(widget.root.declineIncomingCall());
    RemoteAttachmentService? attachments;
    RemoteGroupService? groups;
    try {
      attachments = widget.root.attachmentService;
    } catch (_) {}
    try {
      groups = widget.root.groupService;
    } catch (_) {}
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          conversationId: conversationId,
          messagingService: messaging,
          attachmentService: attachments,
          groupService: groups,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var status = _status ?? widget.root.callService.activeCall;
    if (status == null) return const SizedBox.shrink();
    final messaging = _messaging;
    final peerId = status.peerAccountId;
    if (messaging != null && (status.peerDisplayName ?? '').trim().isEmpty) {
      status = status.copyWith(peerDisplayName: messaging.personName(peerId));
    }
    final number = messaging?.peerPhoneNumber(peerId);
    final current = status;
    return CallScreen(
      callStatus: current,
      onMinimize: () => Navigator.of(context).maybePop(),
      peerSubtitle: number != null && number != current.displayName
          ? number
          : null,
      onMessage: messaging == null ? null : () => _declineAndMessage(current),
      onAccept: () => widget.root.acceptIncomingCall(),
      onDecline: () => widget.root.declineIncomingCall(),
      onEnd: () => widget.root.endActiveCall(),
      onMute: ({required bool muted}) =>
          widget.root.callService.setMuted(muted: muted),
      onSpeaker: ({required bool enabled}) =>
          widget.root.callService.setSpeakerOn(enabled: enabled),
      onVideo: ({required bool enabled}) =>
          widget.root.callService.setVideoEnabled(enabled: enabled),
      onSwitchCamera: () => widget.root.callService.switchCamera(),
    );
  }
}
