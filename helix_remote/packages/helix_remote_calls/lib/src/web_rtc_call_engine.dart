import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:helix_remote_calls/helix_remote_calls.dart';

class RemoteWebRtcCallEngine implements RemoteCallEngine {
  RemoteWebRtcCallEngine({
    RemoteIceConfig? iceConfig,
    Future<RemoteIceConfig> Function()? iceConfigProvider,
    Duration qualitySampleInterval = const Duration(seconds: 5),
  }) : _iceConfig =
           iceConfig ??
           const RemoteIceConfig(
             iceServers: [],
             ipPrivacy: IpPrivacyMode.relayOnly,
           ),
       _runtimeIceConfigProvider = iceConfigProvider,
       _qualityPollingInterval = qualitySampleInterval;

  static const int _maxCandidateLength = 4096;

  final RemoteIceConfig _iceConfig;
  final Future<RemoteIceConfig> Function()? _runtimeIceConfigProvider;
  final Duration _qualityPollingInterval;
  final Map<String, _PeerConnectionState> _calls = {};
  final Map<String, List<_RemoteIceCandidate>> _pendingCandidates = {};
  final Set<String> _endedCalls = <String>{};
  final StreamController<RemoteCallEngineEvent> _eventController =
      StreamController<RemoteCallEngineEvent>.broadcast();

  @override
  Stream<RemoteCallEngineEvent> get events => _eventController.stream;

