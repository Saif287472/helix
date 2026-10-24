import 'package:helix_remote_server/src/platform/push/push.dart';

/// Records the wake-ups a run sends, and answers "unregistered" for the tokens
/// in [gone]. Test-only by construction: the platform library ships
/// `NoPushProvider` and the real FCM provider, and nothing here.
final class RecordingPushProvider implements PushProvider {
  final List<({String token, PushReason reason, String? callId})> sent = [];

  /// Tokens that answer "unregistered".
  final Set<String> gone = {};

  @override
  bool get isConfigured => true;

  @override
  Future<void> send({
    required String token,
    required String kind,
    required PushReason reason,
    String? callId,
  }) async {
    if (gone.contains(token)) throw const PushTokenGone();
    sent.add((token: token, reason: reason, callId: callId));
  }
}
