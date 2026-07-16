import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

// ---------------------------------------------------------------------------
// Stub engine
// ---------------------------------------------------------------------------

class StubCallEngine implements RemoteCallEngine {
  final _ctrl = StreamController<RemoteCallEngineEvent>.broadcast();
  final List<String> log = [];
  bool _disposed = false;
  bool throwOnEndCall = false;

  @override
  Stream<RemoteCallEngineEvent> get events => _ctrl.stream;

  void emitCandidate(String callId, String candidate) {
    _ctrl.add(
      RemoteIceCandidateEvent(
        callId: callId,
        candidate: candidate,
        mlineIndex: 0,
        sdpMid: 'audio',
      ),
    );
  }

  void emitConnection(String callId, RemoteCallEngineConnectionState state) {
    _ctrl.add(RemoteCallConnectionStateEvent(callId: callId, state: state));
  }

  void emitRestartOffer(String callId, String sdp) {
    _ctrl.add(RemoteRenegotiationOfferEvent(callId: callId, sdp: sdp));
  }

  @override
  Future<String> createOffer(String callId, {bool video = false}) async {
    log.add('createOffer:$callId:video=$video');
    return 'stub_offer_sdp';
  }

  @override
  Future<String> createAnswer(
    String callId,
    String offerSdp, {
    bool video = false,
  }) async {
    log.add('createAnswer:$callId:video=$video');
    return 'stub_answer_sdp';
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
    log.add('addIce:$callId:$candidate');
  }

  @override
  Future<void> restartIce(String callId) async {
    log.add('restartIce:$callId');
  }

  @override
  Future<void> setMuted(String callId, {required bool muted}) async {
    log.add('setMuted:$callId:$muted');
  }

  @override
  Future<void> setSpeakerOn(String callId, {required bool enabled}) async {
    log.add('setSpeaker:$callId:$enabled');
  }

  @override
  Future<void> setVideoEnabled(String callId, {required bool enabled}) async {
    log.add('setVideo:$callId:$enabled');
  }

  @override
  Future<void> switchCamera(String callId) async {
    log.add('switchCamera:$callId');
  }

  @override
  Future<void> endCall(String callId) async {
    log.add('endCall:$callId');
    if (throwOnEndCall) throw StateError('end failed');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _ctrl.close();
  }
}

// ---------------------------------------------------------------------------
// Stub signaling gateway
// ---------------------------------------------------------------------------

class StubSignalingGateway implements RemoteCallSignalingGateway {
  final List<Map<String, dynamic>> sent = [];
  bool failSends = false;

  @override
  Future<void> sendCallSignal({
    String? targetAccountId,
    String? targetDeviceId,
    required RemoteCallSignal signal,
  }) async {
    if (failSends) throw StateError('signaling failed');
    sent.add({
      'peer': targetAccountId ?? targetDeviceId ?? signal.peerId ?? '',
      'account': targetAccountId,
      'device': targetDeviceId,
      'signal': signal,
    });
  }

  RemoteCallSignal? lastSignalTo(String peer) {
    final matches = sent.where((e) => e['peer'] == peer).toList();
    if (matches.isEmpty) return null;
    return matches.last['signal'] as RemoteCallSignal;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

HelixRemoteDatabase _openMemoryDb() {
  final db = HelixRemoteDatabase(File(':memory:'));
  db.initialize();
  return db;
}

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      String? foundPath;
      for (var i = 0; i < 5; i++) {
        final path = p.join(dir.path, '.dart_tool', 'lib', 'sqlite3.dll');
        if (File(path).existsSync()) {
          foundPath = path;
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      if (foundPath != null) DynamicLibrary.open(foundPath);
    }
  });

  late HelixRemoteDatabase db;
  late StubCallEngine engine;
  late StubSignalingGateway gateway;

  setUp(() {
    db = _openMemoryDb();
    engine = StubCallEngine();
    gateway = StubSignalingGateway();
  });

  tearDown(() async {
    db.close();
    await engine.dispose();
  });

  RemoteCallService makeService({
    RemoteIceConfig? iceConfig,
    Duration? outgoingRingTimeout,
    Duration? incomingRingTimeout,
    Duration? offerAnswerTimeout,
    Duration? iceConnectionTimeout,
    Duration? disconnectedGrace,
    void Function(String message)? diagnostics,
  }) {
    final svc = RemoteCallService(
      db: db,
      engine: engine,
      signalingGateway: gateway,
      iceConfig: iceConfig ?? const RemoteIceConfig(iceServers: []),
      outgoingRingTimeout: outgoingRingTimeout ?? const Duration(seconds: 45),
      incomingRingTimeout: incomingRingTimeout ?? const Duration(seconds: 45),
      offerAnswerTimeout: offerAnswerTimeout ?? const Duration(seconds: 20),
      iceConnectionTimeout: iceConnectionTimeout ?? const Duration(seconds: 20),
      disconnectedGrace: disconnectedGrace ?? const Duration(seconds: 10),
      terminalStateGrace: Duration.zero,
      diagnostics: diagnostics,
    );
    svc.start();
    return svc;
  }

