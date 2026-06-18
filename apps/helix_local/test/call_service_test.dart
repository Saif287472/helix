// test/call_service_test.dart

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_domain/domain/call/call_state.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_calls/services/call_service.dart';

// ---------------------------------------------------------------------------
// Mock CallEngine
// ---------------------------------------------------------------------------

class _MockEngine implements CallEngine {
  final _eventsCtrl = StreamController<CallEngineEvent>.broadcast();
  final List<String> log = [];

  @override
  Stream<CallEngineEvent> get events => _eventsCtrl.stream;

  @override
  Future<String> createOffer(String callId, {bool video = false}) async {
    log.add('createOffer:$callId:video=$video');
    return 'sdp-offer';
  }

  @override
  Future<String> createAnswer(String callId, String offerSdp, {bool video = false}) async {
    log.add('createAnswer:$callId:video=$video');
    return 'sdp-answer';
  }

  @override
  Future<void> setRemoteAnswer(String callId, String answerSdp) async {
    log.add('setRemoteAnswer:$callId');
  }

  @override
  Future<void> addIceCandidate(
    String callId,
    String candidate,
    int mlineIndex,
    String sdpMid,
  ) async {
    log.add('addIce:$callId');
  }

  @override
  Future<void> setMuted(String callId, {required bool muted}) async {
    log.add('setMuted:$callId:$muted');
  }

  @override
  Future<void> setSpeakerOn(String callId, {required bool enabled}) async {
    log.add('setSpeakerOn:$callId:$enabled');
  }

  @override
  Future<void> setVideoEnabled(String callId, {required bool enabled}) async {
    log.add('setVideoEnabled:$callId:$enabled');
  }

  @override
  Future<void> switchCamera(String callId) async {
    log.add('switchCamera:$callId');
  }

  @override
  Future<void> endCall(String callId) async {
    log.add('endCall:$callId');
  }

  @override
  Future<void> dispose() async {
    await _eventsCtrl.close();
  }

  void emitConnected(String callId) => _eventsCtrl.add(
    CallConnectionStateEvent(callId: callId, connected: true),
  );

  void emitRemoteVideoState(String callId, bool enabled) => _eventsCtrl.add(
    RemoteVideoStateEvent(callId: callId, enabled: enabled),
  );

  void emitRenegotiationOffer(String callId, String sdp) => _eventsCtrl.add(
    RenegotiationOfferEvent(callId: callId, sdp: sdp),
  );
}

// ---------------------------------------------------------------------------
// Mock CallSignalingGateway
// ---------------------------------------------------------------------------

class _MockGateway implements CallSignalingGateway {
  final List<(String, CallSignalFrame)> sent = [];

  @override
  Future<void> sendCallSignal(String peerId, CallSignalFrame frame) async {
    sent.add((peerId, frame));
  }

