// lib/ui/screens/home/home_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/providers/controllers/incoming_call_alert_controller.dart';
import 'package:helix/providers/controllers/proximity_screen_controller.dart';
import 'package:helix/providers/controllers/wakelock_controller.dart';
import 'package:helix/ui/app_theme.dart';
import 'package:helix/ui/app_router.dart';
import 'package:helix/ui/screens/requests/requests_screen.dart';
import 'package:helix/ui/screens/settings/settings_screen.dart';
import 'package:helix/ui/widgets/connectivity_banner.dart';
import 'package:helix/ui/widgets/secret_code_search_sheet.dart';
import 'package:helix/ui/widgets/trusted_devices_sheet.dart';
import 'package:helix/ui/widgets/status_badge.dart';
import 'package:helix/services/app_logger.dart';

part '_home_tab.dart';
part '_peer_widgets.dart';
part '_home_dialogs.dart';
part '_chats_tab.dart';

// ---------------------------------------------------------------------------
// Root home screen with bottom nav (mobile) or nav rail (wide)
// ---------------------------------------------------------------------------

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _sessionInitStarted = false;
  int _selectedIndex = 0;
  ServerSocket? _tcpServer;

  static const _titles = ['Home', 'Requests', 'Chats', 'Settings'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSession());
  }

  @override
  void dispose() {
    ref.read(activeTcpPortProvider.notifier).state = 0;
    _tcpServer?.close();
    super.dispose();
  }

  Future<String> _localEndpoint(int port) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return '${addr.address}:$port';
        }
      }
    } catch (_) {}
    return '127.0.0.1:$port';
  }

  Future<void> _initSession() async {
    if (_sessionInitStarted) return;
    _sessionInitStarted = true;

    final profileSvc = ref.read(profileServiceProvider);
    if (profileSvc.isFirstRun ||
        profileSvc.profile == null ||
        profileSvc.identity == null) {
      return;
    }

    final sessionSvc = ref.read(sessionServiceProvider);
    if (sessionSvc.state.phase == SessionPhase.active) {
      if (mounted) {
        ref
            .read(sessionStateProvider.notifier)
            .startSession(sessionSvc.sessionId);
      }
      return;
    }
    if (sessionSvc.state.phase == SessionPhase.starting) return;

    final discoverySvc = ref.read(discoveryCoordinatorProvider);
    final requestSvc = ref.read(requestServiceProvider);

    try {
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      if (!mounted) {
        try {
          await server.close();
        } catch (_) {}
        return;
      }
      _tcpServer = server;
      ref.read(activeTcpPortProvider.notifier).state = _tcpServer!.port;

      _tcpServer!.listen(
        (socket) => requestSvc.handleIncomingTcpConnection(socket),
        onError: (Object e) => debugPrint('[Helix] TCP server error: $e'),
      );

      await sessionSvc.startSession(profileSvc.profile!, profileSvc.identity!);

      if (!mounted) {
        throw StateError('Widget unmounted during session initialization');
      }
      ref
          .read(sessionStateProvider.notifier)
          .startSession(sessionSvc.sessionId);

      final profile = profileSvc.profile!;
      final identity = profileSvc.identity!;
      final secretCodeVerifier = await profileSvc.getSecretCodeVerifier();

      requestSvc.configureLocalSession(
        sessionId: sessionSvc.sessionId,
        displayName: profile.displayName,
        deviceSuffix: identity.deviceSuffix,
        tcpPort: _tcpServer!.port,
      );

      await discoverySvc.start(
        sessionId: sessionSvc.sessionId,
        displayName: profile.displayName,
        deviceSuffix: identity.deviceSuffix,
        tcpPort: _tcpServer!.port,
        discoverable:
            profile.discoverability == DiscoverabilityState.discoverable,
        secretCodeVerifier: secretCodeVerifier,
      );

      if (!mounted) {
        throw StateError('Widget unmounted during session initialization');
      }
      requestSvc.start();

      // Trust service must be wired in BEFORE reconnect fires so markKnown is called.
      ref.read(trustBridgeProvider);
      await ref.read(trustServiceProvider).init();

      if (!mounted) {
        throw StateError('Widget unmounted during session initialization');
      }
      ref.read(reconnectBridgeProvider);
      ref.read(resumeAutoAcceptBridgeProvider);
      ref.read(fileTransferBridgeProvider);
      ref.read(groupBridgeProvider);
      ref
          .read(groupServiceProvider)
          .configureLocalIdentity(
            fingerprint: identity.staticPublicKeyFingerprint,
            displayName: profile.displayName,
            deviceSuffix: identity.deviceSuffix,
            endpoint: await _localEndpoint(_tcpServer!.port),
          );
      unawaited(ref.read(groupServiceProvider).createPublicLobby());
      ref.read(foregroundServiceBridgeProvider);
      ref.read(notificationActionBridgeProvider);
      ref.read(newMessageNotificationBridgeProvider);
      ref.read(incomingCallAlertControllerProvider);
      ref.read(proximityScreenControllerProvider);
      ref.read(wakelockControllerProvider);
      await ref.read(notificationServiceProvider).init();

      // On Android 14+, USE_FULL_SCREEN_INTENT requires explicit user approval.
      // Prompt once per launch so users know where to enable full-screen call alerts.
      if (Platform.isAndroid && mounted) {
        try {
          final descriptor = ref.read(productDescriptorProvider);
          final foregroundChannel = MethodChannel(
            '${descriptor.methodChannelNamespace}/foreground',
          );
          final granted =
              await foregroundChannel.invokeMethod<bool>(
                'canUseFullScreenIntent',
              ) ??
              true;
          if (!granted && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Grant "Display over other apps" so incoming calls show on your lock screen.',
                ),
                duration: const Duration(seconds: 10),
                action: SnackBarAction(
                  label: 'Allow',
                  onPressed: () {
                    foregroundChannel
                        .invokeMethod<void>('openFullScreenIntentSettings')
                        .ignore();
                  },
                ),
              ),
            );
          }
        } catch (_) {}
      }

      debugPrint('[Helix] Session started, TCP port ${_tcpServer!.port}');
    } catch (e, st) {
      debugPrint('[Helix] Session init failed: $e\n$st');
      AppLogger.instance.error('session', 'Session init failed: $e', st);
      if (_tcpServer != null) {
        try {
          await _tcpServer!.close();
        } catch (_) {}
        _tcpServer = null;
      }
      await discoverySvc.stop().catchError((_) {});
      await sessionSvc.stopSession().catchError((_) {});
      if (mounted) {
        ref.read(activeTcpPortProvider.notifier).state = 0;
        ref.read(sessionStateProvider.notifier).setError(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(oneWayMessageBridgeProvider);

    // Navigate to Requests tab when user taps a connection-request notification.
    ref.listen(notificationTapsProvider, (_, next) {
      next.whenData((payload) {
        if (payload == 'requests' && mounted) {
          setState(() => _selectedIndex = 1);
        }
      });
    });

    // In-app banner: show when a new remote message arrives in a thread that
    // is not currently open.
    ref.listen(threadChangesStreamProvider, (_, next) {
      next.whenData((thread) {
        final last = thread.lastMessage;
        if (last == null ||
            last.origin == MessageOrigin.local ||
            last.isSystem) {
          return;
        }
        if (ref.read(currentChatThreadIdProvider) == thread.threadId) return;
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New message from ${thread.peerDisplayName}'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => Navigator.of(
                context,
              ).pushNamed('${AppRoutes.chat}/${thread.threadId}'),
            ),
          ),
        );
      });
    });

    final unread = ref.watch(totalUnreadProvider);
    final incomingCount = ref.watch(incomingRequestCountProvider);
    final width = MediaQuery.of(context).size.width;
    final isWide = width > HelixTokens.breakpointWide;

    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: 'Home',
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: incomingCount > 0,
          label: Text('$incomingCount'),
          child: const Icon(Icons.notifications_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: incomingCount > 0,
          label: Text('$incomingCount'),
          child: const Icon(Icons.notifications),
        ),
        label: 'Requests',
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: const Icon(Icons.chat_bubble_outline),
        ),
        selectedIcon: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: const Icon(Icons.chat_bubble),
        ),
        label: 'Chats',
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: 'Settings',
      ),
    ];

    final body = IndexedStack(
      index: _selectedIndex,
      children: [
        _HomeTab(onSelectTab: (int i) => setState(() => _selectedIndex = i)),
        const RequestsScreen(),
        const _ChatsTab(),
        const SettingsScreen(),
      ],
    );

    final screen = _buildShell(context, isWide, destinations, body, unread, incomingCount);

    if (!isDesktop) return screen;

    // Ctrl+1–4 keyboard shortcuts for desktop tab navigation (P9-03).
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            setState(() => _selectedIndex = 0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            setState(() => _selectedIndex = 1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            setState(() => _selectedIndex = 2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            setState(() => _selectedIndex = 3),
      },
      child: Focus(autofocus: true, child: screen),
    );
  }

  Widget _buildShell(
    BuildContext context,
    bool isWide,
    List<NavigationDestination> destinations,
    Widget body,
    int unread,
    int incomingCount,
  ) {
    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                NavigationRailDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: const Text('Home'),
                ),
                NavigationRailDestination(
                  icon: Badge(
                    isLabelVisible: incomingCount > 0,
                    label: Text('$incomingCount'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: incomingCount > 0,
                    label: Text('$incomingCount'),
                    child: const Icon(Icons.notifications),
                  ),
                  label: const Text('Requests'),
                ),
                NavigationRailDestination(
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text('$unread'),
                    child: const Icon(Icons.chat_bubble_outline),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text('$unread'),
                    child: const Icon(Icons.chat_bubble),
                  ),
                  label: const Text('Chats'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: Column(
                children: [
                  AppBar(
                    title: Text(_titles[_selectedIndex]),
                    automaticallyImplyLeading: false,
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        automaticallyImplyLeading: false,
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: destinations,
      ),
    );
  }
}
