// lib/infrastructure/call/webrtc_call_engine.dart

import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';

/// LAN-only WebRTC call engine built on flutter_webrtc.
///
/// Ice candidate filtering: only host-type candidates whose IP address falls
/// in a private (RFC 1918 / loopback) range are forwarded to signaling.
/// No STUN or TURN servers are configured.
class WebRtcCallEngine implements CallEngine {
  final Map<String, _CallSession> _sessions = {};
  final Map<String, Future<_CallSession>> _creating = {};
  final _eventsController = StreamController<CallEngineEvent>.broadcast();
  final _cancelledCalls = <String>{};
  bool _disposed = false;

  @override
  Stream<CallEngineEvent> get events => _eventsController.stream;

  @override
  Future<String> createOffer(String callId, {bool video = false}) async {
    final session = await _getOrCreateSession(callId, video: video);
    final offer = await session.pc.createOffer();
    await session.pc.setLocalDescription(offer);
    session.initialNegotiationDone = true;
    return offer.sdp!;
  }

  @override
  Future<String> createAnswer(String callId, String offerSdp, {bool video = false}) async {
    final session = await _getOrCreateSession(callId, video: video);
    await session.pc.setRemoteDescription(
      RTCSessionDescription(offerSdp, 'offer'),
    );
    final answer = await session.pc.createAnswer();
    await session.pc.setLocalDescription(answer);
    session.initialNegotiationDone = true;
    return answer.sdp!;
  }

  @override
  Future<void> setRemoteAnswer(String callId, String answerSdp) async {
    final session = _sessions[callId];
    if (session == null) return;
    await session.pc.setRemoteDescription(
      RTCSessionDescription(answerSdp, 'answer'),
    );
  }

  @override
  Future<void> addIceCandidate(
    String callId,
    String candidate,
    int mlineIndex,
    String sdpMid,
  ) async {
    final session = _sessions[callId];
    if (session == null) return;
    await session.pc.addCandidate(
      RTCIceCandidate(candidate, sdpMid, mlineIndex),
    );
  }

