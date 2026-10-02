/// Failures the engine reports to its callers. Messages never contain
/// message content, keys, tokens, codes or full phone numbers.
sealed class EngineException implements Exception {
  const EngineException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The operation needs a signed-in device.
final class NotSignedInException extends EngineException {
  const NotSignedInException([super.message = 'this device is not signed in']);
}

/// The operation is not allowed in the engine's current state (for example
/// registering while an account already exists on this database).
final class EngineStateException extends EngineException {
  const EngineStateException(super.message);
}

/// A sign-in or linking step failed for a reason the user can act on.
final class SignInException extends EngineException {
  const SignInException(this.reason, [String? message])
    : super(message ?? 'sign-in failed');

  final SignInFailure reason;
}

enum SignInFailure {
  /// The link code is malformed or names another server.
  badLinkCode,

  /// The other device did not approve in time, or the link expired.
  linkExpired,

  /// The password did not unwrap the account key.
  wrongPassword,

  /// The server answered with keys that do not belong to the account.
  untrustedAccountKey,
}

/// Something went wrong that retrying later may fix (no network, a server
/// that is down). The inbound pipeline stops and retries instead of
/// quarantining the envelope, because the cumulative ack cannot skip it.
final class TransientEngineException extends EngineException {
  const TransientEngineException(super.message, {this.cause});

  final Object? cause;
}

/// The recipient's keys could not be trusted: a certificate that does not
/// verify, or keys that claim another account.
final class UntrustedPeerException extends EngineException {
  const UntrustedPeerException(super.message);
}
