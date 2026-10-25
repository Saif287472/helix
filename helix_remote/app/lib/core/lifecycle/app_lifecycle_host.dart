import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/diagnostics/anomaly_log.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/notifications/message_alerts.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// Keeps the engine in step with the app's foreground.
///
/// Coming back to the app is not the same as the socket still being good: the
/// OS may have dropped it, and the device may have slept for hours. So on
/// resume the socket is reconnected and, when it is not running, the mailbox is
/// read once over REST. That is what makes a message that arrived while the
/// app was closed appear without waiting for a push. The message notification
/// goes on resume too: the chats are on screen.
class AppLifecycleHost extends ConsumerStatefulWidget {
  const AppLifecycleHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleHost> createState() => _AppLifecycleHostState();
}

class _AppLifecycleHostState extends ConsumerState<AppLifecycleHost>
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
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(ref.read(runningAppAlertsProvider).resumed());
        unawaitedResume();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Android says when memory is short. Nothing here can free much (the
  /// database, the engine and the images are what a phone holds), but a run
  /// of these is the likeliest reason for the app being killed, so it is
  /// recorded once a minute at most.
  @override
  void didHaveMemoryPressure() => AnomalyLog.state('app', 'memory pressure');

  /// Reconnects the socket and catches up over REST.
  ///
  /// Both are best effort: an offline device resuming is the normal case, and
  /// the engine's own backoff and reconnect do the rest.
  Future<void> unawaitedResume() async {
    // Nobody signed in (the sign-in page) is the normal state, not a crash:
    // there is nothing to reconnect (AUD-14b-4). Asked first, because the
    // runtime provider retries a failure with a backoff, so awaiting it with
    // no account would hold this call open for a minute before it threw.
    if (ref.read(activeAccountProvider) == null) return;
    final HelixRuntime runtime;
    try {
      runtime = await ref.read(runtimeProvider.future);
    } on NoServerChosen {
      return;
    }
    if (runtime.engine.status != EngineStatus.running) return;
    runtime.engine.reconnect();
    try {
      await runtime.engine.syncOnce();
    } on Object {
      // Offline, or the session ended; the engine reports that itself.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
