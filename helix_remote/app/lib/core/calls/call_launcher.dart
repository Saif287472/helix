import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Starts a call to a person. **The seam the calls feature (A3a) fills.**
///
/// The conversation header has a voice and a video button; what they do is the
/// calls feature's business (the engine's call state machine, the media
/// session, the full-screen call). Until that lands, the default launcher says
/// calls are unavailable and the header shows exactly that.
abstract interface class CallLauncher {
  /// Whether a call can be started from a chat at all.
  bool get isAvailable;

  /// Calls [peerAccount]; [video] chooses a video call.
  Future<void> start({required String peerAccount, required bool video});
}

/// The launcher before the calls feature is wired in.
final class UnavailableCallLauncher implements CallLauncher {
  const UnavailableCallLauncher();

  @override
  bool get isAvailable => false;

  @override
  Future<void> start({
    required String peerAccount,
    required bool video,
  }) async {}
}

/// A3a replaces this provider's body with the real launcher.
final callLauncherProvider = Provider<CallLauncher>(
  (ref) => const UnavailableCallLauncher(),
);
