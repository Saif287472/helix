import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show EngineException, NotSignedInException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

/// Why an operation failed, in the few ways a person can act on.
enum FailureKind {
  /// No network, or the server is not answering.
  offline,

  /// Wrong password or code.
  rejected,

  /// Too many wrong tries: wait.
  locked,

  /// Asked too often: wait.
  rateLimited,

  /// The server is in maintenance or failing; try later.
  unavailable,

  /// The server said no (suspended, blocked, forbidden).
  notAllowed,

  /// The session ended; sign in again.
  signedOut,

  /// Anything else.
  unknown,
}

/// A failure with the sentence to show and what kind it is.
///
/// Nothing in [message] names a host, a key, a code or an exception type: it
/// is the only text a settings screen ever shows for a failure.
final class Failure {
  const Failure(this.kind, this.message);

  final FailureKind kind;
  final String message;

  @override
  String toString() => 'Failure(${kind.name})';
}

/// Turns anything the engine and API can throw into a [Failure].
///
/// [now] is only used to say how long a lockout lasts.
Failure describeFailure(Object error, {DateTime? now}) {
  switch (error) {
    case NetworkException():
      return const Failure(
        FailureKind.offline,
        'You are offline, or Helix cannot be reached. Check your connection '
        'and try again.',
      );
    case SignedOutException():
      return const Failure(
        FailureKind.signedOut,
        'You were signed out. Sign in again to continue.',
      );
    case NotSignedInException():
      return const Failure(
        FailureKind.signedOut,
        'You were signed out. Sign in again to continue.',
      );
    case ApiException(:final code, :final lockedUntil, :final retryAfter):
      return switch (code) {
        ErrorCode.invalidCredentials || ErrorCode.invalidCode => const Failure(
          FailureKind.rejected,
          'That did not match. Check it and try again.',
        ),
        ErrorCode.passwordLocked => Failure(
          FailureKind.locked,
          _lockedMessage(lockedUntil ?? _after(now, retryAfter), now),
        ),
        ErrorCode.rateLimited => Failure(
          FailureKind.rateLimited,
          _waitMessage(retryAfter),
        ),
        ErrorCode.maintenance || ErrorCode.unavailable => const Failure(
          FailureKind.unavailable,
          'The server is not available right now. Try again in a little '
          'while.',
        ),
        ErrorCode.accountSuspended || ErrorCode.accountBanned => const Failure(
          FailureKind.notAllowed,
          'This account cannot do that right now.',
        ),
        ErrorCode.deviceRevoked => const Failure(
          FailureKind.signedOut,
          'This device was removed from the account. Sign in again to '
          'continue.',
        ),
        _ when code.isRetryable => const Failure(
          FailureKind.unavailable,
          'Something went wrong on the server. Try again in a little while.',
        ),
        _ => const Failure(
          FailureKind.unknown,
          'That did not work. Try again.',
        ),
      };
    case EngineException():
      return const Failure(
        FailureKind.unknown,
        'That did not work. Try again.',
      );
    default:
      return const Failure(
        FailureKind.unknown,
        'That did not work. Try again.',
      );
  }
}

DateTime? _after(DateTime? now, Duration? delay) =>
    now == null || delay == null ? null : now.add(delay);

String _lockedMessage(DateTime? until, DateTime? now) {
  if (until == null || now == null) {
    return 'Too many wrong attempts. Wait a while before trying again.';
  }
  final minutes = until.difference(now).inMinutes + 1;
  if (minutes <= 1) {
    return 'Too many wrong attempts. Try again in a minute.';
  }
  return 'Too many wrong attempts. Try again in $minutes minutes.';
}

String _waitMessage(Duration? retryAfter) {
  if (retryAfter == null) {
    return 'You are doing that too often. Wait a moment and try again.';
  }
  final seconds = retryAfter.inSeconds;
  if (seconds < 90) {
    return 'You are doing that too often. Try again in a minute.';
  }
  return 'You are doing that too often. Try again in '
      '${(seconds / 60).ceil()} minutes.';
}
