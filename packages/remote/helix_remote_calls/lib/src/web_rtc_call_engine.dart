import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:helix_remote_calls/helix_remote_calls.dart';

class RemoteWebRtcCallEngine implements RemoteCallEngine {
  RemoteWebRtcCallEngine({RemoteIceConfig? iceConfig})
    : _iceConfig =
          iceConfig ??
          const RemoteIceConfig(
            iceServers: [],
            ipPrivacy: IpPrivacyMode.relayOnly,
          );

  final RemoteIceConfig _iceConfig;
  final Map<String, _PeerConnectionState> _calls = {};
  final StreamController<RemoteCallEngineEvent> _eventController =
      StreamController<RemoteCallEngineEvent>.broadcast();

  @override
  Stream<RemoteCallEngineEvent> get events => _eventController.stream;

  webrtc.MediaStream? _localStream;

  Future<webrtc.MediaStream> _ensureLocalStream({bool video = false}) async {
    if (_localStream != null) return _localStream!;
    final stream = await webrtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video,
    });
    _localStream = stream;
    return stream;
  }

  Future<webrtc.RTCPeerConnection> _createPeerConnection(String callId) async {
    final config = {'iceServers': _iceConfig.toWebRtcIceServers()};
    final pc = await webrtc.createPeerConnection(config);
    pc.onIceCandidate = (candidate) {
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
      _eventController.add(
        RemoteCallConnectionStateEvent(
          callId: callId,
          connected:
              state ==
              webrtc.RTCIceConnectionState.RTCIceConnectionStateConnected,
        ),
      );
    };
    return pc;
  }

  @override
  Future<String> createOffer(String callId, {bool video = false}) async {
    final pc = await _createPeerConnection(callId);
    final stream = await _ensureLocalStream(video: video);
    for (final track in stream.getTracks()) {
      pc.addTrack(track, stream);
    }
    _calls[callId] = _PeerConnectionState(pc: pc);

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    return offer.sdp ?? '';
  }

  @override
  Future<String> createAnswer(
    String callId,
    String offerSdp, {
    bool video = false,
  }) async {
    final pc = await _createPeerConnection(callId);
    final stream = await _ensureLocalStream(video: video);
    for (final track in stream.getTracks()) {
      pc.addTrack(track, stream);
    }
    _calls[callId] = _PeerConnectionState(pc: pc);

    await pc.setRemoteDescription(
      webrtc.RTCSessionDescription(offerSdp, 'offer'),
    );
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return answer.sdp ?? '';
  }

  @override
  Future<void> setRemoteAnswer(String callId, String answerSdp) async {
    final state = _calls[callId];
    if (state == null) throw StateError('Unknown call: $callId');
    await state.pc.setRemoteDescription(
      webrtc.RTCSessionDescription(answerSdp, 'answer'),
    );
  }

  @override
  Future<void> addIceCandidate(
    String callId,
    String candidate,
    int mlineIndex,
    String sdpMid,
  ) async {
    final state = _calls[callId];
    if (state == null) throw StateError('Unknown call: $callId');
    await state.pc.addCandidate(
      webrtc.RTCIceCandidate(candidate, sdpMid, mlineIndex),
    );
  }

  @override
  Future<void> restartIce(String callId) async {
    final state = _calls[callId];
    if (state == null) return;
    final offer = await state.pc.createOffer();
    await state.pc.setLocalDescription(offer);
  }

  @override
  Future<void> setMuted(String callId, {required bool muted}) async {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !muted;
    }
  }

  @override
  Future<void> setSpeakerOn(String callId, {required bool enabled}) async {
    await webrtc.Helper.setSpeakerphoneOn(enabled);
  }

  @override
  Future<void> setVideoEnabled(String callId, {required bool enabled}) async {
    if (_localStream == null) return;
    for (final track in _localStream!.getVideoTracks()) {
      track.enabled = enabled;
    }
    _eventController.add(
      RemoteVideoStateEvent(callId: callId, enabled: enabled),
    );
  }

  @override
  Future<void> switchCamera(String callId) async {
    if (_localStream == null) return;
    final videoTracks = _localStream!.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      await webrtc.Helper.switchCamera(videoTracks.first);
    }
    _eventController.add(
      RemoteCameraFacingEvent(callId: callId, isFrontCamera: true),
    );
  }

  @override
  Future<void> endCall(String callId) async {
    final state = _calls.remove(callId);
    if (state != null) {
      await state.pc.close();
      state.pc.dispose();
    }
    if (_calls.isEmpty) {
      await _localStream?.dispose();
      _localStream = null;
    }
  }

  @override
  Future<void> dispose() async {
    for (final callId in _calls.keys.toList()) {
      await endCall(callId);
    }
    await _localStream?.dispose();
    _localStream = null;
    await _eventController.close();
  }
}

class _PeerConnectionState {
  _PeerConnectionState({required this.pc});
  final webrtc.RTCPeerConnection pc;
}
