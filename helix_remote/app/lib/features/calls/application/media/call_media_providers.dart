import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/media/webrtc_call_media.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show CallMediaFactory;

/// The live call's media, shared by the engine's media session and the call
/// screen (see [CallMediaHub]).
final callMediaHubProvider = Provider<CallMediaHub>((ref) {
  final hub = CallMediaHub();
  ref.onDispose(hub.dispose);
  return hub;
});

/// What the engine makes call media with. Tests override this with the
/// engine's `FakeCallMediaFactory`.
final callMediaFactoryProvider = Provider<CallMediaFactory>(
  (ref) => WebRtcCallMediaFactory(hub: ref.watch(callMediaHubProvider)),
);

/// The video surfaces, camera facing and connection quality of the live call;
/// null when no media is up.
final callMediaInfoProvider = StreamProvider<CallMediaInfo?>(
  (ref) => ref.watch(callMediaHubProvider).watch(),
);
