import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The network side of calls, as the [CallsService] state machine sees it:
/// sealed signals out, pending offers and TURN credentials in. The engine's
/// implementation (`EngineCallSignaling`) seals every signal per recipient
/// device through the pairwise session manager and talks to the `calls` API;
/// tests plug in an in-memory network.
///
/// Nothing here may log or keep a signal's content: SDP and ICE are as
/// private as a message.
abstract interface class CallSignaling {
  /// Short-lived TURN credentials, or null when the server has no relay
  /// (`unavailable`) or refuses (rate limit): the call then tries a direct
  /// connection.
  Future<TurnCredentials?> turnCredentials();

  /// Seals [payload] for the devices of [account] and posts it
  /// (`POST /v1/calls/{id}/signals`, routed as `payload.type.routedAs`).
  ///
  /// With [devices] null it goes to every active device of the account (an
  /// offer must: the server rejects an incomplete list with
  /// `device_list_stale`, which the implementation repairs); otherwise only
  /// to those devices. [ttl] is how long an offer stays pending for offline
  /// devices. Throws what the API throws.
  Future<CallSignalResponse> send(
    String callId,
    CallSignalPayload payload, {
    required String account,
    Set<String>? devices,
    Duration ttl = const Duration(seconds: 60),
  });

  /// Tells the server this account answered or declined, so its other
  /// devices stop ringing (`PUT /v1/calls/{id}/state`).
  Future<void> setState(String callId, CallState state);

  /// Offers that arrived while this device was offline, sealed
  /// (`GET /v1/calls/pending`).
  Future<List<PendingCall>> pending();

  /// Opens a pending offer's sealed payload, or null when it cannot be read
  /// (no session, a replay, a hostile sender). Moves the pairwise ratchet,
  /// so a payload can be opened once.
  Future<CallSignalPayload?> open(PendingCall call);
}

/// Where the network side delivers what arrives: implemented by the state
/// machine.
abstract interface class CallSignalSink {
  /// A signal from [device] of [account] (authenticated by the pairwise
  /// session it was opened under).
  Future<void> onSignal(
    String account,
    String device,
    CallSignalPayload payload,
  );

  /// Another device of this account answered or declined [callId]
  /// (`call_signal` with no payload, `data: {kind: end, state}`).
  void onEndedElsewhere(String callId, CallState state);
}
