// Call providers: WebRTC call service and call state.
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:helix_local_domain/domain/call/call_state.dart';
import 'package:helix/providers/infrastructure_providers.dart';
import 'package:helix/providers/messaging_providers.dart'
    show messagingServiceProvider;
import 'package:helix_local_calls/infrastructure/call/call_signaling_gateway_adapter.dart';
import 'package:helix_local_calls/services/call_service.dart';

final callServiceProvider = Provider<CallService>((ref) {
  final messaging = ref.watch(messagingServiceProvider);
  final engine = ref.watch(compositionRootProvider).callEngine;

  final signalingGateway = CallSignalingGatewayAdapter(
    (peerId) => messaging.getChannel(peerId),
  );

  final service = CallService(
    engine: engine,
    signalingGateway: signalingGateway,
  );

  messaging.setCallSignalHandler(service.handleSignal);
  ref.onDispose(service.dispose);
  return service;
});

final currentCallProvider = StreamProvider<CallState?>((ref) {
  return ref.watch(callServiceProvider).callStateStream;
});

/// Whether the in-progress call screen is shrunk to a small floating bar.
final callMinimizedProvider = StateProvider<bool>((ref) => false);

/// Mirrors [WidgetsBindingObserver.didChangeAppLifecycleState] for non-widget
/// controllers (e.g. the incoming-call alert) to check foreground/background.
final appLifecycleStateProvider = StateProvider<AppLifecycleState>(
  (ref) => AppLifecycleState.resumed,
);
