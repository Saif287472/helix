import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `calls` module: sealed call signals, ringing state, pending offers,
/// TURN credentials and anonymous quality metrics.
final class CallsClient {
  const CallsClient(this._t);

  final HelixTransport _t;

  /// One-hour TURN REST credentials (10 per hour per device).
  Future<TurnCredentials> turnCredentials() =>
      _t.call(Routes.turnCredentials, TurnCredentials.fromJson);

  Future<CallSignalResponse> sendSignal(
    String callId,
    CallSignalRequest request,
  ) => _t.call(
    Routes.sendCallSignal,
    CallSignalResponse.fromJson,
    params: {'call_id': callId},
    json: request.toJson(),
  );

  /// Stops this account's other devices ringing and drops pending offers.
  Future<void> setState(String callId, CallState state) => _t.empty(
    Routes.setCallState,
    params: {'call_id': callId},
    json: CallStateRequest(state: state).toJson(),
  );

  /// Offers that arrived while this device was offline.
  Future<PendingCallList> pending() =>
      _t.call(Routes.pendingCalls, PendingCallList.fromJson);

  Future<void> sendMetrics(CallMetricsRequest request) =>
      _t.empty(Routes.callMetrics, json: request.toJson());
}
