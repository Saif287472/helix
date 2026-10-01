/// Another server could not be reached (network, timeout, 5xx). Relays that
/// can wait retry through the outbox; live operations report
/// `federation_unavailable`. Shared by the federation module (which throws
/// it) and the modules whose relays it carries.
final class RelayUnavailable implements Exception {
  const RelayUnavailable([this.reason = 'unreachable']);

  final String reason;

  @override
  String toString() => 'RelayUnavailable($reason)';
}
