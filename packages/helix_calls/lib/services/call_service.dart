import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import 'package:helix_protocol/application/contracts/gateways.dart';
import 'package:helix_domain/domain/call/call_state.dart';
import 'package:helix_protocol/protocol/protocol_messages.dart';
import 'package:helix_calls/infrastructure/call/webrtc_call_engine.dart';

/// Orchestrates WebRTC call lifecycle: offer/answer negotiation, ICE exchange,
/// media control, and state transitions.
///
/// One call at a time is supported.  A second incoming offer while a call is
/// already in progress is automatically answered with a "busy" signal.
class CallService {
  CallService({required this._engine, required this._signalingGateway}) {
    _engineSub = _engine.events.listen(_handleEngineEvent);
  }

  final CallEngine _engine;
  final CallSignalingGateway _signalingGateway;
  late final StreamSubscription<CallEngineEvent> _engineSub;

  CallState? _currentCall;
  String? _pendingOfferSdp;
  bool _pendingOfferIsVideo = false;
  Timer? _autoEndTimer;
  final _stateController = StreamController<CallState?>.broadcast();

  Stream<CallState?> get callStateStream => _stateController.stream;
  CallState? get currentCall => _currentCall;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<void> initiateCall(String peerId, String peerDisplayName) async {
    if (_currentCall != null && _currentCall!.isInProgress) return;

    final callId = const Uuid().v4();
    _updateState(
      CallState(
        callId: callId,
        peerId: peerId,
        peerDisplayName: peerDisplayName,
        direction: CallDirection.outgoing,
        status: CallStatus.offering,
      ),
    );

    try {
      final sdp = await _engine.createOffer(callId);
      if (_currentCall?.callId != callId) {
        await _engine.endCall(callId).catchError((_) {});
        return;
      }
      await _signalingGateway.sendCallSignal(
        peerId,
        CallSignalFrame(callId: callId, signalType: 'offer', sdp: sdp),
      );
      if (_currentCall?.callId != callId) {
        return;
      }
      _autoEndTimer = Timer(
        const Duration(seconds: 60),
        () => _cancelByTimeout(callId),
      );
    } catch (_) {
      if (_currentCall?.callId == callId) {
        await _engine.endCall(callId).catchError((_) {});
        _updateState(_currentCall?.copyWith(status: CallStatus.failed));
        _scheduleCleanup(callId);
      } else {
        await _engine.endCall(callId).catchError((_) {});
      }
    }
  }

  Future<void> initiateVideoCall(String peerId, String peerDisplayName) async {
    if (_currentCall != null && _currentCall!.isInProgress) return;

    final callId = const Uuid().v4();
    _updateState(
      CallState(
        callId: callId,
        peerId: peerId,
        peerDisplayName: peerDisplayName,
        direction: CallDirection.outgoing,
        status: CallStatus.offering,
        isVideoEnabled: true,
      ),
    );

    try {
      final sdp = await _engine.createOffer(callId, video: true);
      if (_currentCall?.callId != callId) {
        await _engine.endCall(callId).catchError((_) {});
        return;
      }
      await _signalingGateway.sendCallSignal(
        peerId,
        CallSignalFrame(callId: callId, signalType: 'offer', sdp: sdp),
      );
      if (_currentCall?.callId != callId) {
        return;
      }
      _autoEndTimer = Timer(
        const Duration(seconds: 60),
        () => _cancelByTimeout(callId),
      );
    } catch (_) {
      if (_currentCall?.callId == callId) {
        await _engine.endCall(callId).catchError((_) {});
        _updateState(_currentCall?.copyWith(status: CallStatus.failed));
        _scheduleCleanup(callId);
      } else {
        await _engine.endCall(callId).catchError((_) {});
      }
    }
  }

