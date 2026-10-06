import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/calls/application/call_controller.dart';
import 'package:helix_remote/features/calls/application/call_effects.dart';
import 'package:helix_remote/features/calls/application/calls_port.dart';
import 'package:helix_remote/features/calls/calls_routes.dart';

/// Keeps calls working for as long as the app runs, whatever screen is up.
///
/// Three jobs, all driven by the engine's call state (not by a screen):
///
/// - gives the engine its media as soon as there is a runtime, so an offer that
///   rings during start-up can be answered;
/// - runs the phone's side of a call ([callEffectsProvider]: ringing, the
///   foreground service, the lock screen, audio and proximity) and applies
///   Answer/Decline pressed on a notification;
/// - opens the full-screen call over whatever is showing the moment a call
///   appears, ringing or dialing, and rings pending offers again on resume.
///
/// Sits above the app lock's gate, so the call UI needs the lock's own call
/// bypass (`AppLock.callInProgress`, set by the effects) to be reachable.
class CallHost extends ConsumerStatefulWidget {
  const CallHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CallHost> createState() => _CallHostState();
}

class _CallHostState extends ConsumerState<CallHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_ringPending());
  }

  /// An offer that waited for this device (a push woke the phone while the
  /// socket was down) rings now. Offline or signed out is the normal case.
  Future<void> _ringPending() async {
    try {
      final port = await ref.read(callsPortProvider.future);
      await port.fetchPending();
    } on Object {
      // Offline, or no runtime: the engine rings it when the socket connects.
    }
  }

  /// The call the screen was last opened for.
  String? _openedFor;

  @override
  Widget build(BuildContext context) {
    // Only once there is a server to talk to: signed out has no calls.
    final signedInServer = ref.watch(serverUrlProvider) != null;
    if (!signedInServer) return widget.child;
    ref.watch(callEffectsProvider);
    ref.watch(callNotificationHandlerProvider);
    final callId = ref.watch(
      callScreenStateProvider.select((state) => state?.callId),
    );
    if (callId == null) {
      _openedFor = null;
    } else if (callId != _openedFor) {
      _openedFor = callId;
      // Never during a build: a call that is already ringing when this first
      // runs would push a route mid-frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ref.read(callScreenOpenProvider)) return;
        unawaited(ref.read(appRouterProvider).push(CallRoutes.call));
      });
    }
    return widget.child;
  }
}
