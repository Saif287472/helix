// Tests for Phase F8: RemoteGroupCallService — mesh connect, signalling,
// active-speaker rotation, leave/end room, kick handling.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

// ---------------------------------------------------------------------------
// Stub engine
// ---------------------------------------------------------------------------

class _StubEngine implements RemoteCallEngine {
  final _ctrl = StreamController<RemoteCallEngineEvent>.broadcast();
  final List<String> log = [];
  bool disposed = false;

  @override
  Stream<RemoteCallEngineEvent> get events => _ctrl.stream;

  void emitIce(String callId) => _ctrl.add(
    RemoteIceCandidateEvent(
      callId: callId,
      candidate: 'cand',
      mlineIndex: 0,
      sdpMid: '0',
    ),
  );

  void emitRemoteStream(String callId) =>
      _ctrl.add(RemoteCallMediaEvent(callId: callId, remoteStream: null));

  @override
  Future<String> createOffer(String callId, {bool video = false}) async {
    log.add('offer:$callId');
    return 'stub_offer';
  }

  @override
  Future<String> createAnswer(
    String callId,
    String offerSdp, {
    bool video = false,
  }) async {
    log.add('answer:$callId');
    return 'stub_answer';
  }

  @override
  Future<void> setRemoteAnswer(String callId, String answerSdp) async {
    log.add('setAnswer:$callId');
  }

  @override
  Future<void> addIceCandidate(
    String callId,
    String c,
    int m,
    String mid,
  ) async {
    log.add('ice:$callId');
  }

  @override
  Future<void> restartIce(String callId) async {}

  @override
  Future<void> setMuted(String callId, {required bool muted}) async {}

  @override
  Future<void> setSpeakerOn(String callId, {required bool enabled}) async {}

  @override
  Future<void> setVideoEnabled(String callId, {required bool enabled}) async {}

  @override
  Future<void> switchCamera(String callId) async {}