  Future<webrtc.MediaStream> _createLocalStream({bool video = false}) {
    return webrtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video
          ? {
              'width': {'ideal': 1280, 'max': 1280},
              'height': {'ideal': 720, 'max': 720},
              'frameRate': {'ideal': 24, 'max': 30},
            }
          : false,
    });
  }

  Future<webrtc.RTCPeerConnection> _createPeerConnection(String callId) async {
    if (_calls.isNotEmpty && !_calls.containsKey(callId)) {
      throw StateError('Only one remote call can own media at a time.');
    }
    final latestConfig =
        await (_runtimeIceConfigProvider?.call() ?? Future.value(_iceConfig));
    _diag(
      callId,
      'ice_config privacy=${latestConfig.ipPrivacy.name} '
      'has_turn=${latestConfig.hasTurnServer} '
      'servers=${latestConfig.iceServers.length} '
      'schemes=${_iceServerSchemes(latestConfig)}',
    );
    if (latestConfig.ipPrivacy == IpPrivacyMode.relayOnly &&
        !latestConfig.hasTurnServer) {
      _diag(callId, 'ice_config rejected reason=relay_only_without_turn');
      throw StateError('Relay-only calls require TURN credentials.');
    }
    final pc = await webrtc.createPeerConnection(
      latestConfig.toWebRtcConfiguration(),
    );
    _diag(callId, 'peer_connection created');
    pc.onIceCandidate = (candidate) {
      if (_endedCalls.contains(callId)) return;
      _diag(
        callId,
        'candidate gathered type=${_candidateType(candidate.candidate ?? '')} '
        'mid=${candidate.sdpMid?.isEmpty ?? true ? "none" : candidate.sdpMid} '
        'mline=${candidate.sdpMLineIndex ?? 0}',
      );
      _eventController.add(
        RemoteIceCandidateEvent(
          callId: callId,
          candidate: candidate.candidate ?? '',
          mlineIndex: candidate.sdpMLineIndex ?? 0,
          sdpMid: candidate.sdpMid ?? '',
        ),
      );
    };
    pc.onIceConnectionState = (state) {
      _diag(callId, 'ice_connection_state ${_shortEnum(state)}');
      _eventController.add(
        RemoteCallConnectionStateEvent(
          callId: callId,
          state: _mapIceState(state),
        ),
      );
    };
    pc.onConnectionState = (state) {
      _diag(callId, 'peer_connection_state ${_shortEnum(state)}');
    };
    pc.onIceGatheringState = (state) {
      _diag(callId, 'ice_gathering_state ${_shortEnum(state)}');
    };
    pc.onSignalingState = (state) {
      _diag(callId, 'signaling_state ${_shortEnum(state)}');
    };
    pc.onTrack = (event) {
      final state = _calls[callId];
      if (state == null || event.streams.isEmpty) return;
      state.remoteStream ??= event.streams.first;
      state.remoteRenderer.srcObject = state.remoteStream;
      _diag(
        callId,
        'remote_track streams=${event.streams.length} '
        'track_id=${event.track.id == null || event.track.id!.isEmpty ? "none" : "present"}',
      );
      _emitMedia(callId, state);
    };
    return pc;
  }

  Future<_PeerConnectionState> _createState(
    String callId, {
    required bool video,
  }) async {
    _diag(callId, 'state_create begin video=$video');
    final pc = await _createPeerConnection(callId);
    _diag(callId, 'local_media request video=$video');
    final localStream = await _createLocalStream(video: video);
    _diag(
      callId,
      'local_media ready audio=${localStream.getAudioTracks().length} '
      'video=${localStream.getVideoTracks().length}',
    );
    final localRenderer = webrtc.RTCVideoRenderer();
    final remoteRenderer = webrtc.RTCVideoRenderer();
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _diag(callId, 'renderers initialized');
    localRenderer.srcObject = localStream;
    for (final track in localStream.getTracks()) {
      pc.addTrack(track, localStream);
    }
    _diag(callId, 'local_tracks added count=${localStream.getTracks().length}');
    final state = _PeerConnectionState(
      pc: pc,
      localStream: localStream,
      localRenderer: localRenderer,
      remoteRenderer: remoteRenderer,
    );
    _calls[callId] = state;
    _endedCalls.remove(callId);
    _emitMedia(callId, state);
    state.qualityTimer = Timer.periodic(
      _qualityPollingInterval,
      (_) => _sampleQuality(callId, state),
    );
    return state;
  }

  @override
  Future<String> createOffer(String callId, {bool video = false}) async {
    _diag(callId, 'create_offer begin video=$video');
    final state = _calls[callId] ?? await _createState(callId, video: video);
    final offer = await state.pc.createOffer();
    _diag(callId, 'create_offer done sdp_len=${offer.sdp?.length ?? 0}');
    await state.pc.setLocalDescription(offer);
    _diag(callId, 'set_local_offer done');
    return offer.sdp ?? '';
  }

  @override
  Future<String> createAnswer(
    String callId,
    String offerSdp, {
    bool video = false,
  }) async {
    _diag(
      callId,
      'create_answer begin video=$video offer_sdp_len=${offerSdp.length}',
    );
    final state = _calls[callId] ?? await _createState(callId, video: video);
    await state.pc.setRemoteDescription(
      webrtc.RTCSessionDescription(offerSdp, 'offer'),
    );
    _diag(callId, 'set_remote_offer done');
    state.remoteDescriptionSet = true;
    await _flushPendingCandidates(callId, state);
    final answer = await state.pc.createAnswer();
    _diag(callId, 'create_answer done sdp_len=${answer.sdp?.length ?? 0}');
    await state.pc.setLocalDescription(answer);
    _diag(callId, 'set_local_answer done');
    return answer.sdp ?? '';
  }

  @override
  Future<void> setRemoteAnswer(String callId, String answerSdp) async {
    final state = _calls[callId];
    if (state == null || _endedCalls.contains(callId)) {
      _diag(
        callId,
        'set_remote_answer ignored state=${state == null ? "missing" : "ended"}',
      );
      return;
    }
    _diag(callId, 'set_remote_answer begin sdp_len=${answerSdp.length}');
    await state.pc.setRemoteDescription(
      webrtc.RTCSessionDescription(answerSdp, 'answer'),
    );
    _diag(callId, 'set_remote_answer done');
    state.remoteDescriptionSet = true;
    await _flushPendingCandidates(callId, state);
  }

  @override
  Future<void> addIceCandidate(
    String callId,
    String candidate,
    int mlineIndex,
    String sdpMid,
  ) async {
    if (_endedCalls.contains(callId)) {
      _diag(callId, 'remote_candidate ignored reason=ended');
      return;
    }
    if (!_isValidCandidate(candidate)) {
      _diag(callId, 'remote_candidate ignored reason=invalid');
      return;
    }
    final pending = _RemoteIceCandidate(candidate, mlineIndex, sdpMid);
    final state = _calls[callId];
    if (state == null || !state.remoteDescriptionSet) {
      final queue = _pendingCandidates.putIfAbsent(callId, () => []);
      if (!queue.any((item) => item.key == pending.key)) {
        queue.add(pending);
        _diag(
          callId,
          'remote_candidate queued type=${_candidateType(candidate)} '
          'pending=${queue.length}',
        );
      }
      return;
    }
    _diag(callId, 'remote_candidate add type=${_candidateType(candidate)}');
    await _addCandidate(state, pending);
  }

  @override
  Future<void> restartIce(String callId) async {
    final state = _calls[callId];
    if (state == null || state.restartingIce || _endedCalls.contains(callId)) {
      _diag(
        callId,
        'restart_ice ignored reason=${state == null
            ? "missing"
            : state.restartingIce
            ? "in_progress"
            : "ended"}',
      );
      return;
    }
    state.restartingIce = true;
    try {
      final offer = await state.pc.createOffer({'iceRestart': true});
      await state.pc.setLocalDescription(offer);
      _eventController.add(
        RemoteRenegotiationOfferEvent(callId: callId, sdp: offer.sdp ?? ''),
      );
    } finally {
      state.restartingIce = false;
    }
  }

  @override
  Future<void> setMuted(String callId, {required bool muted}) async {
    final state = _calls[callId];
    if (state == null) return;
    for (final track in state.localStream.getAudioTracks()) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setSpeakerOn(String callId, {required bool enabled}) async {
    await webrtc.Helper.setSpeakerphoneOn(enabled);
  }

  @override
  Future<void> setVideoEnabled(String callId, {required bool enabled}) async {
    final state = _calls[callId];
    if (state == null) return;
    for (final track in state.localStream.getVideoTracks()) {
      track.enabled = enabled;
    }
    _eventController.add(
      RemoteVideoStateEvent(callId: callId, enabled: enabled),
    );
  }

  @override
  Future<void> switchCamera(String callId) async {
    final state = _calls[callId];
    if (state == null) return;
    final videoTracks = state.localStream.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      await webrtc.Helper.switchCamera(videoTracks.first);
    }
    state.isFrontCamera = !state.isFrontCamera;
    _eventController.add(
      RemoteCameraFacingEvent(
        callId: callId,
        isFrontCamera: state.isFrontCamera,
      ),
    );
  }

  @override
  Future<void> endCall(String callId) async {
    _diag(callId, 'end_call begin');
    _endedCalls.add(callId);
    _pendingCandidates.remove(callId);
    final state = _calls.remove(callId);
    if (state == null) {
      _diag(callId, 'end_call ignored reason=missing_state');
      return;
    }
    state.qualityTimer?.cancel();
    await _ignoreCleanup(state.pc.close);
    await _ignoreCleanup(state.pc.dispose);
    for (final track in state.localStream.getTracks()) {
      await _ignoreCleanup(track.stop);
    }
    await _ignoreCleanup(() => state.localRenderer.srcObject = null);
    await _ignoreCleanup(() => state.remoteRenderer.srcObject = null);
    await _ignoreCleanup(state.localStream.dispose);
    await _ignoreCleanup(() async {
      await state.remoteStream?.dispose();
    });
    await _ignoreCleanup(state.localRenderer.dispose);
    await _ignoreCleanup(state.remoteRenderer.dispose);
    _diag(callId, 'end_call cleanup_done');
  }

  @override
  Future<void> dispose() async {
    for (final callId in _calls.keys.toList()) {
      await endCall(callId);
    }
    _pendingCandidates.clear();
    await _eventController.close();
  }

  Future<void> _flushPendingCandidates(
    String callId,
    _PeerConnectionState state,
  ) async {
    final pending = _pendingCandidates.remove(callId) ?? const [];
    if (pending.isNotEmpty) {
      _diag(callId, 'remote_candidate flush count=${pending.length}');
    }
    for (final candidate in pending) {
      await _addCandidate(state, candidate);
    }
  }

  Future<void> _ignoreCleanup(FutureOr<void> Function() cleanup) async {
    try {
      await cleanup();
    } catch (_) {
      // Best-effort media cleanup must not strand the call state.
    }
  }

  Future<void> _addCandidate(
    _PeerConnectionState state,
    _RemoteIceCandidate candidate,
  ) async {
    if (!state.seenRemoteCandidates.add(candidate.key)) return;
    await state.pc.addCandidate(
      webrtc.RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.mlineIndex,
      ),
    );
  }

  void _diag(String callId, String message) {
    if (_eventController.isClosed) return;
    _eventController.add(
      RemoteCallEngineDiagnosticEvent(callId: callId, message: message),
    );
  }

  String _iceServerSchemes(RemoteIceConfig config) {
    final schemes = <String>{};
    for (final server in config.iceServers) {
      final index = server.url.indexOf(':');
      schemes.add(index <= 0 ? 'unknown' : server.url.substring(0, index));
    }
    return schemes.isEmpty ? 'none' : schemes.join(',');
  }

  String _candidateType(String candidate) {
    if (candidate.isEmpty) return 'end';
    final match = RegExp(r' typ ([A-Za-z0-9_-]+)').firstMatch(candidate);
    return match?.group(1) ?? 'unknown';
  }

  String _shortEnum(Object? value) {
    final text = value?.toString() ?? 'null';
    final dot = text.lastIndexOf('.');
    return dot == -1 ? text : text.substring(dot + 1);
  }

  Future<void> _sampleQuality(String callId, _PeerConnectionState state) async {
    if (_eventController.isClosed || _endedCalls.contains(callId)) return;
    try {
      final reports = await state.pc.getStats();
      _eventController.add(
        RemoteCallQualityEvent(
          callId: callId,
          metrics: _qualityFromReports(callId, state, reports),
        ),
      );
    } catch (_) {
      // Stats are best-effort diagnostics and must not perturb active media.
    }
  }

  CallQualityMetrics _qualityFromReports(
    String callId,
    _PeerConnectionState state,
    List<webrtc.StatsReport> reports,
  ) {
    var packetsLost = 0.0;
    var packetsReceived = 0.0;
    var jitterMs = 0.0;
    var roundTripMs = 0.0;
    var framesSent = 0;
    var framesReceived = 0;
    var framesDropped = 0;
    String? selectedCandidateType;
    String? selectedLocalCandidateId;
    var audioBitrateKbps = 0.0;
    double? videoBitrateKbps;
    final now = DateTime.now().millisecondsSinceEpoch;
    final byId = {for (final report in reports) report.id: report};

    for (final report in reports) {
      final values = report.values;
      num? number(String key) => values[key] is num ? values[key] as num : null;
      if (report.type == 'inbound-rtp') {
        packetsLost += (number('packetsLost') ?? 0).toDouble();
        packetsReceived += (number('packetsReceived') ?? 0).toDouble();
        jitterMs = (number('jitter') ?? 0).toDouble() * 1000;
        framesReceived += (number('framesReceived') ?? 0).toInt();
        framesDropped += (number('framesDropped') ?? 0).toInt();
      } else if (report.type == 'outbound-rtp') {
        framesSent += (number('framesSent') ?? 0).toInt();
        final bytesSent = number('bytesSent');
        if (bytesSent != null) {
          final bitrate = _bitrateKbpsFor(
            state,
            report.id,
            bytesSent.toInt(),
            now,
          );
          final kind = _mediaKind(values);
          if (kind == 'audio') {
            audioBitrateKbps += bitrate;
          } else if (kind == 'video') {
            videoBitrateKbps = (videoBitrateKbps ?? 0) + bitrate;
          }
        }
      } else if (report.type == 'candidate-pair' &&
          (values['selected'] == true || values['nominated'] == true)) {
        roundTripMs = (number('currentRoundTripTime') ?? 0).toDouble() * 1000;
        selectedLocalCandidateId = values['localCandidateId'] as String?;
      }
    }
    final localCandidate = selectedLocalCandidateId == null
        ? null
        : byId[selectedLocalCandidateId];
    if (localCandidate != null && localCandidate.type == 'local-candidate') {
      selectedCandidateType =
          localCandidate.values['candidateType'] as String? ??
          localCandidate.values['candidateType']?.toString();
    }

    final totalPackets = packetsReceived + packetsLost;
    final packetLossPercent = totalPackets == 0
        ? 0.0
        : (packetsLost / totalPackets) * 100;
    final isRelay = selectedCandidateType == 'relay';
    final hasInboundTraffic = packetsReceived > 0;
    final isWeak =
        packetLossPercent >= 8 ||
        jitterMs >= 120 ||
        (hasInboundTraffic && roundTripMs >= 1200);

    return CallQualityMetrics(
      callId: callId,
      packetLossPercent: packetLossPercent,
      jitterMs: jitterMs,
      roundTripMs: roundTripMs,
      audioBitrateKbps: audioBitrateKbps,
      videoBitrateKbps: videoBitrateKbps,
      selectedCandidateType: selectedCandidateType,
      isRelay: isRelay,
      framesSent: framesSent,
      framesReceived: framesReceived,
      framesDropped: framesDropped,
      isWeak: isWeak,
    );
  }

  double _bitrateKbpsFor(
    _PeerConnectionState state,
    String reportId,
    int bytesSent,
    int now,
  ) {
    final previous = state.previousOutboundBytes[reportId];
    state.previousOutboundBytes[reportId] = _BitrateSample(bytesSent, now);
    if (previous == null || bytesSent < previous.bytes) return 0;
    final elapsedMs = now - previous.timestampMs;
    if (elapsedMs <= 0) return 0;
    return ((bytesSent - previous.bytes) * 8) / elapsedMs;
  }

  String? _mediaKind(Map<dynamic, dynamic> values) {
    final kind = values['kind'] ?? values['mediaType'];
    return kind is String ? kind : null;
  }

  void _emitMedia(String callId, _PeerConnectionState state) {
    if (_eventController.isClosed) return;
    _eventController.add(
      RemoteCallMediaEvent(
        callId: callId,
        localStream: state.localStream,
        remoteStream: state.remoteStream,
        localRenderer: state.localRenderer,
        remoteRenderer: state.remoteRenderer,
      ),
    );
  }

  bool _isValidCandidate(String candidate) {
    if (candidate.isEmpty) return true;
    if (candidate.length > _maxCandidateLength) return false;
    return candidate.startsWith('candidate:');
  }

  RemoteCallEngineConnectionState _mapIceState(
    webrtc.RTCIceConnectionState state,
  ) {
    switch (state) {
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateChecking:
        return RemoteCallEngineConnectionState.checking;
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateConnected:
        return RemoteCallEngineConnectionState.connected;
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateCompleted:
        return RemoteCallEngineConnectionState.completed;
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        return RemoteCallEngineConnectionState.disconnected;
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateFailed:
        return RemoteCallEngineConnectionState.failed;
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateClosed:
        return RemoteCallEngineConnectionState.closed;
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateNew:
      case webrtc.RTCIceConnectionState.RTCIceConnectionStateCount:
        return RemoteCallEngineConnectionState.checking;
    }
  }
}

class _PeerConnectionState {
  _PeerConnectionState({
    required this.pc,
    required this.localStream,
    required this.localRenderer,
    required this.remoteRenderer,
  });

  final webrtc.RTCPeerConnection pc;
  final webrtc.MediaStream localStream;
  final webrtc.RTCVideoRenderer localRenderer;
  final webrtc.RTCVideoRenderer remoteRenderer;
  final Set<String> seenRemoteCandidates = <String>{};
  webrtc.MediaStream? remoteStream;
  Timer? qualityTimer;
  bool remoteDescriptionSet = false;
  bool restartingIce = false;
  bool isFrontCamera = true;
  final Map<String, _BitrateSample> previousOutboundBytes = {};
}

class _BitrateSample {
  const _BitrateSample(this.bytes, this.timestampMs);

  final int bytes;
  final int timestampMs;
}

class _RemoteIceCandidate {
  const _RemoteIceCandidate(this.candidate, this.mlineIndex, this.sdpMid);

  final String candidate;
  final int mlineIndex;
  final String sdpMid;

  String get key => '$candidate|$mlineIndex|$sdpMid';
}
