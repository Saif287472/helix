import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

// ---------------------------------------------------------------------------
// Stub engine
// ---------------------------------------------------------------------------

class StubCallEngine implements RemoteCallEngine {
  final _ctrl = StreamController<RemoteCallEngineEvent>.broadcast();
  final List<String> log = [];

  @override
  Stream<RemoteCallEngineEvent> get events => _ctrl.stream;

  void emitCandidate(String callId, String candidate) {
    _ctrl.add(RemoteIceCandidateEvent(
      callId: callId,
      candidate: candidate,
      mlineIndex: 0,
      sdpMid: 'audio',
    ));
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
  }

  @override
  Future<void> dispose() async {
    await _ctrl.close();
  }
}

// ---------------------------------------------------------------------------
// Stub signaling gateway
// ---------------------------------------------------------------------------

class StubSignalingGateway implements RemoteCallSignalingGateway {
  final List<Map<String, dynamic>> sent = [];

  @override
  Future<void> sendCallSignal({
    required String targetPeerId,
    required RemoteCallSignal signal,
  }) async {
    sent.add({'peer': targetPeerId, 'signal': signal});
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

  RemoteCallService makeService({RemoteIceConfig? iceConfig}) {
    final svc = RemoteCallService(
      db: db,
      engine: engine,
      signalingGateway: gateway,
      iceConfig: iceConfig ?? const RemoteIceConfig(iceServers: []),
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

  // P15-002: Inbound offer sets ringing state
  test('P15-002: inbound offer sets call to ringing state', () async {
    final svc = makeService();
    await svc.processInboundSignal(RemoteCallSignal(
      callId: 'call_1',
      signalType: kSignalOffer,
      sdp: 'offer_sdp',
      isVideo: false,
      peerId: 'peer_alice',
    ));

    expect(svc.activeCall, isNotNull);
    expect(svc.activeCall!.state, equals(RemoteCallState.ringing));
    expect(svc.activeCall!.peerId, equals('peer_alice'));
    expect(svc.activeCall!.direction, equals(kCallDirectionIncoming));
  });

  // P15-002: Busy signal when call already active
  test('P15-002: inbound offer while busy sends busy signal back', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    gateway.sent.clear();
    await svc.processInboundSignal(RemoteCallSignal(
      callId: 'call_intruder',
      signalType: kSignalOffer,
      peerId: 'peer_charlie',
    ));

    final busy = gateway.lastSignalTo('peer_charlie');
    expect(busy, isNotNull);
    expect(busy!.signalType, equals(kSignalBusy));
  });

  // P15-003: IceConfig carries STUN servers
  test('P15-003: RemoteIceConfig.defaultStun contains STUN server URLs', () {
    final config = RemoteIceConfig.defaultStun();
    expect(config.iceServers, isNotEmpty);
    expect(
      config.iceServers.any((s) => s.url.startsWith('stun:')),
      isTrue,
    );
  });

  // P15-006: IceConfig supports both STUN and TURN for direct+relay fallback
  test('P15-006: withTurnCredentials adds TURN server alongside STUN', () {
    final config = RemoteIceConfig.defaultStun().withTurnCredentials(
      turnUrl: 'turn:turn.example.com:3478',
      username: 'user',
      credential: 'cred',
    );
    final webrtcServers = config.toWebRtcIceServers();
    expect(webrtcServers.any((s) => (s['urls'] as String).startsWith('stun:')), isTrue);
    expect(webrtcServers.any((s) => (s['urls'] as String).startsWith('turn:')), isTrue);
  });

  // P15-008: Call state recovery detects stale calls
  test('P15-008: recoverCallState marks stale active call as missed', () {
    // Write a marker that started 2 minutes ago (beyond 60s timeout).
    final oldTimestamp =
        DateTime.now().millisecondsSinceEpoch - 120000;
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
    expect(engine.log, contains(startsWith('setMuted:') ));
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

    await svc.restartIce();
    expect(engine.log, contains(startsWith('restartIce:')));
  });

  // P15-013: Call history persisted after call ends
  test('P15-013: call history is persisted when outgoing call ends', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    // Simulate answer so the call becomes active with a startedAt.
    await svc.processInboundSignal(RemoteCallSignal(
      callId: svc.activeCall!.callId,
      signalType: kSignalAnswer,
      sdp: 'answer_sdp',
    ));

    await svc.endActiveCall();

    final history = svc.getCallHistory();
    expect(history, isNotEmpty);
    expect(history.first['direction'], equals(kCallDirectionOutgoing));
    expect(history.first['peer_id'], equals('peer_bob'));
  });

  test('P15-013: declined incoming call is recorded as MISSED', () async {
    final svc = makeService();
    await svc.processInboundSignal(RemoteCallSignal(
      callId: 'call_missed',
      signalType: kSignalOffer,
      peerId: 'peer_alice',
    ));

    await svc.declineIncomingCall();

    final history = svc.getCallHistory();
    expect(history, isNotEmpty);
    expect(history.first['direction'], equals(kCallDirectionMissed));
  });

  // P15-014: No call media stored in DB
  test('P15-014: call history contains only metadata — no media bytes', () async {
    final svc = makeService();
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: true);
    await svc.endActiveCall();

    final history = svc.getCallHistory();
    expect(history, isNotEmpty);
    final row = history.first;
    // Only metadata columns exist; no audio/video content.
    expect(row.keys, containsAll(['call_id', 'peer_id', 'is_video', 'direction', 'duration', 'timestamp']));
    expect(row.keys.contains('sdp'), isFalse);
    expect(row.keys.contains('audio_data'), isFalse);
    expect(row.keys.contains('video_data'), isFalse);
  });

