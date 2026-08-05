/// Why a call could not be set up, in terms a user can act on.
///
/// Before this existed, every setup failure - a server with no TURN relay
/// configured, a relay that would not issue credentials, and a phone with no
/// connectivity - produced the same sentence: "The call could not be started.
/// Check server and call connectivity." That is unactionable for all three,
/// and actively misleading for the first, which is a server-side
/// configuration problem no amount of checking the user's own connectivity
/// will fix.
enum RemoteCallSetupFailure {
  /// The server has no TURN relay configured at all - it answered the
  /// credential request with 503. Nothing the caller can do; an admin has to
  /// configure one. See `deploy/coturn/README.md`.
  turnNotConfigured,

  /// TURN is configured but did not yield usable credentials, so a
  /// relay-only call has no candidate path. Distinct from
  /// [turnNotConfigured] because the fix is different: the relay is there
  /// but broken or mis-keyed, rather than absent.
  turnUnavailable,

  /// The credential request never reached the server.
  network,
}

/// A call-setup failure that carries enough context for the UI to say
/// something specific, instead of the caller having to string-match an
/// [Exception]'s `toString()`.
class RemoteCallSetupException implements Exception {
  const RemoteCallSetupException(this.failure, {this.detail});

  final RemoteCallSetupFailure failure;

  /// Underlying technical detail, for logs. Deliberately not shown to the
  /// user - [userMessage] is what they see.
  final String? detail;

  /// Plain-language explanation, including who can fix it.
  String get userMessage => switch (failure) {
    RemoteCallSetupFailure.turnNotConfigured =>
      'This server has no call relay configured, so calls cannot connect. '
          'Ask the server admin to set up TURN.',
    RemoteCallSetupFailure.turnUnavailable =>
      'The call relay is not issuing credentials right now, so the call '
          'cannot connect. Ask the server admin to check the TURN server.',
    RemoteCallSetupFailure.network =>
      'Could not reach the server to set up the call. Check your connection '
          'and try again.',
  };

  @override
  String toString() =>
      'RemoteCallSetupException(${failure.name})'
      '${detail == null ? '' : ': $detail'}';
}