  @override
  Future<void> endCall(String callId) async {
    log.add('end:$callId');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _ctrl.close();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

RemoteGroupCallService _makeService({
  String myDeviceId = 'alice_dev1',
  String myAccountId = 'alice',
  List<Map<String, dynamic>> outbound = const [],
  List<_StubEngine> engines = const [],
  int engineIndex = 0,
}) {
  final capturedSignals = outbound;
  var idx = engineIndex;
  final engineList = engines;

  return RemoteGroupCallService(
    myDeviceId: myDeviceId,
    myAccountId: myAccountId,
    iceConfig: RemoteIceConfig.defaultStun(),
    signalSender: (roomId, targetDevice, payload) async {
      capturedSignals.add({...payload, '_to': targetDevice, '_room': roomId});
    },
    engineFactory: (_) {
      final e = engineList.isNotEmpty && idx < engineList.length
          ? engineList[idx++]
          : _StubEngine();
      return e;
    },
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('RemoteGroupCallService', () {
    test('leaveRoom on fresh service emits ended state', () async {
      final svc = _makeService();
      // getUserMedia is a platform call — bypass by going straight to leaveRoom.
      await svc.leaveRoom();
      expect(svc.currentState?.status, GroupCallStatus.ended);
    });

    test(
      'processRoomEvent participant_joined triggers offer to new peer',
      () async {
        final signals = <Map<String, dynamic>>[];
        final bobEngine = _StubEngine();
        final svc = _makeService(outbound: signals, engines: [bobEngine]);

        // Simulate already-active state (skip media acquisition).
        svc.seedState(
          GroupCallState(
            status: GroupCallStatus.active,
            roomId: 'room_001',
            isVideo: true,
            peers: const [],
          ),
        );

        await svc.processRoomEvent('participant_joined', {
          'room_id': 'room_001',
          'account_id': 'bob',
          'device_id': 'bob_dev1',
          'is_video': true,
        });

        await Future<void>.delayed(Duration.zero);

        expect(
          bobEngine.log.any((l) => l.startsWith('offer:')),
          isTrue,
          reason: 'should have sent an offer to the new participant',
        );
        expect(
          signals.any((s) => s['type'] == 'offer' && s['_to'] == 'bob_dev1'),
          isTrue,
        );
      },
    );

    test('inbound offer triggers answer', () async {
      final signals = <Map<String, dynamic>>[];
      final bobEngine = _StubEngine();
      final svc = _makeService(outbound: signals, engines: [bobEngine]);

      svc.seedState(
        GroupCallState(
          status: GroupCallStatus.active,
          roomId: 'room_001',
          isVideo: true,
          peers: const [],
        ),
      );

      await svc.processSignal({
        'type': 'offer',
        'sdp': 'remote_offer_sdp',
        'sender_device_id': 'bob_dev1',
        'sender_account_id': 'bob',
        'room_id': 'room_001',
      });

      await Future<void>.delayed(Duration.zero);

      expect(
        signals.any((s) => s['type'] == 'answer' && s['_to'] == 'bob_dev1'),
        isTrue,
      );
      expect(bobEngine.log.any((l) => l.startsWith('answer:')), isTrue);
    });

    test('inbound answer sets remote description', () async {
      final signals = <Map<String, dynamic>>[];
      final bobEngine = _StubEngine();
      final svc = _makeService(outbound: signals, engines: [bobEngine]);

      svc.seedState(
        GroupCallState(
          status: GroupCallStatus.active,
          roomId: 'room_001',
          isVideo: false,
          peers: const [],
        ),
      );

      // First send an offer so the engine exists.
      await svc.processRoomEvent('participant_joined', {
        'room_id': 'room_001',
        'account_id': 'bob',
        'device_id': 'bob_dev1',
        'is_video': false,
      });
      await Future<void>.delayed(Duration.zero);

      // Now receive the answer back.
      await svc.processSignal({
        'type': 'answer',
        'sdp': 'bob_answer_sdp',
        'sender_device_id': 'bob_dev1',
        'sender_account_id': 'bob',
        'room_id': 'room_001',
      });

      expect(bobEngine.log.any((l) => l.startsWith('setAnswer:')), isTrue);
    });

    test('participant_left removes peer and disposes engine', () async {
      final bobEngine = _StubEngine();
      final svc = _makeService(engines: [bobEngine]);

      svc.seedState(
        GroupCallState(
          status: GroupCallStatus.active,
          roomId: 'room_001',
          isVideo: true,
          peers: const [],
        ),
      );

      await svc.processRoomEvent('participant_joined', {
        'room_id': 'room_001',
        'account_id': 'bob',
        'device_id': 'bob_dev1',
        'is_video': true,
      });
      await Future<void>.delayed(Duration.zero);

      expect(svc.currentState!.peers.length, 1);

      await svc.processRoomEvent('participant_left', {
        'room_id': 'room_001',
        'device_id': 'bob_dev1',
      });
      await Future<void>.delayed(Duration.zero);

      expect(svc.currentState!.peers, isEmpty);
      expect(bobEngine.disposed, isTrue);
    });

    test('room_ended event transitions to ended status', () async {
      final svc = _makeService();

      svc.seedState(
        GroupCallState(
          status: GroupCallStatus.active,
          roomId: 'room_001',
          isVideo: false,
          peers: const [],
        ),
      );

      await svc.processRoomEvent('room_ended', {'room_id': 'room_001'});
      await Future<void>.delayed(Duration.zero);

      expect(svc.currentState?.status, GroupCallStatus.ended);
    });

    test('ICE candidate from peer is forwarded to correct engine', () async {
      final bobEngine = _StubEngine();
      final svc = _makeService(engines: [bobEngine]);

      svc.seedState(
        GroupCallState(
          status: GroupCallStatus.active,
          roomId: 'room_001',
          isVideo: false,
          peers: const [],
        ),
      );

      // Join bob so the engine exists.
      await svc.processRoomEvent('participant_joined', {
        'room_id': 'room_001',
        'account_id': 'bob',
        'device_id': 'bob_dev1',
        'is_video': false,
      });
      await Future<void>.delayed(Duration.zero);

      await svc.processSignal({
        'type': 'ice',
        'candidate': 'cand_x',
        'mline_index': 0,
        'sdp_mid': '0',
        'sender_device_id': 'bob_dev1',
        'sender_account_id': 'bob',
        'room_id': 'room_001',
      });

      expect(bobEngine.log.any((l) => l.startsWith('ice:')), isTrue);
    });

    test('screen_sharing_changed updates peer participant flag', () async {
      final bobEngine = _StubEngine();
      final svc = _makeService(engines: [bobEngine]);

      svc.seedState(
        GroupCallState(
          status: GroupCallStatus.active,
          roomId: 'room_001',
          isVideo: true,
          peers: const [],
        ),
      );

      await svc.processRoomEvent('participant_joined', {
        'room_id': 'room_001',
        'account_id': 'bob',
        'device_id': 'bob_dev1',
        'is_video': true,
      });
      await Future<void>.delayed(Duration.zero);

      await svc.processRoomEvent('screen_sharing_changed', {
        'room_id': 'room_001',
        'device_id': 'bob_dev1',
        'active': true,
      });

      final bobState = svc.currentState!.peers.firstWhere(
        (p) => p.participant.deviceId == 'bob_dev1',
      );
      expect(bobState.participant.isScreenSharing, isTrue);
    });

    test('leaveRoom disposes all engines', () async {
      final e1 = _StubEngine();
      final e2 = _StubEngine();
      final svc = _makeService(engines: [e1, e2]);

      svc.seedState(
        GroupCallState(
          status: GroupCallStatus.active,
          roomId: 'room_001',
          isVideo: false,
          peers: const [],
        ),
      );

      await svc.processRoomEvent('participant_joined', {
        'room_id': 'room_001',
        'account_id': 'bob',
        'device_id': 'bob_dev1',
        'is_video': false,
      });
      await svc.processRoomEvent('participant_joined', {
        'room_id': 'room_001',
        'account_id': 'carol',
        'device_id': 'carol_dev1',
        'is_video': false,
      });
      await Future<void>.delayed(Duration.zero);

      await svc.leaveRoom();

      expect(e1.disposed, isTrue);
      expect(e2.disposed, isTrue);
      expect(svc.currentState?.status, GroupCallStatus.ended);
    });
  });
}
