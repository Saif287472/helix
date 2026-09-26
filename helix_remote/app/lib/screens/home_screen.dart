import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/screens/call_screen.dart';
import 'package:helix_remote/screens/calls_tab_screen.dart';
import 'package:helix_remote/screens/contacts_screen.dart';
import 'package:helix_remote/screens/conversation_list_screen.dart';
import 'package:helix_remote/screens/settings_screen.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.root, this.onChangeServerUrl});

  final RemoteCompositionRoot root;
  final Future<void> Function()? onChangeServerUrl;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _pendingContactRequests = 0;
  StreamSubscription<RemoteSyncChange>? _changeSub;
  StreamSubscription<RemoteCallStatus?>? _callSub;
  bool _callScreenShowing = false;

  @override
  void initState() {
    super.initState();
    _changeSub = widget.root.messagingService.changes.listen(_onRemoteChange);
    _callSub = widget.root.callService.callStatusChanges.listen(_onCallStatus);
    _refreshBadge();
  }

  void _onRemoteChange(RemoteSyncChange change) {
    if (change.affects(RemoteSyncChangeArea.contacts)) {
      _refreshBadge();
    }
  }

  void _onCallStatus(RemoteCallStatus? status) {
    if (!mounted) return;
    final shouldShowCallScreen =
        status != null &&
        !(status.state == RemoteCallState.ringing &&
            status.direction == kCallDirectionIncoming);
    if (shouldShowCallScreen && !_callScreenShowing) {
      _callScreenShowing = true;
      AppLogger.instance.info(
        'CALL_NAV',
        'pushing call screen state=${status.state.name} '
            'direction=${status.direction} peer=${status.peerAccountId}',
      );
      Navigator.of(context)
          .push<void>(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/call'),
              fullscreenDialog: true,
              builder: (_) => _CallScreenWrapper(root: widget.root),
            ),
          )
          .then((_) => _callScreenShowing = false);
    }
  }

  void _refreshBadge() {
    try {
      final count = widget.root.messagingService
          .contactRequests()
          .where((r) => r.direction == 'received' && r.status == 'Pending')
          .length;
      if (mounted) setState(() => _pendingContactRequests = count);
    } catch (e) {
      AppLogger.instance.warn(
        'home',
        'contact request badge refresh failed: \$e',
      );
    }
  }

  @override
  void dispose() {
    _changeSub?.cancel();
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPending = _pendingContactRequests > 0;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          ConversationListScreen(
            messagingService: widget.root.messagingService,
            root: widget.root,
          ),
          CallsTabScreen(
            root: widget.root,
            messagingService: widget.root.messagingService,
          ),
          ContactsScreen(
            messagingService: widget.root.messagingService,
            root: widget.root,
          ),
          SettingsScreen(
            root: widget.root,
            messagingService: widget.root.messagingService,
            onChangeServerUrl: widget.onChangeServerUrl,
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
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          const NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Calls',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: hasPending,
              label: Text('$_pendingContactRequests'),
              child: const Icon(Icons.people_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: hasPending,
              label: Text('$_pendingContactRequests'),
              child: const Icon(Icons.people),
            ),
            label: 'Contacts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
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
    if (!mounted) return;
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

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status ?? widget.root.callService.activeCall;
    if (status == null) return const SizedBox.shrink();
    return CallScreen(
      callStatus: status,
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
