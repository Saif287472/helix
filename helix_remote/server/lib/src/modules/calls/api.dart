import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Outbound federation for call signals to `uuid@domain` accounts
/// (installed by the federation module). Signals are live, so a relay is
/// synchronous: an unreachable server is `federation_unavailable`.
abstract interface class CallRelay {
  /// This server's domain: addresses qualified with it are local.
  String get localDomain;

  Future<CallSignalResponse> relayCall(
    String domain,
    String callId,
    S2SCallSignal signal,
  );
}

/// The calls module's facade (ADR-026).
abstract interface class CallsApi {
  void setRelay(CallRelay relay);

  /// A signal relayed by [domain]'s server (already authenticated) for this
  /// server's devices.
  Future<CallSignalResponse> receive(
    String domain,
    String callId,
    S2SCallSignal signal,
  );
}
