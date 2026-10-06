import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show IceCandidatePayload;

/// The engine's [CallMediaFactory] over `helix_remote_calls` (the Flutter
/// WebRTC wrapper), for Android and Windows.
///
/// The engine owns the call's signalling state and hands each call one
/// [CallMediaSession]; this is where that session becomes a peer connection.
/// Each session wraps its own [RemoteWebRtcCallEngine], which already knows how
/// to open the microphone and camera, gather candidates (waiting a moment so
/// the SDP carries them, which a callee woken by a push needs), sample the
/// connection's quality and release everything on `endCall`.
///
/// **Privacy.** Candidates are relay-only (`IpPrivacyMode.relayOnly`): neither
/// side learns the other's address, whatever the other side's candidates say.
/// With no relay from the server there is no call - a clear "no call relay"
/// answer, never a silent fall back to a direct connection.
final class WebRtcCallMediaFactory implements CallMediaFactory {
  WebRtcCallMediaFactory({
    required this.hub,
    String Function()? newId,
    Duration qualityInterval = const Duration(seconds: 5),
  }) : _newId = newId ?? _timeId,
       _qualityInterval = qualityInterval;

  final CallMediaHub hub;
  final String Function() _newId;
  final Duration _qualityInterval;

  static String _timeId() => 'media-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Future<CallMediaSession> create(CallMediaConfig config) async {
    hub.lastProblem = null;
    final servers = <IceServerConfig>[
      for (final server in config.iceServers)
        for (final url in server.urls)
          IceServerConfig(
            url: url,
            username: server.username,
            credential: server.credential,
          ),
    ];
    final ice = RemoteIceConfig(
      iceServers: servers,
      ipPrivacy: IpPrivacyMode.relayOnly,
    );
    if (!ice.hasTurnServer) {
      hub.lastProblem = CallMediaProblem.noRelay;
      throw StateError('no relay');
    }
    return WebRtcCallMediaSession(
      engine: RemoteWebRtcCallEngine(
        iceConfig: ice,
        qualitySampleInterval: _qualityInterval,
      ),
      callId: _newId(),
      video: config.video,
      hub: hub,
    );
  }
}

/// One call's peer connection.
final class WebRtcCallMediaSession implements CallMediaSession {
  WebRtcCallMediaSession({
    required RemoteCallEngine engine,
    required this.callId,
    required this.video,
    required this.hub,
  }) : _engine = engine {
    _events = _engine.events.listen(_onEvent);
    hub
      ..publish(const CallMediaInfo())
      ..bindCameraSwitch(() => _engine.switchCamera(callId));
  }

  final RemoteCallEngine _engine;
  final String callId;
  final bool video;
  final CallMediaHub hub;

  late final StreamSubscription<RemoteCallEngineEvent> _events;

  // Buffers until the engine subscribes (it does, right after create).
  final StreamController<IceCandidatePayload> _candidates =
      StreamController<IceCandidatePayload>();
  final StreamController<CallMediaState> _states =
      StreamController<CallMediaState>.broadcast();
  bool _closed = false;

  @override
  Stream<IceCandidatePayload> get localCandidates => _candidates.stream;

  @override
  Stream<CallMediaState> get states => _states.stream;

  void _onEvent(RemoteCallEngineEvent event) {
    if (_closed || event.callId != callId) return;
    switch (event) {
      case RemoteIceCandidateEvent():
        // An empty candidate marks the end of gathering; the engine's wire
        // format has no use for it.
        if (event.candidate.isEmpty) return;
        _candidates.add(
          IceCandidatePayload(
            candidate: event.candidate,
            sdpMid: event.sdpMid.isEmpty ? null : event.sdpMid,
            sdpMLineIndex: event.mlineIndex,
          ),
        );
      case RemoteCallConnectionStateEvent():
        final state = switch (event.state) {
          RemoteCallEngineConnectionState.checking => CallMediaState.connecting,
          RemoteCallEngineConnectionState.connected ||
          RemoteCallEngineConnectionState.completed => CallMediaState.connected,
          RemoteCallEngineConnectionState.disconnected =>
            CallMediaState.disconnected,
          RemoteCallEngineConnectionState.failed => CallMediaState.failed,
          RemoteCallEngineConnectionState.closed => CallMediaState.closed,
        };
        hub.update((info) => info.copyWith(state: state));
        _states.add(state);
      case RemoteCallMediaEvent():
        final local = event.localRenderer;
        final remote = event.remoteRenderer;
        hub.update(
          (info) => info.copyWith(
            local: local == null
                ? null
                : _RendererSurface(RemoteVideoSource(local)),
            remote: remote == null
                ? null
                : _RendererSurface(RemoteVideoSource(remote)),
          ),
        );
      case RemoteCallQualityEvent():
        hub.update((info) => info.copyWith(weak: event.metrics.isWeak));
      case RemoteCameraFacingEvent():
        hub.update((info) => info.copyWith(frontCamera: event.isFrontCamera));
      case RemoteCallEngineDiagnosticEvent() ||
          RemoteVideoStateEvent() ||
          RemoteRenegotiationOfferEvent():
        break;
    }
  }

  @override
  Future<String> createOffer() => _engine.createOffer(callId, video: video);

  @override
  Future<String> acceptOffer(String offerSdp) =>
      _engine.createAnswer(callId, offerSdp, video: video);

  @override
  Future<void> acceptAnswer(String answerSdp) =>
      _engine.setRemoteAnswer(callId, answerSdp);

  @override
  Future<void> addRemoteCandidate(IceCandidatePayload candidate) =>
      _engine.addIceCandidate(
        callId,
        candidate.candidate,
        candidate.sdpMLineIndex ?? 0,
        candidate.sdpMid ?? '',
      );

  @override
  Future<void> setMuted({required bool muted}) =>
      _engine.setMuted(callId, muted: muted);

  @override
  Future<void> setVideoEnabled({required bool enabled}) async {
    if (!video) return;
    await _engine.setVideoEnabled(callId, enabled: enabled);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    hub
      ..bindCameraSwitch(null)
      ..publish(null);
    await _events.cancel();
    try {
      await _engine.endCall(callId);
      await _engine.dispose();
    } on Object {
      // Releasing the devices is best effort: the call is already over.
    }
    unawaited(_states.close());
    unawaited(_candidates.close());
  }
}

/// A video track as a [CallVideoSurface].
final class _RendererSurface implements CallVideoSurface {
  const _RendererSurface(this._source);

  final RemoteVideoSource _source;

  @override
  Listenable get changes => _source.changes;

  @override
  bool get hasFrames => _source.hasFrames;

  @override
  Widget build({bool mirror = false}) => _source.build(mirror: mirror);
}
