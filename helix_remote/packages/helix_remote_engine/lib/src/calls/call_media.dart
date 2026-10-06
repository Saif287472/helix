import 'dart:async';

import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show IceCandidatePayload;
import 'package:meta/meta.dart';

/// One STUN or TURN server for a call's ICE agent. Built from the server's
/// short-lived TURN credentials; [credential] is a secret and never printed.
@immutable
final class IceServer {
  const IceServer({required this.urls, this.username, this.credential});

  final List<String> urls;
  final String? username;
  final String? credential;

  @override
  String toString() => 'IceServer(${urls.length} urls, redacted)';
}

/// What a media session is created for.
@immutable
final class CallMediaConfig {
  const CallMediaConfig({required this.video, this.iceServers = const []});

  /// The call carries video (the camera starts on) as well as audio.
  final bool video;

  /// Relay servers from `GET /v1/calls/turn`; empty when the server has no
  /// relay (a direct connection may still work).
  final List<IceServer> iceServers;
}

/// How the media connection is doing, as the platform's ICE/DTLS agent
/// reports it.
enum CallMediaState {
  /// Negotiating (candidates are being exchanged).
  connecting,

  /// Media flows both ways: the call is live.
  connected,

  /// Media stopped for now; the agent may recover by itself.
  disconnected,

  /// The connection is gone for good (ICE failed).
  failed,

  /// [CallMediaSession.close] ran.
  closed,
}

/// The engine's view of one call's media (a WebRTC peer connection): pure
/// Dart, so the engine keeps owning only the signalling STATE of a call
/// (ADR-027). The Flutter calls package implements it over `flutter_webrtc`
/// (Phase A3); [FakeCallMediaSession] is the deterministic test double.
///
/// Descriptions are plain SDP strings and the engine never inspects them. A
/// session is one-shot: create, negotiate, [close].
///
/// Contract for implementers:
///
/// - [localCandidates] is a **single-subscription** stream that buffers
///   candidates gathered before it is listened to; the engine subscribes
///   right after creating the session, before [createOffer] or
///   [acceptOffer].
/// - [states] is a broadcast stream of changes (no replay needed).
/// - Every method after [close] may throw [StateError].
abstract interface class CallMediaSession {
  /// Local ICE candidates as they are gathered.
  Stream<IceCandidatePayload> get localCandidates;

  /// Connection state changes.
  Stream<CallMediaState> get states;

  /// Caller side: creates the local offer, sets it as the local description
  /// and starts gathering candidates. Returns the SDP.
  Future<String> createOffer();

  /// Callee side: takes the caller's [offerSdp] as the remote description,
  /// creates and sets the local answer and starts gathering. Returns the
  /// answer SDP.
  Future<String> acceptOffer(String offerSdp);

  /// Caller side: takes the answering device's SDP.
  Future<void> acceptAnswer(String answerSdp);

  /// A candidate from the other side. Only called after the remote
  /// description is set.
  Future<void> addRemoteCandidate(IceCandidatePayload candidate);

  /// Mutes or unmutes the microphone.
  Future<void> setMuted({required bool muted});

  /// Turns the camera on or off (a no-op for an audio-only call).
  Future<void> setVideoEnabled({required bool enabled});

  /// Releases the connection, the camera and the microphone. Idempotent.
  Future<void> close();
}

/// Makes the media session of a call. The host (the app, a test) provides it
/// to `CallsService.mediaFactory`.
abstract interface class CallMediaFactory {
  Future<CallMediaSession> create(CallMediaConfig config);
}