  Future<void> acceptIncomingCall() async {
    final call = _currentCall;
    if (call == null ||
        call.status != CallStatus.ringing ||
        call.direction != CallDirection.incoming) {
      return;
    }

    final callId = call.callId;
    _autoEndTimer?.cancel();
    _autoEndTimer = null;

    try {
      final sdp = await _engine.createAnswer(
        callId,
        _pendingOfferSdp!,
        video: _pendingOfferIsVideo,
      );
      if (_currentCall?.callId != callId) {
        await _engine.endCall(callId).catchError((_) {});
        return;
      }
      _pendingOfferSdp = null;
      _pendingOfferIsVideo = false;
      // Use _currentCall (not the stale snapshot `call`) so that any state
      // changes that arrived asynchronously during the createAnswer await —
      // e.g. RemoteVideoStateEvent firing when setRemoteDescription processes
      // the caller's video track — are preserved rather than overwritten.
      _updateState(_currentCall!.copyWith(status: CallStatus.connecting));
      await _signalingGateway.sendCallSignal(
        call.peerId,
        CallSignalFrame(callId: callId, signalType: 'accept', sdp: sdp),
      );
    } catch (_) {
      if (_currentCall?.callId == callId) {
        await _engine.endCall(callId).catchError((_) {});
        _updateState(_currentCall?.copyWith(status: CallStatus.failed));
        _scheduleCleanup(callId);
      } else {
        await _engine.endCall(callId).catchError((_) {});
      }
    }
  }

  Future<void> toggleVideo() async {
    final call = _currentCall;
    if (call == null) return;
    final callId = call.callId;
    final videoOn = !call.isVideoEnabled;
    await _engine.setVideoEnabled(callId, enabled: videoOn);
    if (_currentCall?.callId != callId) return;
    _updateState(_currentCall!.copyWith(isVideoEnabled: videoOn));
  }

  Future<void> switchCamera() async {
    final call = _currentCall;
    if (call == null) return;
    final callId = call.callId;
    await _engine.switchCamera(callId);
  }

  Future<void> declineIncomingCall({bool timedOut = false, String? targetCallId}) async {
    final call = _currentCall;
    if (call == null) return;
    final callId = call.callId;
    if (targetCallId != null && callId != targetCallId) return;

    _autoEndTimer?.cancel();
    try {
      await _signalingGateway.sendCallSignal(
        call.peerId,
        CallSignalFrame(
          callId: callId,
          signalType: timedOut ? 'no-answer' : 'decline',
        ),
      );
    } catch (_) {}
    if (_currentCall?.callId != callId) {
      await _engine.endCall(callId).catchError((_) {});
      return;
    }
    await _engine.endCall(callId).catchError((_) {});
    _updateState(
      call.copyWith(
        status: CallStatus.ended,
        endReason: timedOut ? CallEndReason.noAnswer : CallEndReason.declined,
      ),
    );
    _scheduleCleanup(callId);
  }

  Future<void> endCurrentCall() async {
    final call = _currentCall;
    if (call == null) return;
    final callId = call.callId;
    _autoEndTimer?.cancel();
    _updateState(call.copyWith(status: CallStatus.ending));
    try {
      await _signalingGateway.sendCallSignal(
        call.peerId,
        CallSignalFrame(callId: callId, signalType: 'end'),
      );
    } catch (_) {}
    await _terminate(callId);
  }

  Future<void> toggleMute() async {
    final call = _currentCall;
    if (call == null) return;
    final callId = call.callId;
    final muted = !call.isMuted;
    await _engine.setMuted(callId, muted: muted);
    if (_currentCall?.callId != callId) return;
    _updateState(_currentCall!.copyWith(isMuted: muted));
  }

  Future<void> toggleSpeaker() async {
    final call = _currentCall;
    if (call == null) return;
    final callId = call.callId;
    final speakerOn = !call.isSpeakerOn;
    await _engine.setSpeakerOn(callId, enabled: speakerOn);
    if (_currentCall?.callId != callId) return;
    _updateState(_currentCall!.copyWith(isSpeakerOn: speakerOn));
  }