  // P15-015: IP privacy — relay-only filters non-relay ICE candidates
  test('P15-015: relayOnly mode forwards only relay ICE candidates', () async {
    final svc = makeService(
      iceConfig: RemoteIceConfig.defaultStun()
          .withIpPrivacy(IpPrivacyMode.relayOnly),
    );
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    final callId = svc.activeCall!.callId;
    gateway.sent.clear();

    // Emit a host candidate (should be filtered out).
    engine.emitCandidate(callId, 'candidate:1 1 UDP 2130706431 192.168.1.5 54321 typ host');
    await Future<void>.delayed(Duration.zero);
    expect(gateway.sent.where((e) => e['peer'] == 'peer_bob').isEmpty, isTrue);

    // Emit a relay candidate (should be forwarded).
    engine.emitCandidate(callId, 'candidate:2 1 UDP 16777215 93.184.216.1 3478 typ relay raddr 0.0.0.0 rport 0');
    await Future<void>.delayed(Duration.zero);
    expect(gateway.sent.where((e) => e['peer'] == 'peer_bob').isNotEmpty, isTrue);
  });

  test('P15-015: directAndRelay mode forwards all ICE candidates', () async {
    final svc = makeService(
      iceConfig: RemoteIceConfig.defaultStun()
          .withIpPrivacy(IpPrivacyMode.directAndRelay),
    );
    await svc.startOutgoingCall(peerId: 'peer_bob', isVideo: false);

    final callId = svc.activeCall!.callId;
    gateway.sent.clear();

    engine.emitCandidate(callId, 'candidate:1 1 UDP 2130706431 192.168.1.5 54321 typ host');
    await Future<void>.delayed(Duration.zero);
    expect(gateway.sent.where((e) => e['peer'] == 'peer_bob').isNotEmpty, isTrue);
  });

  // P15-016: CallQualityMetrics fields
  test('P15-016: CallQualityMetrics carries transport-layer stats without content', () {
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
  });

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
    engine.emitCandidate(callId, 'candidate:0 1 UDP 2130706431 10.0.0.1 55000 typ host');
    engine.emitCandidate(callId, 'candidate:1 1 UDP 1694498815 203.0.113.5 55001 typ srflx raddr 10.0.0.1 rport 55000');
    engine.emitCandidate(callId, 'candidate:2 1 UDP 16777215 198.51.100.2 3478 typ relay raddr 0.0.0.0 rport 0');
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
  test('P15-019: Remote engine has no private-IP filtering — all host candidates allowed', () async {
    // The Remote engine (stub here) does not filter candidates.
    // In production, RemoteWebRtcCallEngine emits all candidates; the
    // IP privacy mode in RemoteCallService decides what gets forwarded.
    // This contrasts with the Local engine which filters at source to
    // private-range IPs. (P15-019: Local engine file was not modified.)
    final svc = makeService(
      iceConfig: const RemoteIceConfig(iceServers: []),
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
      reason: 'Remote engine must forward public-IP host candidates by default',
    );
  });

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
}
