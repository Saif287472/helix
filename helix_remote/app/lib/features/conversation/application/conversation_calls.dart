import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/calls/call_launcher.dart';

/// The call buttons of a conversation header, over the calls seam in `core/`
/// (`CallLauncher`, which resolves to the calls feature's `placeCallProvider`).
final class ConversationCalls {
  ConversationCalls(this._launcher);

  final CallLauncher _launcher;

  /// Whether a call can be started from here at all.
  bool get isAvailable => _launcher.isAvailable;

  /// Null when the call started, else one sentence to show.
  Future<String?> start(String peerAccount, {required bool video}) =>
      _launcher.start(peerAccount: peerAccount, video: video);
}

final conversationCallsProvider = Provider<ConversationCalls>(
  (ref) => ConversationCalls(ref.watch(callLauncherProvider)),
);