  /// Called by [MessagingService] when a [CallSignalFrame] arrives from [peerId].
  Future<void> handleSignal(
    String peerId,
    String peerDisplayName,
    CallSignalFrame frame,
  ) async {
    switch (frame.signalType) {
      case 'offer':
        await _handleOffer(peerId, peerDisplayName, frame);
      case 'video-offer':
        await _handleVideoOffer(frame);
      case 'ringing':
        if (_currentCall?.callId == frame.callId &&
            _currentCall!.direction == CallDirection.outgoing) {
          _updateState(_currentCall!.copyWith(status: CallStatus.ringing));
        }
      case 'accept':
      case 'answer':
      case 'video-answer':
        await _handleAnswer(frame);
      case 'ice':
        await _handleIce(frame);
      case 'decline':
      case 'no-answer':
      case 'busy':
      case 'cancel':
      case 'end':
        if (_currentCall?.callId == frame.callId) {
          _autoEndTimer?.cancel();
          try {
            await _engine.endCall(frame.callId);
          } finally {
            if (_currentCall?.callId == frame.callId) {
              final CallEndReason? reason = switch (frame.signalType) {
                'decline' => CallEndReason.declined,
                'no-answer' => CallEndReason.noAnswer,
                'busy' => CallEndReason.busy,
                _ => null,
              };
              _updateState(
                _currentCall!.copyWith(
                  status: CallStatus.ended,
                  endReason: reason,
                ),
              );
              _scheduleCleanup(frame.callId);
            }
          }
        }
    }
  }

  Future<void> dispose() async {
    _autoEndTimer?.cancel();
    await _engineSub.cancel();
    await _engine.dispose();
    if (!_stateController.isClosed) await _stateController.close();
  }

