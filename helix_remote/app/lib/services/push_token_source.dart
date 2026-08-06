import 'dart:async';

/// Where a device push token comes from.
///
/// Kept behind an interface so [PushRegistrationService] can be tested
/// without Firebase, and so a future APNs or self-hosted transport slots in
/// without touching the registration logic.
abstract class PushTokenSource {
  /// Wire name the server expects for tokens from this source: `FCM` or
  /// `APNS` (see `calls/push_tokens.dart`, which rejects anything else).
  String get tokenType;

  /// Brings the underlying SDK up and asks the user for notification
  /// permission if it has not been granted.
  ///
  /// Returns false when push is simply unavailable — no Firebase
  /// configuration in the build, an unsupported platform, or the user
  /// declining permission. That is a normal state, not an error: the app
  /// works without push, it just cannot wake for a call while closed.
  Future<bool> initialize();

  /// The current token, or null when there is none to register.
  Future<String?> currentToken();

  /// Fires whenever the SDK rotates the token. A rotated token that is not
  /// re-registered is the classic way push silently dies weeks later: the
  /// server keeps sending to an address the device no longer answers on.
  Stream<String> get tokenRefreshes;

  Future<void> dispose();
}

/// A source for builds with no push transport configured.
///
/// [initialize] answers false and everything else is inert, so the
/// registration service short-circuits and the app behaves exactly as it did
/// before push existed. This is what runs when `google-services.json` is
/// absent, which is the state of any developer checkout that has not been
/// given one.
class UnavailablePushTokenSource implements PushTokenSource {
  const UnavailablePushTokenSource();

  @override
  String get tokenType => 'FCM';

  @override
  Future<bool> initialize() async => false;

  @override
  Future<String?> currentToken() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream<String>.empty();

  @override
  Future<void> dispose() async {}
}
