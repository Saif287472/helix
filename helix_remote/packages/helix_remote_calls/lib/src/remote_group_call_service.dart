import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:helix_remote_calls/src/call_engine.dart';
import 'package:helix_remote_calls/src/ice_config.dart';
import 'package:helix_remote_calls/src/web_rtc_call_engine.dart';
import 'package:helix_remote_domain/models.dart';

// ---------------------------------------------------------------------------
// State types
// ---------------------------------------------------------------------------

class GroupCallParticipantState {
  const GroupCallParticipantState({
    required this.participant,
    this.remoteStream,
    this.audioLevel = 0.0,
    this.isActive = false,
  });

  final CallRoomParticipant participant;
  final webrtc.MediaStream? remoteStream;
  final double audioLevel;
  final bool isActive;

  GroupCallParticipantState copyWith({
    CallRoomParticipant? participant,
    webrtc.MediaStream? remoteStream,
    double? audioLevel,
    bool? isActive,
  }) => GroupCallParticipantState(
    participant: participant ?? this.participant,
    remoteStream: remoteStream ?? this.remoteStream,
    audioLevel: audioLevel ?? this.audioLevel,
    isActive: isActive ?? this.isActive,
  );
}

enum GroupCallStatus { idle, joining, active, ended }

class GroupCallState {
  const GroupCallState({
    required this.status,
    required this.roomId,
    required this.isVideo,
    required this.peers,
    this.localStream,
    this.activeSpeakerDeviceId,
    this.isScreenSharing = false,
    this.isMuted = false,
    this.error,
  });

  final GroupCallStatus status;
  final String roomId;
  final bool isVideo;
  final List<GroupCallParticipantState> peers;
  final webrtc.MediaStream? localStream;
  final String? activeSpeakerDeviceId;
  final bool isScreenSharing;
  final bool isMuted;
  final String? error;

  GroupCallState copyWith({
    GroupCallStatus? status,
    String? roomId,
    bool? isVideo,
    List<GroupCallParticipantState>? peers,
    webrtc.MediaStream? localStream,
    String? activeSpeakerDeviceId,
    bool clearActiveSpeaker = false,
    bool? isScreenSharing,
    bool? isMuted,
    String? error,
  }) => GroupCallState(
    status: status ?? this.status,
    roomId: roomId ?? this.roomId,
    isVideo: isVideo ?? this.isVideo,
    peers: peers ?? this.peers,
    localStream: localStream ?? this.localStream,
    activeSpeakerDeviceId:
        clearActiveSpeaker ? null : (activeSpeakerDeviceId ?? this.activeSpeakerDeviceId),
    isScreenSharing: isScreenSharing ?? this.isScreenSharing,
    isMuted: isMuted ?? this.isMuted,
    error: error,
  );
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// Full-mesh P2P group call service (≤4 participants).
///
/// Caller is responsible for:
///  - routing inbound WS events to [processRoomEvent]
///  - routing inbound signalling payloads (offer/answer/ice) to [processSignal]
///  - delivering outbound signals via the [signalSender] callback
class RemoteGroupCallService {
  RemoteGroupCallService({
    required this.myDeviceId,
    required this.myAccountId,
    required this.iceConfig,
    required this.signalSender,
    RemoteCallEngine Function(RemoteIceConfig)? engineFactory,
    this.wrappedKeyReceiver,
  }) : _engineFactory = engineFactory ?? _defaultEngineFactory;

  final String myDeviceId;
  final String myAccountId;
  final RemoteIceConfig iceConfig;
  final Future<void> Function(
    String roomId,
    String targetDeviceId,
    Map<String, dynamic> payload,
  ) signalSender;
  final Future<void> Function(
    String roomId,
    int epoch,
    String wrappedKey,
  )? wrappedKeyReceiver;

  final RemoteCallEngine Function(RemoteIceConfig) _engineFactory;

  // Per-peer connection state.
  final Map<String, RemoteCallEngine> _engines = {};
  final Map<String, StreamSubscription<RemoteCallEngineEvent>> _subs = {};
  final Map<String, GroupCallParticipantState> _peerStates = {};

  GroupCallState? _state;
  GroupCallState? get currentState => _state;

  final _stateController = StreamController<GroupCallState>.broadcast();
  Stream<GroupCallState> get stateStream => _stateController.stream;

  webrtc.MediaStream? _localStream;
  Timer? _speakerTimer;