  bool hasSent(String type, {String? toPeer}) => sent.any(
    (s) => s.$2.signalType == type && (toPeer == null || s.$1 == toPeer),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _MockEngine engine;
  late _MockGateway gateway;
  late CallService svc;

  setUp(() {
    engine = _MockEngine();
    gateway = _MockGateway();
    svc = CallService(engine: engine, signalingGateway: gateway);
  });

  tearDown(() => svc.dispose());

  group('CallService — outgoing call', () {
    test(
      'initiateCall creates offer, sends it, state becomes offering',
      () async {
        await svc.initiateCall('peer-1', 'Alice');

        expect(svc.currentCall?.status, CallStatus.offering);
        expect(svc.currentCall?.direction, CallDirection.outgoing);
        expect(svc.currentCall?.peerDisplayName, 'Alice');
        expect(engine.log.any((e) => e.startsWith('createOffer:')), isTrue);
        expect(gateway.hasSent('offer', toPeer: 'peer-1'), isTrue);
      },
    );

    test('ringing signal from peer updates state', () async {
      await svc.initiateCall('peer-1', 'Alice');
      final callId = svc.currentCall!.callId;

      await svc.handleSignal(
        'peer-1',
        'Alice',
        CallSignalFrame(callId: callId, signalType: 'ringing'),
      );

      expect(svc.currentCall?.status, CallStatus.ringing);
    });

    test('decline signal ends the call with declined reason', () async {
      await svc.initiateCall('peer-1', 'Alice');
      final callId = svc.currentCall!.callId;

      await svc.handleSignal(
        'peer-1',
        'Alice',
        CallSignalFrame(callId: callId, signalType: 'decline'),
      );

      expect(svc.currentCall?.status, CallStatus.ended);
      expect(svc.currentCall?.endReason, CallEndReason.declined);
      expect(engine.log.any((e) => e.startsWith('endCall:')), isTrue);
    });

    test('no-answer signal ends the call with noAnswer reason', () async {
      await svc.initiateCall('peer-1', 'Alice');
      final callId = svc.currentCall!.callId;

      await svc.handleSignal(
        'peer-1',
        'Alice',
        CallSignalFrame(callId: callId, signalType: 'no-answer'),
      );

      expect(svc.currentCall?.status, CallStatus.ended);
      expect(svc.currentCall?.endReason, CallEndReason.noAnswer);
    });

    test('busy signal ends the call with busy reason', () async {
      await svc.initiateCall('peer-1', 'Alice');
      final callId = svc.currentCall!.callId;

      await svc.handleSignal(
        'peer-1',
        'Alice',
        CallSignalFrame(callId: callId, signalType: 'busy'),
      );

      expect(svc.currentCall?.status, CallStatus.ended);
      expect(svc.currentCall?.endReason, CallEndReason.busy);
    });

    test('cancel signal ends the call with no specific reason', () async {
      await svc.initiateCall('peer-1', 'Alice');
      final callId = svc.currentCall!.callId;

      await svc.handleSignal(
        'peer-1',
        'Alice',
        CallSignalFrame(callId: callId, signalType: 'cancel'),
      );

      expect(svc.currentCall?.status, CallStatus.ended);
      expect(svc.currentCall?.endReason, isNull);
    });

    test(
      'caller auto-end timer is cancelled once the call connects',
      () {
        fakeAsync((async) {
          unawaited(svc.initiateCall('peer-1', 'Alice'));
          async.flushMicrotasks();
          final callId = svc.currentCall!.callId;

          engine.emitConnected(callId);
          async.flushMicrotasks();
          expect(svc.currentCall?.status, CallStatus.active);

          // Without the fix, the 60s no-answer timer set in initiateCall
          // would fire here and force-end an already-active call.
          async.elapse(const Duration(seconds: 65));
          expect(svc.currentCall?.status, CallStatus.active);
        });
      },
    );

    test('endCurrentCall sends end and calls engine.endCall', () async {
      await svc.initiateCall('peer-1', 'Alice');

      await svc.endCurrentCall();

      expect(gateway.hasSent('end', toPeer: 'peer-1'), isTrue);
      expect(engine.log.any((e) => e.startsWith('endCall:')), isTrue);
    });
  });

  group('CallService — incoming call', () {
    test('offer signal sets state to ringing and sends ringing back', () async {
      await svc.handleSignal(
        'peer-2',
        'Bob',
        CallSignalFrame(callId: 'c1', signalType: 'offer', sdp: 'sdp'),
      );

      expect(svc.currentCall?.status, CallStatus.ringing);
      expect(svc.currentCall?.direction, CallDirection.incoming);
      expect(svc.currentCall?.peerDisplayName, 'Bob');
      expect(gateway.hasSent('ringing', toPeer: 'peer-2'), isTrue);
    });

    test('acceptIncomingCall creates answer and sends accept', () async {
      await svc.handleSignal(
        'peer-2',
        'Bob',
        CallSignalFrame(callId: 'c1', signalType: 'offer', sdp: 'sdp'),
      );

      await svc.acceptIncomingCall();

      expect(svc.currentCall?.status, CallStatus.connecting);
      expect(engine.log.any((e) => e.startsWith('createAnswer:')), isTrue);
      expect(gateway.hasSent('accept', toPeer: 'peer-2'), isTrue);
    });

    test('declineIncomingCall sends decline and ends with declined reason', () async {
      await svc.handleSignal(
        'peer-2',
        'Bob',
        CallSignalFrame(callId: 'c1', signalType: 'offer', sdp: 'sdp'),
      );

      await svc.declineIncomingCall();

      expect(svc.currentCall?.status, CallStatus.ended);
      expect(svc.currentCall?.endReason, CallEndReason.declined);
      expect(gateway.hasSent('decline', toPeer: 'peer-2'), isTrue);
    });

    test(
      'declineIncomingCall(timedOut: true) sends no-answer and ends with noAnswer reason',
      () async {
        await svc.handleSignal(
          'peer-2',
          'Bob',
          CallSignalFrame(callId: 'c1', signalType: 'offer', sdp: 'sdp'),
        );

        await svc.declineIncomingCall(timedOut: true);

        expect(svc.currentCall?.status, CallStatus.ended);
        expect(svc.currentCall?.endReason, CallEndReason.noAnswer);
        expect(gateway.hasSent('no-answer', toPeer: 'peer-2'), isTrue);
      },
    );

    test('second offer while busy gets a busy reply', () async {
      await svc.initiateCall('peer-1', 'Alice');

      await svc.handleSignal(
        'peer-2',
        'Bob',
        CallSignalFrame(callId: 'other', signalType: 'offer', sdp: 'sdp'),
      );

      expect(gateway.hasSent('busy', toPeer: 'peer-2'), isTrue);
      expect(svc.currentCall?.peerId, 'peer-1');
    });
  });

  group('CallService — media control', () {
    test('toggleMute flips isMuted and calls engine', () async {
      await svc.initiateCall('peer-1', 'Alice');

      expect(svc.currentCall?.isMuted, isFalse);
      await svc.toggleMute();
      expect(svc.currentCall?.isMuted, isTrue);
      expect(
        engine.log.any((e) => e.contains('setMuted') && e.contains('true')),
        isTrue,
      );

      await svc.toggleMute();
      expect(svc.currentCall?.isMuted, isFalse);
    });

    test('toggleSpeaker flips isSpeakerOn and calls engine', () async {
      await svc.initiateCall('peer-1', 'Alice');

      expect(svc.currentCall?.isSpeakerOn, isFalse);
      await svc.toggleSpeaker();
      expect(svc.currentCall?.isSpeakerOn, isTrue);
      expect(
        engine.log.any(
          (e) => e.contains('setSpeakerOn') && e.contains('true'),
        ),
        isTrue,
      );

      await svc.toggleSpeaker();
      expect(svc.currentCall?.isSpeakerOn, isFalse);
    });
  });

  group('CallService — video calling', () {
    test('initiateVideoCall sets isVideoEnabled true and calls engine.createOffer with video: true', () async {
      await svc.initiateVideoCall('peer-1', 'Alice');

      expect(svc.currentCall?.status, CallStatus.offering);
      expect(svc.currentCall?.isVideoEnabled, isTrue);
      expect(
        engine.log.any((e) => e == 'createOffer:${svc.currentCall?.callId}:video=true'),
        isTrue,
      );
      expect(gateway.hasSent('offer', toPeer: 'peer-1'), isTrue);
    });

    test('acceptIncomingCall handles video offer properly', () async {
      await svc.handleSignal(
        'peer-2',
        'Bob',
        CallSignalFrame(callId: 'c1', signalType: 'offer', sdp: 'm=video sdp'),
      );
      expect(svc.currentCall?.isVideoEnabled, isTrue);

      await svc.acceptIncomingCall();
      expect(
        engine.log.any((e) => e == 'createAnswer:c1:video=true'),
        isTrue,
      );
      expect(gateway.hasSent('accept', toPeer: 'peer-2'), isTrue);
    });

    test('toggleVideo flips isVideoEnabled and calls engine.setVideoEnabled', () async {
      await svc.initiateCall('peer-1', 'Alice');
      final callId = svc.currentCall!.callId;

      expect(svc.currentCall?.isVideoEnabled, isFalse);
      await svc.toggleVideo();
      expect(svc.currentCall?.isVideoEnabled, isTrue);
      expect(
        engine.log.any((e) => e == 'setVideoEnabled:$callId:true'),
        isTrue,
      );

      await svc.toggleVideo();
      expect(svc.currentCall?.isVideoEnabled, isFalse);
      expect(
        engine.log.any((e) => e == 'setVideoEnabled:$callId:false'),
        isTrue,
      );
    });

    test('switchCamera calls engine.switchCamera', () async {
      await svc.initiateCall('peer-1', 'Alice');
      final callId = svc.currentCall!.callId;

      await svc.switchCamera();
      expect(
        engine.log.any((e) => e == 'switchCamera:$callId'),
        isTrue,
      );
    });

    test('handleSignal video-offer calls engine.createAnswer with video: true and sends video-answer', () async {
      await svc.initiateCall('peer-1', 'Alice');
      final callId = svc.currentCall!.callId;

      await svc.handleSignal(
        'peer-1',
        'Alice',
        CallSignalFrame(callId: callId, signalType: 'video-offer', sdp: 'renegotiate-sdp'),
      );

      expect(
        engine.log.any((e) => e == 'createAnswer:$callId:video=true'),
        isTrue,
      );
      expect(gateway.hasSent('video-answer', toPeer: 'peer-1'), isTrue);
      expect(svc.currentCall?.isRemoteVideoEnabled, isTrue);
    });

    test('RenegotiationOfferEvent triggers video-offer signal', () async {
      await svc.initiateCall('peer-1', 'Alice');
      final callId = svc.currentCall!.callId;

      engine.emitRenegotiationOffer(callId, 'renegotiate-sdp');
      await Future.delayed(Duration.zero);

      expect(
        gateway.sent.any(
          (s) =>
              s.$1 == 'peer-1' &&
              s.$2.signalType == 'video-offer' &&
              s.$2.sdp == 'renegotiate-sdp',
        ),
        isTrue,
      );
    });

    test('RemoteVideoStateEvent updates isRemoteVideoEnabled', () async {
      await svc.initiateCall('peer-1', 'Alice');
      final callId = svc.currentCall!.callId;

      expect(svc.currentCall?.isRemoteVideoEnabled, isFalse);
      engine.emitRemoteVideoState(callId, true);
      await Future.delayed(Duration.zero);
      expect(svc.currentCall?.isRemoteVideoEnabled, isTrue);
      engine.emitRemoteVideoState(callId, false);
      await Future.delayed(Duration.zero);
      expect(svc.currentCall?.isRemoteVideoEnabled, isFalse);
    });

    test(
      'handleSignal video-offer sets isVideoEnabled so the answering side '
      'also sends its own camera back, not just isRemoteVideoEnabled',
      () async {
        await svc.initiateCall('peer-1', 'Alice');
        final callId = svc.currentCall!.callId;

        expect(svc.currentCall?.isVideoEnabled, isFalse);
        await svc.handleSignal(
          'peer-1',
          'Alice',
          CallSignalFrame(
            callId: callId,
            signalType: 'video-offer',
            sdp: 'renegotiate-sdp',
          ),
        );

        expect(svc.currentCall?.isVideoEnabled, isTrue);
        expect(svc.currentCall?.isRemoteVideoEnabled, isTrue);
      },
    );

    test(
      'a video-answer received after the call is already active does not '
      'knock its status back to connecting',
      () async {
        fakeAsync((async) {
          unawaited(svc.initiateCall('peer-1', 'Alice'));
          async.flushMicrotasks();
          final callId = svc.currentCall!.callId;

          engine.emitConnected(callId);
          async.flushMicrotasks();
          expect(svc.currentCall?.status, CallStatus.active);

          unawaited(
            svc.handleSignal(
              'peer-1',
              'Alice',
              CallSignalFrame(
                callId: callId,
                signalType: 'video-answer',
                sdp: 'renegotiate-answer-sdp',
              ),
            ),
          );
          async.flushMicrotasks();

          expect(svc.currentCall?.status, CallStatus.active);
        });
      },
    );

    test(
      'the initial accept/answer handshake still moves the call to connecting',
      () async {
        await svc.initiateCall('peer-1', 'Alice');
        final callId = svc.currentCall!.callId;

        await svc.handleSignal(
          'peer-1',
          'Alice',
          CallSignalFrame(callId: callId, signalType: 'accept', sdp: 'sdp'),
        );

        expect(svc.currentCall?.status, CallStatus.connecting);
      },
    );
  });
}