  @override
  Future<void> setMuted(String callId, {required bool muted}) async {
    final session = _sessions[callId];
    if (session == null) return;
    for (final track in session.localStream.getAudioTracks()) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setSpeakerOn(String callId, {required bool enabled}) async {
    final session = _sessions[callId];
    if (session == null) return;
    await Helper.setSpeakerphoneOn(enabled);
  }

  @override
  Future<void> setVideoEnabled(String callId, {required bool enabled}) async {
    final session = _sessions[callId];
    if (session == null) return;
    final existing = session.localStream.getVideoTracks();
    if (existing.isNotEmpty) {
      for (final track in existing) {
        track.enabled = enabled;
      }
      return;
    }
    if (!enabled) return;
    await _ensureLocalVideoTrack(session);
  }

  /// Opens the camera and adds a local video track to [session]'s stream
  /// and peer connection, if it doesn't already have one. Adding a track to
  /// an already-negotiated connection triggers [RTCPeerConnection.onRenegotiationNeeded].
  ///
  /// Used both when the local user turns their own camera on mid-call, and
  /// when answering a peer's video offer/upgrade — in the latter case the
  /// session (and its audio-only local stream) already exists, so a plain
  /// `video: true` flag passed into [createAnswer] would otherwise be
  /// silently ignored and this side would never send its own video back.
  Future<void> _ensureLocalVideoTrack(_CallSession session) async {
    if (session.localStream.getVideoTracks().isNotEmpty) return;
    MediaStream? videoStream;
    MediaStreamTrack? videoTrack;
    try {
      videoStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': true,
      });
      final tracks = videoStream.getVideoTracks();
      if (tracks.isEmpty) throw StateError('Camera returned no video track');
      videoTrack = tracks.first;
      await session.pc.addTrack(videoTrack, session.localStream);
      await session.localStream.addTrack(videoTrack);
      session.localRenderer.srcObject = session.localStream;
      session.auxiliaryStreams.add(videoStream);
    } catch (_) {
      try { await videoTrack?.stop(); } catch (_) {}
      try { await videoStream?.dispose(); } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> switchCamera(String callId) async {
    final session = _sessions[callId];
    if (session == null) return;
    final tracks = session.localStream.getVideoTracks();
    if (tracks.isEmpty) return;
    // Helper.switchCamera resolves with whether the camera is now
    // front-facing (see flutter_webrtc's CameraSwitchHandler.onCameraSwitchDone).
    final isFront = await Helper.switchCamera(tracks.first);
    session.isFrontCamera = isFront;
    if (!_eventsController.isClosed) {
      _eventsController.add(
        LocalCameraFacingEvent(callId: callId, isFrontCamera: isFront),
      );
    }
  }

  RTCVideoRenderer? localRendererFor(String callId) => _sessions[callId]?.localRenderer;
  RTCVideoRenderer? remoteRendererFor(String callId) => _sessions[callId]?.remoteRenderer;

  @override
  Future<void> endCall(String callId) async {
    _cancelledCalls.add(callId);
    final pending = _creating[callId];
    final session = _sessions.remove(callId);
    await session?.disposeBestEffort();

    if (pending != null) {
      _CallSession? lateSession;
      try { lateSession = await pending; } catch (_) {}
      await lateSession?.disposeBestEffort();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in sessions) {
      await session.disposeBestEffort();
    }
    final creatingFutures = _creating.values.toList();
    _creating.clear();
    for (final fut in creatingFutures) {
      _CallSession? lateSession;
      try { lateSession = await fut; } catch (_) {}
      await lateSession?.disposeBestEffort();
    }
    if (!_eventsController.isClosed) await _eventsController.close();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<_CallSession> _getOrCreateSession(String callId, {bool video = false}) async {
    if (_disposed) throw StateError('Engine disposed');

    if (_sessions.containsKey(callId)) {
      final session = _sessions[callId]!;
      if (video) await _ensureLocalVideoTrack(session);
      return session;
    }

    return _creating.putIfAbsent(callId, () async {
      try {
        final session = await _createSession(callId, video: video);
        if (_disposed || _cancelledCalls.contains(callId)) {
          await session.disposeBestEffort();
          throw StateError('Call cancelled or engine disposed');
        }
        _sessions[callId] = session;
        return session;
      } finally {
        _creating.remove(callId);
      }
    });
  }

  Future<_CallSession> _createSession(String callId, {bool video = false}) async {
    MediaStream? stream;
    MediaStream? remoteStream;
    RTCVideoRenderer? localRenderer;
    RTCVideoRenderer? remoteRenderer;
    RTCPeerConnection? pc;

    try {
      stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video,
      });

      // A dedicated stream to accumulate incoming remote tracks. In
      // unified-plan (which we use), RTCTrackEvent.streams is often empty
      // because each track has its own SDP section with no associated stream
      // id, so we cannot rely on event.streams to get the remote media.
      remoteStream = await createLocalMediaStream('remote_$callId');

      localRenderer = RTCVideoRenderer();
      await localRenderer.initialize();
      remoteRenderer = RTCVideoRenderer();
      await remoteRenderer.initialize();
      if (video) localRenderer.srcObject = stream;

      pc = await createPeerConnection({
        'iceServers': <dynamic>[], // LAN-only: no STUN/TURN
        'sdpSemantics': 'unified-plan',
      });

      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }

      pc.onIceCandidate = (RTCIceCandidate candidate) {
        if (_eventsController.isClosed) return;
        final raw = candidate.candidate;
        if (raw == null || !_isLanCandidate(raw)) return;
        _eventsController.add(
          IceCandidateEvent(
            callId: callId,
            candidate: raw,
            mlineIndex: candidate.sdpMLineIndex ?? 0,
            sdpMid: candidate.sdpMid ?? '',
          ),
        );
      };

      pc.onConnectionState = (RTCPeerConnectionState state) {
        if (_eventsController.isClosed) return;
        switch (state) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _eventsController.add(
              CallConnectionStateEvent(callId: callId, connected: true),
            );
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            _eventsController.add(
              CallConnectionStateEvent(callId: callId, connected: false),
            );
          default:
            break;
        }
      };