  static const int _maxParticipants = 4;
  static const Duration _speakerInterval = Duration(milliseconds: 500);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Join room described by [room]. Creates engines for all existing JOINED peers
  /// and sends offers. Local stream is acquired here.
  Future<void> joinRoom(CallRoom room) async {
    if (_state?.status == GroupCallStatus.active) return;
    _emit(GroupCallState(
      status: GroupCallStatus.joining,
      roomId: room.roomId,
      isVideo: room.isVideo,
      peers: const [],
    ));

    try {
      _localStream = await _acquireLocalStream(room.isVideo);
    } catch (e) {
      _emit(_state!.copyWith(
        status: GroupCallStatus.ended,
        error: 'Media access denied: $e',
      ));
      return;
    }

    _emit(_state!.copyWith(
      status: GroupCallStatus.active,
      localStream: _localStream,
    ));

    // Connect to each currently JOINED peer that isn't us.
    for (final p in room.joinedParticipants) {
      if (p.deviceId == myDeviceId) continue;
      await _connectToPeer(room.roomId, p, sendOffer: true);
    }

    _startActiveSpeakerDetection();
  }

  /// Process a WebSocket room event pushed from the server.
  Future<void> processRoomEvent(
    String eventType,
    Map<String, dynamic> payload,
  ) async {
    final roomId = payload['room_id'] as String? ?? _state?.roomId ?? '';
    switch (eventType) {
      case 'participant_joined':
        final p = CallRoomParticipant(
          accountId: payload['account_id'] as String,
          deviceId: payload['device_id'] as String,
          role: 'PARTICIPANT',
          status: 'JOINED',
        );
        if (p.deviceId != myDeviceId &&
            !_engines.containsKey(p.deviceId) &&
            _peerStates.length < _maxParticipants - 1) {
          await _connectToPeer(roomId, p, sendOffer: false);
        }

      case 'participant_left':
      case 'participant_kicked':
        final deviceId = payload['device_id'] as String;
        await _removePeer(deviceId);

      case 'room_ended':
        await leaveRoom();
        _emit(_state!.copyWith(status: GroupCallStatus.ended));

      case 'screen_sharing_changed':
        final deviceId = payload['device_id'] as String;
        final active = payload['active'] == true;
        if (_peerStates.containsKey(deviceId)) {
          final existing = _peerStates[deviceId]!;
          _peerStates[deviceId] = existing.copyWith(
            participant: CallRoomParticipant(
              accountId: existing.participant.accountId,
              deviceId: existing.participant.deviceId,
              role: existing.participant.role,
              status: existing.participant.status,
              isScreenSharing: active,
              joinedAt: existing.participant.joinedAt,
            ),
          );
          _emitPeers();
        }
    }
  }

  /// Process an inbound WebRTC signal (offer/answer/ice) from a peer.
  Future<void> processSignal(Map<String, dynamic> signal) async {
    final type = signal['type'] as String?;
    final roomId = signal['room_id'] as String? ?? _state?.roomId ?? '';
    final senderDeviceId = signal['sender_device_id'] as String? ?? '';
    final senderAccountId = signal['sender_account_id'] as String? ?? '';
    if (senderDeviceId.isEmpty || senderDeviceId == myDeviceId) return;

    if (!_engines.containsKey(senderDeviceId)) {
      final p = CallRoomParticipant(
        accountId: senderAccountId,
        deviceId: senderDeviceId,
        role: 'PARTICIPANT',
        status: 'JOINED',
      );
      await _connectToPeer(roomId, p, sendOffer: false);
    }

    final engine = _engines[senderDeviceId]!;
    final callId = _peerCallId(roomId, senderDeviceId);

    switch (type) {
      case 'offer':
        final sdp = signal['sdp'] as String;
        final answer = await engine.createAnswer(callId, sdp, video: _state?.isVideo ?? false);
        await signalSender(roomId, senderDeviceId, {
          'type': 'answer',
          'sdp': answer,
          'sender_device_id': myDeviceId,
          'sender_account_id': myAccountId,
          'room_id': roomId,
        });
      case 'answer':
        await engine.setRemoteAnswer(callId, signal['sdp'] as String);
      case 'ice':
        await engine.addIceCandidate(
          callId,
          signal['candidate'] as String,
          signal['mline_index'] as int,
          signal['sdp_mid'] as String,
        );
      case 'room_key':
        final epoch = signal['epoch'] as int;
        final wrappedKey = signal['wrapped_key'] as String;
        await wrappedKeyReceiver?.call(roomId, epoch, wrappedKey);
    }
  }

  Future<void> setMuted(bool muted) async {
    for (final e in _engines.values) {
      await e.setMuted(_peerCallIdFromEngine(e), muted: muted);
    }
    _emit(_state!.copyWith(isMuted: muted));
  }

  Future<void> setVideoEnabled(bool enabled) async {
    for (final e in _engines.values) {
      await e.setVideoEnabled(_peerCallIdFromEngine(e), enabled: enabled);
    }
  }

  Future<void> setSpeakerOn(bool on) async {
    for (final e in _engines.values) {
      await e.setSpeakerOn(_peerCallIdFromEngine(e), enabled: on);
    }
  }

  Future<void> toggleScreenShare(bool active) async {
    _emit(_state!.copyWith(isScreenSharing: active));
  }