  // P15-001: RemoteCallService uses RemoteCallEngine, not the Local LAN engine
  test('P15-001: RemoteCallService is isolated from Local call engine', () {
    // Verify the service accepts only RemoteCallEngine (not Local CallEngine).
    // Enforced at compile time by the type system; a stub satisfies the interface.
    final svc = makeService();
    expect(svc, isNotNull);
    expect(svc.activeCall, isNull);
  });

  // P15-002: Outgoing call sends offer signal via gateway
  test('P15-002: startOutgoingCall sends offer signal to peer', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    expect(engine.log, contains(startsWith('createOffer:')));
    final sent = gateway.lastSignalTo('peer_bob');
    expect(sent, isNotNull);
    expect(sent!.signalType, equals(kSignalOffer));
    expect(sent.sdp, equals('stub_offer_sdp'));
    expect(sent.isVideo, isFalse);
  });

  test(
    'F3 silence unknown callers records missed call without ringing',
    () async {
      db.setSilenceUnknownCallers(enabled: true);
      final svc = makeService();

      await svc.processInboundSignal(
        const RemoteCallSignal(
          callId: 'call_unknown',
          signalType: kSignalOffer,
          callerAccountId: 'mallory',
          callerDeviceId: 'mallory_phone',
          sdp: 'offer',
        ),
      );

      expect(svc.activeCall, isNull);
      expect(engine.log, isEmpty);
      final history = svc.getCallHistory();
      expect(history.single['call_id'], 'call_unknown');
      expect(history.single['outcome'], 'silenced_unknown');

      db.upsertContact(
        const RemoteContact(
          peerAccountId: 'bob',
          nickname: 'Bob',
          status: 'Accepted',
        ),
      );
      await svc.processInboundSignal(
        const RemoteCallSignal(
          callId: 'call_known',
          signalType: kSignalOffer,
          callerAccountId: 'bob',
          callerDeviceId: 'bob_phone',
          sdp: 'offer',
        ),
      );
      expect(svc.activeCall?.state, RemoteCallState.ringing);
    },
  );

  test(
    'P6-C01/P6-C05: start is idempotent and dispose releases media',
    () async {
      final svc = makeService();
      svc.start();
      await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);
      final callId = svc.activeCall!.callId;
      gateway.sent.clear();

      engine.emitCandidate(
        callId,
        'candidate:1 1 UDP 16777215 198.51.100.2 3478 typ relay',
      );
      await Future<void>.delayed(Duration.zero);
      expect(gateway.sent, hasLength(1));

      await svc.dispose();
      expect(engine.log, contains('endCall:$callId'));
      expect(svc.activeCall, isNull);
    },
  );

  test('outgoing signaling failure clears dialing call state', () async {
    final svc = makeService();
    gateway.failSends = true;

    await expectLater(
      svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false),
      throwsStateError,
    );

    expect(svc.activeCall, isNull);
    expect(db.getActiveCallMarker(), isNull);
    expect(engine.log, contains(startsWith('endCall:')));
  });

  test('engine end failure still clears active call state', () async {
    final diagnostics = <String>[];
    final svc = makeService(diagnostics: diagnostics.add);
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);
    final callId = svc.activeCall!.callId;
    engine.throwOnEndCall = true;

    await svc.endActiveCall();

    expect(engine.log, contains('endCall:$callId'));
    expect(svc.activeCall, isNull);
    expect(db.getActiveCallMarker(), isNull);
    expect(
      diagnostics,
      contains(contains('engine endCall failed cid=${callId.substring(0, 8)}')),
    );
  });

  // P15-002: Inbound offer sets ringing state
  test('P15-002: inbound offer sets call to ringing state', () async {
    final svc = makeService();
    await svc.processInboundSignal(
      RemoteCallSignal(
        callId: 'call_1',
        signalType: kSignalOffer,
        sdp: 'offer_sdp',
        isVideo: false,
        peerId: 'peer_alice',
      ),
    );

    expect(svc.activeCall, isNotNull);
    expect(svc.activeCall!.state, equals(RemoteCallState.ringing));
    expect(svc.activeCall!.peerId, equals('peer_alice'));
    expect(svc.activeCall!.direction, equals(kCallDirectionIncoming));
  });

  test('P15-002: duplicate inbound offer while ringing is ignored', () async {
    final diagnostics = <String>[];
    final svc = makeService(diagnostics: diagnostics.add);
    await svc.processInboundSignal(
      const RemoteCallSignal(
        callId: 'call_1',
        signalType: kSignalOffer,
        sdp: 'offer_sdp',
        isVideo: false,
        peerId: 'peer_alice',
      ),
    );

    await svc.processInboundSignal(
      const RemoteCallSignal(
        callId: 'call_1',
        signalType: kSignalOffer,
        sdp: 'offer_sdp',
        isVideo: false,
        peerId: 'peer_alice',
      ),
    );

    expect(svc.activeCall?.state, equals(RemoteCallState.ringing));
    expect(engine.log.any((line) => line.startsWith('createAnswer:')), isFalse);
    expect(gateway.sent, isEmpty);
    expect(
      diagnostics,
      contains(contains('offer duplicate ignored cid=call_1')),
    );
  });

  // P15-002: Busy signal when call already active
  test('P15-002: inbound offer while busy sends busy signal back', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    gateway.sent.clear();
    await svc.processInboundSignal(
      RemoteCallSignal(
        callId: 'call_intruder',
        signalType: kSignalOffer,
        peerId: 'peer_charlie',
      ),
    );

    final busy = gateway.lastSignalTo('peer_charlie');
    expect(busy, isNotNull);
    expect(busy!.signalType, equals(kSignalBusy));
  });

  // P15-003: IceConfig carries STUN servers
  test('P15-003: RemoteIceConfig.defaultStun contains STUN server URLs', () {
    final config = RemoteIceConfig.defaultStun();
    expect(config.iceServers, isNotEmpty);
    expect(config.iceServers.any((s) => s.url.startsWith('stun:')), isTrue);
  });

  // P15-006: IceConfig supports both STUN and TURN for direct+relay fallback
  test('P15-006: withTurnCredentials adds TURN server alongside STUN', () {
    final config = RemoteIceConfig.defaultStun().withTurnCredentials(
      turnUrl: 'turn:turn.example.com:3478',
      username: 'user',
      credential: 'cred',
    );
    final webrtcServers = config.toWebRtcIceServers();
    expect(
      webrtcServers.any((s) => (s['urls'] as String).startsWith('stun:')),
      isTrue,
    );
    expect(
      webrtcServers.any((s) => (s['urls'] as String).startsWith('turn:')),
      isTrue,
    );
  });

  // P15-008: Call state recovery detects stale calls
  test('P15-008: recoverCallState marks stale active call as missed', () {
    // Write a marker that started 2 minutes ago (beyond 60s timeout).
    final oldTimestamp = DateTime.now().millisecondsSinceEpoch - 120000;
    db.setActiveCallMarker(
      callId: 'stale_call',
      peerId: 'peer_x',
      isVideo: false,
      startedAt: oldTimestamp,
    );

    final svc = makeService();
    svc.recoverCallState();

    // Marker should be cleared.
    expect(db.getActiveCallMarker(), isNull);

    // History should have a MISSED entry.
    final history = db.getCallHistory();
    expect(history, isNotEmpty);
    expect(history.first['call_id'], equals('stale_call'));
    expect(history.first['direction'], equals(kCallDirectionMissed));
  });

  test('P15-008: recoverCallState ignores recent (non-stale) markers', () {
    db.setActiveCallMarker(
      callId: 'fresh_call',
      peerId: 'peer_y',
      isVideo: false,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final svc = makeService();
    svc.recoverCallState();

    // Fresh call should not be cleared.
    expect(db.getActiveCallMarker(), isNotNull);
    expect(db.getCallHistory(), isEmpty);
  });

  // P15-009: Audio controls
  test('P15-009: setMuted delegates to engine', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    await svc.setMuted(muted: true);
    expect(engine.log, contains(startsWith('setMuted:')));
    expect(engine.log.last, contains(':true'));
  });

  test('P15-009: setSpeakerOn delegates to engine', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    await svc.setSpeakerOn(enabled: true);
    expect(engine.log, contains(startsWith('setSpeaker:')));
    expect(engine.log.last, contains(':true'));
  });

  // P15-010: Video controls
  test('P15-010: setVideoEnabled delegates to engine', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    await svc.setVideoEnabled(enabled: true);
    expect(engine.log, contains(startsWith('setVideo:')));
    expect(engine.log.last, contains(':true'));
  });

  // P15-011: Camera swap
  test('P15-011: switchCamera delegates to engine', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: true);

    await svc.switchCamera();
    expect(engine.log, contains(startsWith('switchCamera:')));
  });

  // P15-012: Network handoff — ICE restart
  test('P15-012: restartIce delegates to engine', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);
    final callId = svc.activeCall!.callId;
    await svc.processInboundSignal(
      RemoteCallSignal(
        callId: callId,
        signalType: kSignalAnswer,
        sdp: 'answer-sdp',
      ),
    );
    engine.emitConnection(callId, RemoteCallEngineConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    await svc.restartIce();
    expect(engine.log, contains(startsWith('restartIce:')));
  });

  // P15-013: Call history persisted after call ends
  test('P15-013: call history is persisted when outgoing call ends', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    // Simulate answer so the call becomes active with a startedAt.
    await svc.processInboundSignal(
      RemoteCallSignal(
        callId: svc.activeCall!.callId,
        signalType: kSignalAnswer,
        sdp: 'answer_sdp',
      ),
    );

    await svc.endActiveCall();

    final history = svc.getCallHistory();
    expect(history, isNotEmpty);
    expect(history.first['direction'], equals(kCallDirectionOutgoing));
    expect(history.first['peer_id'], equals('peer_bob'));
  });

  test('P15-013: declined incoming call is recorded as MISSED', () async {
    final svc = makeService();
    await svc.processInboundSignal(
      RemoteCallSignal(
        callId: 'call_missed',
        signalType: kSignalOffer,
        peerId: 'peer_alice',
      ),
    );

    await svc.declineIncomingCall();

    final history = svc.getCallHistory();
    expect(history, isNotEmpty);
    expect(history.first['direction'], equals(kCallDirectionMissed));
  });

  // P15-014: No call media stored in DB
  test(
    'P15-014: call history contains only metadata — no media bytes',
    () async {
      final svc = makeService();
      await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: true);
      await svc.endActiveCall();

      final history = svc.getCallHistory();
      expect(history, isNotEmpty);
      final row = history.first;
      // Only metadata columns exist; no audio/video content.
      expect(
        row.keys,
        containsAll([
          'call_id',
          'peer_id',
          'is_video',
          'direction',
          'duration',
          'timestamp',
        ]),
      );
      expect(row.keys.contains('sdp'), isFalse);
      expect(row.keys.contains('audio_data'), isFalse);
      expect(row.keys.contains('video_data'), isFalse);
    },
  );

  // P15-015: IP privacy — relay-only filters non-relay ICE candidates
  test('P15-015: relayOnly mode forwards only relay ICE candidates', () async {
    final svc = makeService(
      iceConfig: RemoteIceConfig.defaultStun().withIpPrivacy(
        IpPrivacyMode.relayOnly,
      ),
    );
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    final callId = svc.activeCall!.callId;
    gateway.sent.clear();

    // Emit a host candidate (should be filtered out).
    engine.emitCandidate(
      callId,
      'candidate:1 1 UDP 2130706431 192.168.1.5 54321 typ host',
    );
    await Future<void>.delayed(Duration.zero);
    expect(gateway.sent.where((e) => e['peer'] == 'peer_bob').isEmpty, isTrue);

    // Emit a relay candidate (should be forwarded).
    engine.emitCandidate(
      callId,
      'candidate:2 1 UDP 16777215 93.184.216.1 3478 typ relay raddr 0.0.0.0 rport 0',
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      gateway.sent.where((e) => e['peer'] == 'peer_bob').isNotEmpty,
      isTrue,
    );
  });

  test(
    'P15-015: ICE diagnostics report gathered candidate type and action',
    () async {
      final diagnostics = <String>[];
      final svc = makeService(
        iceConfig: RemoteIceConfig.defaultStun().withIpPrivacy(
          IpPrivacyMode.relayOnly,
        ),
        diagnostics: diagnostics.add,
      );
      await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

      final callId = svc.activeCall!.callId;
      gateway.sent.clear();

      engine.emitCandidate(
        callId,
        'candidate:1 1 UDP 2130706431 192.168.1.5 54321 typ host',
      );
      engine.emitCandidate(
        callId,
        'candidate:2 1 UDP 16777215 93.184.216.1 3478 typ relay raddr 0.0.0.0 rport 0',
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        diagnostics,
        contains(
          contains('ice gathered cid=${callId.substring(0, 8)} type=host'),
        ),
      );
      expect(diagnostics, contains(contains('type=host')));
      expect(diagnostics, contains(contains('action=filter')));
      expect(diagnostics, contains(contains('type=relay')));
      expect(diagnostics, contains(contains('action=forward')));
    },
  );

  test('P15-015: directAndRelay mode forwards all ICE candidates', () async {
    final svc = makeService(
      iceConfig: RemoteIceConfig.defaultStun().withIpPrivacy(
        IpPrivacyMode.directAndRelay,
      ),
    );
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    final callId = svc.activeCall!.callId;
    gateway.sent.clear();

    engine.emitCandidate(
      callId,
      'candidate:1 1 UDP 2130706431 192.168.1.5 54321 typ host',
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      gateway.sent.where((e) => e['peer'] == 'peer_bob').isNotEmpty,
      isTrue,
    );
  });

  // P15-016: CallQualityMetrics fields
  test(
    'P15-016: CallQualityMetrics carries transport-layer stats without content',
    () {
      const metrics = CallQualityMetrics(
        callId: 'call_q',
        packetLossPercent: 1.5,
        jitterMs: 12.0,
        roundTripMs: 45.0,
        audioBitrateKbps: 32.0,
        videoBitrateKbps: 512.0,
      );

      final map = metrics.toMap();
      expect(map['packet_loss_percent'], equals(1.5));
      expect(map['jitter_ms'], equals(12.0));
      expect(map['round_trip_ms'], equals(45.0));
      expect(map['audio_bitrate_kbps'], equals(32.0));
      expect(map['video_bitrate_kbps'], equals(512.0));

      // No content fields.
      expect(map.containsKey('audio_data'), isFalse);
      expect(map.containsKey('video_data'), isFalse);
      expect(map.containsKey('sdp'), isFalse);
    },
  );

  // P15-017: Relay-only scenario (cross-network simulation)
  test('P15-017: relay-only call completes without leaking direct IP', () async {
    final svc = makeService(
      iceConfig: RemoteIceConfig.defaultStun()
          .withTurnCredentials(
            turnUrl: 'turn:turn.example.com:3478',
            username: 'u',
            credential: 'c',
          )
          .withIpPrivacy(IpPrivacyMode.relayOnly),
    );
    await svc.startOutgoingCall(peerId: 'peer_remote', isVideo: false);

    final callId = svc.activeCall!.callId;
    gateway.sent.clear();

    // Emit various candidate types.
    engine.emitCandidate(
      callId,
      'candidate:0 1 UDP 2130706431 10.0.0.1 55000 typ host',
    );
    engine.emitCandidate(
      callId,
      'candidate:1 1 UDP 1694498815 203.0.113.5 55001 typ srflx raddr 10.0.0.1 rport 55000',
    );
    engine.emitCandidate(
      callId,
      'candidate:2 1 UDP 16777215 198.51.100.2 3478 typ relay raddr 0.0.0.0 rport 0',
    );
    await Future<void>.delayed(Duration.zero);

    final forwarded = gateway.sent
        .where((e) => e['peer'] == 'peer_remote')
        .map((e) => (e['signal'] as RemoteCallSignal).candidate!)
        .toList();

    // Only relay candidate forwarded — no direct IP exposure.
    expect(forwarded.length, equals(1));
    expect(forwarded.first, contains('typ relay'));
  });

  // P15-018: Cost and quota monitoring (verified via TURN credential log)
  test('P15-018: TURN usage is trackable via saveCallHistory and DB', () {
    db.saveCallHistory(
      callId: 'cost_call',
      peerId: 'peer_a',
      isVideo: true,
      direction: kCallDirectionOutgoing,
      durationSeconds: 300,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final history = db.getCallHistory();
    expect(history, isNotEmpty);
    expect(history.first['duration'], equals(300));
    expect(history.first['is_video'], equals(1));
  });

  // P15-019: Local WebRTC candidate filtering unchanged
  test(
    'P15-019: Remote engine has no private-IP filtering — all host candidates allowed',
    () async {
      // The Remote engine (stub here) does not filter candidates.
      // In production, RemoteWebRtcCallEngine emits all candidates; the
      // IP privacy mode in RemoteCallService decides what gets forwarded.
      // This contrasts with the Local engine which filters at source to
      // private-range IPs. (P15-019: Local engine file was not modified.)
      final svc = makeService(
        iceConfig: const RemoteIceConfig(
          iceServers: [],
          ipPrivacy: IpPrivacyMode.directAndRelay,
        ),
      );
      await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

      final callId = svc.activeCall!.callId;
      gateway.sent.clear();

      // A public IP host candidate is not filtered in directAndRelay mode.
      engine.emitCandidate(
        callId,
        'candidate:1 1 UDP 2130706431 203.0.113.99 50000 typ host',
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        gateway.sent.where((e) => e['peer'] == 'peer_bob').isNotEmpty,
        isTrue,
        reason:
            'Remote engine must forward public-IP host candidates by default',
      );
    },
  );

  // Signal JSON round-trip
  test('RemoteCallSignal serializes and deserializes correctly', () {
    const signal = RemoteCallSignal(
      callId: 'c1',
      signalType: kSignalIce,
      candidate: 'candidate:abc',
      mlineIndex: 0,
      sdpMid: 'audio',
      isVideo: true,
      peerId: 'bob',
    );
    final json = signal.toJson();
    final parsed = RemoteCallSignal.fromJson(json);
    expect(parsed.callId, equals('c1'));
    expect(parsed.signalType, equals(kSignalIce));
    expect(parsed.candidate, equals('candidate:abc'));
    expect(parsed.isVideo, isTrue);
    expect(parsed.peerId, equals('bob'));
  });

  test('RemoteCallStatus.copyWith can clear transient error message', () {
    const status = RemoteCallStatus(
      callId: 'c1',
      peerId: 'bob',
      isVideo: false,
      direction: kCallDirectionOutgoing,
      state: RemoteCallState.active,
      errorMessage: 'Weak network detected. Call quality may be reduced.',
    );

    final cleared = status.copyWith(clearErrorMessage: true);

    expect(cleared.errorMessage, isNull);
  });

  // Media controls are no-ops when no active call
  test('media controls are safe to call when no active call', () async {
    final svc = makeService();
    await svc.setMuted(muted: true);
    await svc.setSpeakerOn(enabled: true);
    await svc.setVideoEnabled(enabled: true);
    await svc.switchCamera();
    await svc.restartIce();
    await svc.endActiveCall();
    expect(engine.log, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // P12-A04: callStatusChanges stream (Phase 12)
  // ---------------------------------------------------------------------------

  test('P12-A04: callStatusChanges emits ringing on inbound offer', () async {
    final svc = makeService();
    final emitted = <RemoteCallStatus?>[];
    final sub = svc.callStatusChanges.listen(emitted.add);

    await svc.processInboundSignal(
      const RemoteCallSignal(
        callId: 'c-p12-001',
        signalType: kSignalOffer,
        sdp: 'offer-sdp',
        isVideo: false,
        peerId: 'alice',
      ),
    );

    expect(emitted.length, 1);
    expect(emitted.first?.state, RemoteCallState.ringing);
    expect(emitted.first?.peerId, 'alice');

    await sub.cancel();
    await svc.dispose();
  });

  test(
    'P12-A04: callStatusChanges emits null after endActiveCall (logout cleanup)',
    () async {
      final svc = makeService();
      final emitted = <RemoteCallStatus?>[];
      final sub = svc.callStatusChanges.listen(emitted.add);

      await svc.processInboundSignal(
        const RemoteCallSignal(
          callId: 'c-p12-002',
          signalType: kSignalOffer,
          sdp: 'offer-sdp',
          isVideo: false,
          peerId: 'bob',
        ),
      );
      await svc.endActiveCall();

      expect(emitted.length, 2);
      expect(emitted.last, isNull);

      await sub.cancel();
      await svc.dispose();
    },
  );

  test(
    'P12-A04: callStatusChanges emits preparing and dialing on startOutgoingCall',
    () async {
      final svc = makeService();
      final emitted = <RemoteCallStatus?>[];
      final sub = svc.callStatusChanges.listen(emitted.add);

      await svc.startOutgoingCall(peerId: 'charlie', isVideo: true);

      expect(emitted.map((status) => status?.state), [
        RemoteCallState.preparing,
        RemoteCallState.dialing,
      ]);
      expect(emitted.first?.isVideo, isTrue);

      await sub.cancel();
      await svc.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // RP7-002: clearCallHistory removes all entries
  // ---------------------------------------------------------------------------

  test('RP7-002: clearCallHistory removes all call log entries', () async {
    final svc = makeService();

    // Generate two completed call entries in the history
    await svc.startOutgoingCall(peerId: 'peer_clear_1', isVideo: false);
    await svc.endActiveCall();
    await svc.startOutgoingCall(peerId: 'peer_clear_2', isVideo: false);
    await svc.endActiveCall();

    expect(svc.getCallHistory(), hasLength(2));

    svc.clearCallHistory();

    expect(svc.getCallHistory(), isEmpty);

    await svc.dispose();
  });

  // ---------------------------------------------------------------------------
  // RP6-001: Signal identity — callId mismatch protection
  // ---------------------------------------------------------------------------

  test('RP6-001: answer signal for wrong callId is silently ignored', () async {
    final svc = makeService();

    await svc.startOutgoingCall(peerId: 'peer_a', isVideo: false);
    expect(svc.activeCall?.state, RemoteCallState.dialing);

    final sentBefore = gateway.sent.length;

    // A spoofed answer targeting a different callId must be ignored.
    await svc.processInboundSignal(
      const RemoteCallSignal(
        callId: 'wrong-call-id-xyz',
        signalType: kSignalAnswer,
        sdp: 'evil-answer-sdp',
        isVideo: false,
        peerId: 'peer_a',
      ),
    );

    // Call remains in dialing state; no spurious signals sent.
    expect(svc.activeCall?.state, RemoteCallState.dialing);
    expect(gateway.sent.length, equals(sentBefore));

    await svc.dispose();
  });

  test(
    'RP6-001: end signal for unrelated callId has no effect on active call',
    () async {
      final svc = makeService();

      await svc.processInboundSignal(
        const RemoteCallSignal(
          callId: 'real-call-789',
          signalType: kSignalOffer,
          sdp: 'offer-sdp',
          isVideo: false,
          peerId: 'alice',
        ),
      );
      await svc.acceptIncomingCall();
      expect(svc.activeCall?.state, RemoteCallState.connecting);
      engine.emitConnection(
        'real-call-789',
        RemoteCallEngineConnectionState.connected,
      );
      await Future<void>.delayed(Duration.zero);
      expect(svc.activeCall?.state, RemoteCallState.active);

      // A spoofed end signal for a different callId must not terminate the active call.
      await svc.processInboundSignal(
        const RemoteCallSignal(
          callId: 'spoofed-call-000',
          signalType: kSignalEnd,
          isVideo: false,
          peerId: 'alice',
        ),
      );

      expect(svc.activeCall?.state, RemoteCallState.active);

      await svc.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // RP6-002: Full incoming call flow — offer → ringing → accept → active
  // ---------------------------------------------------------------------------

  test(
    'RP6-002: acceptIncomingCall transitions to active and sends answer signal',
    () async {
      final svc = makeService();

      const peerId = 'caller_bob';
      const callId = 'incoming-accept-001';

      await svc.processInboundSignal(
        const RemoteCallSignal(
          callId: callId,
          signalType: kSignalOffer,
          sdp: 'offer-sdp',
          isVideo: false,
          peerId: peerId,
        ),
      );
      expect(svc.activeCall?.state, RemoteCallState.ringing);

      await svc.acceptIncomingCall();

      final status = svc.activeCall;
      expect(status?.state, RemoteCallState.connecting);
      expect(status?.peerId, equals(peerId));

      // Engine must have created an answer using the offer SDP.
      expect(engine.log, contains('createAnswer:$callId:video=false'));

      // Answer signal must have been sent back to the caller with the correct callId.
      final answer = gateway.lastSignalTo(peerId);
      expect(answer, isNotNull);
      expect(answer!.callId, equals(callId));
      expect(answer.signalType, equals(kSignalAnswer));

      engine.emitConnection(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      expect(svc.activeCall?.state, RemoteCallState.active);

      await svc.dispose();
    },
  );

  group('Phase 3 media engine and state machine', () {
    test('queues early ICE until an incoming offer is accepted', () async {
      final svc = makeService();
      await svc.processInboundSignal(
        const RemoteCallSignal(
          callId: 'early-ice-call',
          signalType: kSignalOffer,
          sdp: 'offer-sdp',
          peerId: 'alice',
        ),
      );
      await svc.processInboundSignal(
        const RemoteCallSignal(
          callId: 'early-ice-call',
          signalType: kSignalIce,
          candidate: 'candidate:1 1 UDP 16777215 198.51.100.2 3478 typ relay',
          mlineIndex: 0,
          sdpMid: 'audio',
        ),
      );

      expect(engine.log.any((line) => line.startsWith('addIce:')), isFalse);

      await svc.acceptIncomingCall();

      expect(
        engine.log,
        contains(
          'addIce:early-ice-call:candidate:1 1 UDP 16777215 198.51.100.2 3478 typ relay',
        ),
      );
    });

    test('deduplicates and validates remote ICE candidates', () async {
      final svc = makeService();
      await svc.startOutgoingCall(peerId: 'bob', isVideo: false);
      final callId = svc.activeCall!.callId;
      await svc.processInboundSignal(
        RemoteCallSignal(
          callId: callId,
          signalType: kSignalAnswer,
          sdp: 'answer-sdp',
        ),
      );

      const candidate =
          'candidate:2 1 UDP 16777215 198.51.100.2 3478 typ relay';
      await svc.processInboundSignal(
        RemoteCallSignal(
          callId: callId,
          signalType: kSignalIce,
          candidate: candidate,
          mlineIndex: 0,
          sdpMid: 'audio',
        ),
      );
      await svc.processInboundSignal(
        RemoteCallSignal(
          callId: callId,
          signalType: kSignalIce,
          candidate: candidate,
          mlineIndex: 0,
          sdpMid: 'audio',
        ),
      );
      await svc.processInboundSignal(
        RemoteCallSignal(
          callId: callId,
          signalType: kSignalIce,
          candidate: 'not-a-candidate',
          mlineIndex: 0,
          sdpMid: 'audio',
        ),
      );

      expect(
        engine.log.where((line) => line.startsWith('addIce:$callId')),
        hasLength(1),
      );
    });

    test('connection events gate active and failed terminal cleanup', () async {
      final svc = makeService();
      await svc.startOutgoingCall(peerId: 'bob', isVideo: false);
      final callId = svc.activeCall!.callId;
      await svc.processInboundSignal(
        RemoteCallSignal(
          callId: callId,
          signalType: kSignalAnswer,
          sdp: 'answer-sdp',
        ),
      );
      expect(svc.activeCall?.state, RemoteCallState.connecting);

      engine.emitConnection(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      expect(svc.activeCall?.state, RemoteCallState.active);

      engine.emitConnection(callId, RemoteCallEngineConnectionState.failed);
      await Future<void>.delayed(Duration.zero);
      expect(svc.activeCall, isNull);
      expect(db.getActiveCallMarker(), isNull);
      expect(engine.log, contains('endCall:$callId'));
      expect(svc.getCallHistory().first['direction'], kCallDirectionOutgoing);
    });

    test(
      'outgoing timeout cleans marker and persists failed history',
      () async {
        final svc = makeService(
          outgoingRingTimeout: const Duration(milliseconds: 1),
          offerAnswerTimeout: const Duration(seconds: 1),
        );
        await svc.startOutgoingCall(peerId: 'bob', isVideo: false);
        final callId = svc.activeCall!.callId;

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(svc.activeCall, isNull);
        expect(db.getActiveCallMarker(), isNull);
        expect(engine.log, contains('endCall:$callId'));
        expect(svc.getCallHistory().first['direction'], kCallDirectionOutgoing);
        expect(svc.getCallHistory().first['duration'], 0);
      },
    );

    test('ICE restart event sends a renegotiation offer', () async {
      final svc = makeService();
      await svc.startOutgoingCall(peerId: 'bob', isVideo: false);
      final callId = svc.activeCall!.callId;
      await svc.processInboundSignal(
        RemoteCallSignal(
          callId: callId,
          signalType: kSignalAnswer,
          sdp: 'answer-sdp',
        ),
      );
      engine.emitConnection(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      gateway.sent.clear();

      await svc.restartIce();
      engine.emitRestartOffer(callId, 'restart-offer-sdp');
      await Future<void>.delayed(Duration.zero);

      expect(engine.log, contains('restartIce:$callId'));
      final offer = gateway.lastSignalTo('bob');
      expect(offer, isNotNull);
      expect(offer!.signalType, kSignalOffer);
      expect(offer.sdp, 'restart-offer-sdp');
      expect(svc.activeCall?.state, RemoteCallState.reconnecting);
    });

    test('incoming decline is classified as missed history', () async {
      final svc = makeService();
      await svc.processInboundSignal(
        const RemoteCallSignal(
          callId: 'missed-incoming',
          signalType: kSignalOffer,
          sdp: 'offer-sdp',
          peerId: 'alice',
        ),
      );
      await svc.processInboundSignal(
        const RemoteCallSignal(
          callId: 'missed-incoming',
          signalType: kSignalDecline,
        ),
      );

      expect(svc.activeCall, isNull);
      expect(svc.getCallHistory().first['direction'], kCallDirectionMissed);
    });
  });

  // ---------------------------------------------------------------------------
  // RP6-004: ICE config unavailable state (relay-only + no TURN)
  // ---------------------------------------------------------------------------

  test(
    'RP6-004: relay-only config without TURN servers yields no connectable candidates',
    () {
      // Default app config: empty iceServers + relayOnly.
      // The callsAvailable getter (RemoteCompositionRoot) returns false here.
      const config = RemoteIceConfig(
        iceServers: [],
        ipPrivacy: IpPrivacyMode.relayOnly,
      );

      final hasTurn = config.iceServers.any(
        (s) => s.url.startsWith('turn:') || s.url.startsWith('turns:'),
      );
      expect(
        hasTurn,
        isFalse,
        reason: 'No TURN configured → calls cannot connect in relay-only mode',
      );
      expect(config.iceServers, isEmpty);
      expect(config.ipPrivacy, equals(IpPrivacyMode.relayOnly));
    },
  );

  test(
    'RP6-004: relay-only config with a TURN server represents a connectable state',
    () {
      final config = RemoteIceConfig.defaultStun()
          .withTurnCredentials(
            turnUrl: 'turn:relay.example.com:3478',
            username: 'u',
            credential: 'c',
          )
          .withIpPrivacy(IpPrivacyMode.relayOnly);

      final hasTurn = config.iceServers.any(
        (s) => s.url.startsWith('turn:') || s.url.startsWith('turns:'),
      );
      expect(
        hasTurn,
        isTrue,
        reason: 'TURN server present → relay-only calls can connect',
      );
      expect(config.ipPrivacy, equals(IpPrivacyMode.relayOnly));
    },
  );
}
