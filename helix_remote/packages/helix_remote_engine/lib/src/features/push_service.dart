import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Push-token registration. The server sends data-only wake-ups (no
/// content, METADATA_V2.md); the host's FCM handler starts a headless engine
/// run (`Engine.syncOnce`) that fetches and decrypts, then shows the
/// notification.
final class PushService {
  PushService(this._ctx);

  final EngineContext _ctx;

  /// Tells the server where to wake this device. Call again whenever the
  /// platform rotates the token.
  Future<void> register(
    String token, {
    PushTokenKind kind = PushTokenKind.fcm,
  }) => _ctx.api.identity.setPushToken(
    PushTokenRequest(token: token, kind: kind),
  );

  /// Stops wake-ups (the user turned notifications off).
  Future<void> unregister() => _ctx.api.identity.clearPushToken();
}