  Future<void> leaveRoom() async {
    _speakerTimer?.cancel();
    _speakerTimer = null;
    final roomId = _state?.roomId ?? '';
    for (final deviceId in _engines.keys.toList()) {
      await _removePeer(deviceId);
    }
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    _emit(GroupCallState(
      status: GroupCallStatus.ended,
      roomId: roomId,
      isVideo: _state?.isVideo ?? false,
      peers: const [],
    ));
  }

  Future<void> dispose() async {
    await leaveRoom();
    await _stateController.close();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _connectToPeer(
    String roomId,
    CallRoomParticipant p,
    {required bool sendOffer}
  ) async {
    if (_engines.containsKey(p.deviceId)) return;
    final engine = _engineFactory(iceConfig);
    _engines[p.deviceId] = engine;
    _peerStates[p.deviceId] = GroupCallParticipantState(participant: p);

    final callId = _peerCallId(roomId, p.deviceId);

    final sub = engine.events.listen((event) {
      _handleEngineEvent(roomId, p.deviceId, event);
    });
    _subs[p.deviceId] = sub;
    _emitPeers();

    if (sendOffer) {
      final offerSdp = await engine.createOffer(callId, video: _state?.isVideo ?? false);
      await signalSender(roomId, p.deviceId, {
        'type': 'offer',
        'sdp': offerSdp,
        'sender_device_id': myDeviceId,
        'sender_account_id': myAccountId,
        'room_id': roomId,
      });
    }
  }

  void _handleEngineEvent(String roomId, String deviceId, RemoteCallEngineEvent event) {
    if (event is RemoteIceCandidateEvent) {
      signalSender(roomId, deviceId, {
        'type': 'ice',
        'candidate': event.candidate,
        'mline_index': event.mlineIndex,
        'sdp_mid': event.sdpMid,
        'sender_device_id': myDeviceId,
        'sender_account_id': myAccountId,
        'room_id': roomId,
      }).ignore();
    } else if (event is RemoteCallMediaEvent) {
      if (event.remoteStream != null && _peerStates.containsKey(deviceId)) {
        _peerStates[deviceId] = _peerStates[deviceId]!.copyWith(
          remoteStream: event.remoteStream,
        );
        _emitPeers();
      }
    } else if (event is RemoteRenegotiationOfferEvent) {
      signalSender(roomId, deviceId, {
        'type': 'offer',
        'sdp': event.sdp,
        'sender_device_id': myDeviceId,
        'sender_account_id': myAccountId,
        'room_id': roomId,
      }).ignore();
    }
  }

  Future<void> _removePeer(String deviceId) async {
    await _subs.remove(deviceId)?.cancel();
    final engine = _engines.remove(deviceId);
    if (engine != null) {
      final callId = _state != null
          ? _peerCallId(_state!.roomId, deviceId)
          : deviceId;
      await engine.endCall(callId);
      await engine.dispose();
    }
    _peerStates.remove(deviceId);
    _emitPeers();
  }

  void _startActiveSpeakerDetection() {
    _speakerTimer = Timer.periodic(_speakerInterval, (_) {
      if (_peerStates.isEmpty) return;
      String? loudest;
      double maxLevel = 0.01; // noise floor
      for (final entry in _peerStates.entries) {
        final level = entry.value.audioLevel;
        if (level > maxLevel) {
          maxLevel = level;
          loudest = entry.key;
        }
      }
      final changed = loudest != _state?.activeSpeakerDeviceId;
      if (changed) {
        _emit(_state!.copyWith(activeSpeakerDeviceId: loudest, clearActiveSpeaker: loudest == null));
      }
    });
  }

  void _emitPeers() {
    if (_state == null) return;
    _emit(_state!.copyWith(peers: _peerStates.values.toList()));
  }

  void _emit(GroupCallState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  String _peerCallId(String roomId, String deviceId) => '$roomId:$deviceId';

  // Reverse-look up the call ID from the engine reference.
  String _peerCallIdFromEngine(RemoteCallEngine engine) {
    final roomId = _state?.roomId ?? '';
    for (final entry in _engines.entries) {
      if (identical(entry.value, engine)) {
        return _peerCallId(roomId, entry.key);
      }
    }
    return roomId;
  }

  static Future<webrtc.MediaStream> _acquireLocalStream(bool video) async {
    return webrtc.navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
  }

  static RemoteCallEngine _defaultEngineFactory(RemoteIceConfig config) =>
      RemoteWebRtcCallEngine(iceConfig: config);

  // Test seeding — bypasses getUserMedia so state-machine logic can be tested
  // without real WebRTC / platform channels.
  // ignore: invalid_use_of_visible_for_testing_member
  void seedState(GroupCallState state) => _emit(state);

  // Expose peer video renderers for the UI.
  webrtc.MediaStream? remoteStreamForDevice(String deviceId) =>
      _peerStates[deviceId]?.remoteStream;

  webrtc.MediaStream? get localStream => _localStream;
}