  // ---------------------------------------------------------------------------
  // Signal handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleOffer(
    String peerId,
    String peerDisplayName,
    CallSignalFrame frame,
  ) async {
    if (_currentCall != null && _currentCall!.isInProgress) {
      await _signalingGateway.sendCallSignal(
        peerId,
        CallSignalFrame(callId: frame.callId, signalType: 'busy'),
      );
      return;
    }
    final callId = frame.callId;
    _pendingOfferSdp = frame.sdp;
    _pendingOfferIsVideo = frame.sdp?.contains('m=video') ?? false;
    _updateState(
      CallState(
        callId: callId,
        peerId: peerId,
        peerDisplayName: peerDisplayName,
        direction: CallDirection.incoming,
        status: CallStatus.ringing,
        isVideoEnabled: _pendingOfferIsVideo,
      ),
    );
    _autoEndTimer = Timer(
      const Duration(seconds: 60),
      () => declineIncomingCall(timedOut: true, targetCallId: callId),
    );
    await _signalingGateway.sendCallSignal(
      peerId,
      CallSignalFrame(callId: callId, signalType: 'ringing'),
    );
  }

  Future<void> _handleVideoOffer(CallSignalFrame frame) async {
    final call = _currentCall;
    if (call == null || call.callId != frame.callId || frame.sdp == null) return;
    final callId = frame.callId;
    final answerSdp = await _engine.createAnswer(
      callId,
      frame.sdp!,
      video: true,
    );
    if (_currentCall?.callId != callId) {
      await _engine.endCall(callId).catchError((_) {});
      return;
    }
    await _signalingGateway.sendCallSignal(
      call.peerId,
      CallSignalFrame(
        callId: callId,
        signalType: 'video-answer',
        sdp: answerSdp,
      ),
    );
    if (_currentCall?.callId != callId) return;
    _updateState(
      _currentCall!.copyWith(isRemoteVideoEnabled: true, isVideoEnabled: true),
    );
  }

  Future<void> _handleAnswer(CallSignalFrame frame) async {
    final call = _currentCall;
    if (call == null || call.callId != frame.callId) return;
    final callId = frame.callId;
    if (frame.sdp != null) {
      await _engine.setRemoteAnswer(callId, frame.sdp!);
    }
    if (_currentCall?.callId != callId) return;
    if (_currentCall!.status != CallStatus.active) {
      _updateState(_currentCall!.copyWith(status: CallStatus.connecting));
    }
  }

  Future<void> _handleIce(CallSignalFrame frame) async {
    final call = _currentCall;
    if (call == null || call.callId != frame.callId) return;
    final callId = frame.callId;
    if (frame.candidate == null) return;
    await _engine.addIceCandidate(
      callId,
      frame.candidate!,
      frame.mlineIndex ?? 0,
      frame.sdpMid ?? '',
    );
  }

  // ---------------------------------------------------------------------------
  // Engine event handler
  // ---------------------------------------------------------------------------

  void _handleEngineEvent(CallEngineEvent event) {
    switch (event) {
      case IceCandidateEvent():
        final call = _currentCall;
        if (call == null || call.callId != event.callId) return;
        unawaited(
          _signalingGateway.sendCallSignal(
            call.peerId,
            CallSignalFrame(
              callId: event.callId,
              signalType: 'ice',
              candidate: event.candidate,
              mlineIndex: event.mlineIndex,
              sdpMid: event.sdpMid,
            ),
          ).catchError((_) {}),
        );
      case CallConnectionStateEvent():
        final call = _currentCall;
        if (call == null || call.callId != event.callId) return;
        if (event.connected) {
          _autoEndTimer?.cancel();
          _autoEndTimer = null;
          _updateState(
            call.copyWith(status: CallStatus.active, startedAt: DateTime.now()),
          );
        } else if (!call.isEnded) {
          unawaited(_engine.endCall(call.callId).catchError((_) {}));
          _updateState(call.copyWith(status: CallStatus.failed));
          _scheduleCleanup(event.callId);
        }
      case CallFailedEvent():
        final call = _currentCall;
        if (call == null || call.callId != event.callId) return;
        unawaited(_engine.endCall(call.callId).catchError((_) {}));
        _updateState(call.copyWith(status: CallStatus.failed));
        _scheduleCleanup(event.callId);
      case RemoteVideoStateEvent():
        final call = _currentCall;
        if (call == null || call.callId != event.callId) return;
        _updateState(call.copyWith(isRemoteVideoEnabled: event.enabled));
      case LocalCameraFacingEvent():
        final call = _currentCall;
        if (call == null || call.callId != event.callId) return;
        _updateState(call.copyWith(isFrontCamera: event.isFrontCamera));
      case RenegotiationOfferEvent():
        final call = _currentCall;
        if (call == null || call.callId != event.callId) return;
        unawaited(
          _signalingGateway.sendCallSignal(
            call.peerId,
            CallSignalFrame(
              callId: event.callId,
              signalType: 'video-offer',
              sdp: event.sdp,
            ),
          ).catchError((_) {}),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _cancelByTimeout(String callId) async {
    final call = _currentCall;
    if (call == null || call.callId != callId || call.isEnded) return;
    try {
      await _signalingGateway.sendCallSignal(
        call.peerId,
        CallSignalFrame(callId: callId, signalType: 'cancel'),
      );
    } catch (_) {}
    if (_currentCall?.callId != callId) {
      await _engine.endCall(callId).catchError((_) {});
      return;
    }
    await _engine.endCall(callId).catchError((_) {});
    _updateState(
      _currentCall!.copyWith(status: CallStatus.ended, endReason: CallEndReason.noAnswer),
    );
    _scheduleCleanup(callId);
  }

  Future<void> _terminate(String callId) async {
    try {
      await _engine.endCall(callId);
    } finally {
      if (_currentCall?.callId == callId) {
        _pendingOfferSdp = null;
        _pendingOfferIsVideo = false;
        _updateState(_currentCall!.copyWith(status: CallStatus.ended));
        _scheduleCleanup(callId);
      }
    }
  }

  void _scheduleCleanup(String callId) {
    Future.delayed(const Duration(seconds: 3), () {
      if (_currentCall?.callId == callId &&
          !_stateController.isClosed &&
          (_currentCall?.isEnded == true ||
              _currentCall?.status == CallStatus.failed)) {
        _updateState(null);
      }
    });
  }

  void _updateState(CallState? state) {
    _currentCall = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  RTCVideoRenderer? get localVideoRenderer {
    final engine = _engine;
    final callId = _currentCall?.callId;
    if (engine is! WebRtcCallEngine || callId == null) return null;
    return engine.localRendererFor(callId);
  }

  RTCVideoRenderer? get remoteVideoRenderer {
    final engine = _engine;
    final callId = _currentCall?.callId;
    if (engine is! WebRtcCallEngine || callId == null) return null;
    return engine.remoteRendererFor(callId);
  }
}