      // Capture for closure; remoteStream is guaranteed non-null here.
      final capturedRemoteStream = remoteStream;
      pc.onTrack = (RTCTrackEvent event) {
        // unified-plan: event.streams is often empty — add the track to our
        // own accumulation stream so the renderer always has a source.
        capturedRemoteStream.addTrack(event.track);
        remoteRenderer!.srcObject = capturedRemoteStream;
        if (event.track.kind == 'video' && !_eventsController.isClosed) {
          _eventsController.add(
            RemoteVideoStateEvent(callId: callId, enabled: true),
          );
        }
      };

      final capturedPc = pc;
      pc.onRenegotiationNeeded = () async {
        try {
          final session = _sessions[callId];
          if (session == null || !session.initialNegotiationDone) return;
          if (_eventsController.isClosed) return;
          final offer = await capturedPc.createOffer();
          // Re-check: session may have ended while we awaited.
          if (_sessions[callId] == null || _eventsController.isClosed) return;
          await capturedPc.setLocalDescription(offer);
          _eventsController.add(
            RenegotiationOfferEvent(callId: callId, sdp: offer.sdp!),
          );
        } catch (_) {}
      };

      return _CallSession(
        callId: callId,
        pc: pc,
        localStream: stream,
        remoteStream: remoteStream,
        localRenderer: localRenderer,
        remoteRenderer: remoteRenderer,
      );
    } catch (e) {
      // Dispose resources that were successfully created before the failure.
      try { await pc?.close(); } catch (_) {}
      try { await localRenderer?.dispose(); } catch (_) {}
      try { await remoteRenderer?.dispose(); } catch (_) {}
      try { await remoteStream?.dispose(); } catch (_) {}
      if (stream != null) {
        for (final track in stream.getTracks()) {
          try { await track.stop(); } catch (_) {}
        }
        try { await stream.dispose(); } catch (_) {}
      }
      rethrow;
    }
  }

  static bool _isLanCandidate(String candidate) {
    if (!candidate.contains('typ host')) return false;
    final parts = candidate.split(' ');
    if (parts.length < 5) return false;
    return _isPrivateIp(parts[4]);
  }

  static bool _isPrivateIp(String ip) {
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('127.')) return true;
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? 0;
        if (second >= 16 && second <= 31) return true;
      }
    }
    return false;
  }
}

class _CallSession {
  _CallSession({
    required this.callId,
    required this.pc,
    required this.localStream,
    required this.remoteStream,
    required this.localRenderer,
    required this.remoteRenderer,
  });

  final String callId;
  final RTCPeerConnection pc;
  final MediaStream localStream;
  final MediaStream remoteStream;
  final RTCVideoRenderer localRenderer;
  final RTCVideoRenderer remoteRenderer;
  final List<MediaStream> auxiliaryStreams = [];
  bool initialNegotiationDone = false;
  bool isFrontCamera = true;

  Future<void> disposeBestEffort() async {
    for (final track in localStream.getTracks()) {
      try { await track.stop(); } catch (_) {}
    }
    try { await localStream.dispose(); } catch (_) {}
    for (final stream in auxiliaryStreams) {
      for (final track in stream.getTracks()) {
        try { await track.stop(); } catch (_) {}
      }
      try { await stream.dispose(); } catch (_) {}
    }
    auxiliaryStreams.clear();
    try { await remoteStream.dispose(); } catch (_) {}
    try { await pc.close(); } catch (_) {}
    try { await localRenderer.dispose(); } catch (_) {}
    try { await remoteRenderer.dispose(); } catch (_) {}
  }
}
