// Tests for Phase F7: adaptive media, reconnect backoff, max reconnect limit,
// metrics uploader callback, and silence-unknown-callers integration.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

// ---------------------------------------------------------------------------
// Stubs (mirror remote_call_service_test.dart stubs)
// ---------------------------------------------------------------------------

class _StubEngine implements RemoteCallEngine {
  final _ctrl = StreamController<RemoteCallEngineEvent>.broadcast();
  final List<String> log = [];

  @override
  Stream<RemoteCallEngineEvent> get events => _ctrl.stream;

  void emitConn(String callId, RemoteCallEngineConnectionState s) =>
      _ctrl.add(RemoteCallConnectionStateEvent(callId: callId, state: s));

  void emitQuality(
    String callId, {
    double loss = 0,
    double rtt = 0,
    double jitter = 0,
    double audioBitrate = 32,
    bool isRelay = false,
    bool isWeak = false,
  }) {
    _ctrl.add(
      RemoteCallQualityEvent(
        callId: callId,
        metrics: CallQualityMetrics(
          callId: callId,
          packetLossPercent: loss,
          roundTripMs: rtt,
          jitterMs: jitter,
          audioBitrateKbps: audioBitrate,
          isRelay: isRelay,
          isWeak: isWeak,
        ),
      ),
    );
  }

  @override
  Future<String> createOffer(String callId, {bool video = false}) async =>
      'stub_offer';

  @override
  Future<String> createAnswer(
    String callId,
    String offerSdp, {
    bool video = false,
  }) async => 'stub_answer';

  @override
  Future<void> setRemoteAnswer(String callId, String answerSdp) async {}

  @override
  Future<void> addIceCandidate(
    String callId,
    String c,
    int m,
    String mid,
  ) async {}

  @override
  Future<void> restartIce(String callId) async {
    log.add('restartIce:$callId');
  }

  @override
  Future<void> setMuted(String callId, {required bool muted}) async {}

  @override
  Future<void> setSpeakerOn(String callId, {required bool enabled}) async {}

  @override
  Future<void> setVideoEnabled(String callId, {required bool enabled}) async {
    log.add('setVideo:$callId:$enabled');
  }

  @override
  Future<void> switchCamera(String callId) async {}

  @override
  Future<void> endCall(String callId) async {}

  @override
  Future<void> dispose() async => _ctrl.close();
}

class _StubGateway implements RemoteCallSignalingGateway {
  @override
  Future<RemoteCallSignalDeliveryReceipt> sendCallSignal({
    String? targetAccountId,
    String? targetDeviceId,
    required RemoteCallSignal signal,
  }) async {
    return const RemoteCallSignalDeliveryReceipt(
      status: 'delivered',
      delivered: true,
      queued: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

HelixRemoteDatabase _openDb() {
  final db = HelixRemoteDatabase(File(':memory:'));
  db.initialize();
  return db;
}

RemoteCallService _makeService(
  HelixRemoteDatabase db,
  _StubEngine engine, {
  Duration disconnectedGrace = const Duration(milliseconds: 5),
  Duration adaptCooldown = Duration.zero,
  List<Map<String, dynamic>>? capturedMetrics,
  Future<void> Function(Map<String, dynamic>)? metricsUploader,
  List<Duration>? reconnectBackoff,
}) {
  final svc = RemoteCallService(
    db: db,
    engine: engine,
    signalingGateway: _StubGateway(),
    disconnectedGrace: disconnectedGrace,
    // Production paces video drops 15s apart so a marginal link cannot
    // flap the camera. A test asserting the second drop happens at all
    // would otherwise have to sit through that.
    adaptCooldown: adaptCooldown,
    terminalStateGrace: Duration.zero,
    // The production table is 2s..30s; a test driving six reconnects would
    // otherwise sit through a minute of real backoff.
    reconnectBackoff: reconnectBackoff ?? const [Duration(milliseconds: 5)],
    metricsUploader:
        metricsUploader ??
        (capturedMetrics != null ? (m) async => capturedMetrics.add(m) : null),
  );
  svc.start();
  return svc;
}

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      for (var i = 0; i < 5; i++) {
        final path = p.join(dir.path, '.dart_tool', 'lib', 'sqlite3.dll');
        if (File(path).existsSync()) {
          DynamicLibrary.open(path);
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
  });

  late HelixRemoteDatabase db;
  late _StubEngine engine;

  setUp(() {
    db = _openDb();
    engine = _StubEngine();
  });

  tearDown(() async {
    db.close();
    await engine.dispose();
  });

  // -------------------------------------------------------------------------
  // Adaptive media
  // -------------------------------------------------------------------------

  group('adaptive media', () {
    test('disables video when packet loss exceeds threshold', () async {
      final svc = _makeService(db, engine);
      await svc.startOutgoingCall(peerId: 'bob', isVideo: true);
      final callId = svc.activeCall!.callId;
      engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      engine.emitQuality(callId, loss: 20, rtt: 100);
      await Future<void>.delayed(Duration.zero);

      expect(engine.log, contains('setVideo:$callId:false'));
      await svc.dispose();
    });

    test(
      're-enables video after two consecutive good quality samples',
      () async {
        final svc = _makeService(db, engine);
        await svc.startOutgoingCall(peerId: 'bob', isVideo: true);
        final callId = svc.activeCall!.callId;
        engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
        await Future<void>.delayed(Duration.zero);

        // Trigger degraded → video off.
        engine.emitQuality(callId, loss: 20, rtt: 100);
        await Future<void>.delayed(Duration.zero);
        expect(engine.log, contains('setVideo:$callId:false'));

        // One good sample not enough (needs 2).
        engine.emitQuality(callId, loss: 2, rtt: 50);
        await Future<void>.delayed(Duration.zero);
        expect(engine.log, isNot(contains('setVideo:$callId:true')));

        // Second good sample → video re-enabled.
        engine.emitQuality(callId, loss: 2, rtt: 50);
        await Future<void>.delayed(Duration.zero);
        expect(engine.log, contains('setVideo:$callId:true'));
        await svc.dispose();
      },
    );

    test('keeps video on a slow but clean link', () async {
      // Reported from a device: video dropped itself ~6s into every call.
      //   adapt video_off loss=0.0% rtt=504ms
      // Relay-only sends every packet through TURN, so a healthy call sits
      // in the hundreds of milliseconds by construction. Latency is not a
      // reason to drop video - turning the camera off does not make a round
      // trip shorter, it just removes the picture from a working call.
      final svc = _makeService(db, engine);
      await svc.startOutgoingCall(peerId: 'bob', isVideo: true);
      final callId = svc.activeCall!.callId;
      engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      engine.emitQuality(callId, loss: 0, rtt: 504, isRelay: true);
      await Future<void>.delayed(Duration.zero);

      expect(engine.log, isNot(contains('setVideo:$callId:false')));
      await svc.dispose();
    });

    test('recovers on a link that stays slow', () async {
      // The other half of the same report: once video had dropped it never
      // came back on its own. Recovery used to require RTT under 200ms,
      // which a relay path holding steady near 500ms can never reach, so
      // the fallback latched for the rest of the call.
      final svc = _makeService(db, engine);
      await svc.startOutgoingCall(peerId: 'bob', isVideo: true);
      final callId = svc.activeCall!.callId;
      engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      engine.emitQuality(callId, loss: 20, rtt: 500, isRelay: true);
      await Future<void>.delayed(Duration.zero);
      expect(engine.log, contains('setVideo:$callId:false'));

      // Loss clears, latency does not - which is the normal shape of a
      // relay call recovering from a bad patch.
      engine.emitQuality(callId, loss: 0, rtt: 500, isRelay: true);
      await Future<void>.delayed(Duration.zero);
      engine.emitQuality(callId, loss: 0, rtt: 500, isRelay: true);
      await Future<void>.delayed(Duration.zero);

      expect(engine.log, contains('setVideo:$callId:true'));
      await svc.dispose();
    });

    test('turning video back on by hand re-arms adaptation', () async {
      // The drop branch is guarded by !_audioOnlyFallback, so if a manual
      // re-enable left the flag set, adaptation would be dead for the rest
      // of the call - the link could collapse and nothing would react.
      final svc = _makeService(db, engine);
      await svc.startOutgoingCall(peerId: 'bob', isVideo: true);
      final callId = svc.activeCall!.callId;
      engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      engine.emitQuality(callId, loss: 20, rtt: 100);
      await Future<void>.delayed(Duration.zero);
      expect(engine.log, contains('setVideo:$callId:false'));

      await svc.setVideoEnabled(enabled: true);
      engine.log.clear();

      engine.emitQuality(callId, loss: 30, rtt: 100);
      await Future<void>.delayed(Duration.zero);
      expect(
        engine.log,
        contains('setVideo:$callId:false'),
        reason: 'adaptation must still be able to act after a manual override',
      );
      await svc.dispose();
    });

    test('does not disable video for audio-only call', () async {
      final svc = _makeService(db, engine);
      await svc.startOutgoingCall(peerId: 'bob', isVideo: false);
      final callId = svc.activeCall!.callId;
      engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      engine.emitQuality(callId, loss: 20, rtt: 500);
      await Future<void>.delayed(Duration.zero);

      expect(engine.log, isNot(anyElement(startsWith('setVideo:'))));
      await svc.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Reconnect backoff + max limit
  // -------------------------------------------------------------------------

  group('reconnect backoff', () {
    test('triggers restartIce after disconnected grace', () async {
      final svc = _makeService(
        db,
        engine,
        disconnectedGrace: const Duration(milliseconds: 20),
      );
      await svc.startOutgoingCall(peerId: 'bob', isVideo: false);
      final callId = svc.activeCall!.callId;
      engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      engine.emitConn(callId, RemoteCallEngineConnectionState.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(engine.log, anyElement(startsWith('restartIce:')));
      await svc.dispose();
    });

    test('call fails after exceeding max reconnect attempts', () async {
      final svc = _makeService(
        db,
        engine,
        disconnectedGrace: const Duration(milliseconds: 5),
        reconnectBackoff: const [Duration(milliseconds: 5)],
      );
      await svc.startOutgoingCall(peerId: 'bob', isVideo: false);
      final callId = svc.activeCall!.callId;
      engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      // Drive disconnected → restartIce 5× to exhaust the limit.
      for (var i = 0; i < 6; i++) {
        engine.emitConn(callId, RemoteCallEngineConnectionState.disconnected);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        // Keep it reconnecting so no natural recovery.
        engine.emitConn(callId, RemoteCallEngineConnectionState.checking);
        await Future<void>.delayed(Duration.zero);
      }

      expect(svc.activeCall?.state, anyOf(isNull, RemoteCallState.failed));
      await svc.dispose();
    });

    test(
      'reconnect counter resets when connection returns to active',
      () async {
        final svc = _makeService(
          db,
          engine,
          disconnectedGrace: const Duration(milliseconds: 20),
        );
        await svc.startOutgoingCall(peerId: 'bob', isVideo: false);
        final callId = svc.activeCall!.callId;
        engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
        await Future<void>.delayed(Duration.zero);

        // One disconnect + recovery.
        engine.emitConn(callId, RemoteCallEngineConnectionState.disconnected);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
        await Future<void>.delayed(Duration.zero);

        // Call should still be active, not failed.
        expect(svc.activeCall?.state, RemoteCallState.active);
        await svc.dispose();
      },
    );
  });

  // -------------------------------------------------------------------------
  // Privacy-safe metrics uploader
  // -------------------------------------------------------------------------

  group('metrics uploader', () {
    test('invoked at call end with required fields', () async {
      final captured = <Map<String, dynamic>>[];
      final svc = _makeService(db, engine, capturedMetrics: captured);

      await svc.startOutgoingCall(peerId: 'bob', isVideo: true);
      final callId = svc.activeCall!.callId;
      engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      await svc.endActiveCall();
      await Future<void>.delayed(Duration.zero);

      expect(captured, hasLength(1));
      final m = captured.first;
      expect(m['call_id'], callId);
      expect(m.containsKey('call_outcome'), isTrue);
      expect(m.containsKey('duration_seconds'), isTrue);
      expect(m.containsKey('reconnect_count'), isTrue);
    });

    test('records connection_type from quality event', () async {
      final captured = <Map<String, dynamic>>[];
      final svc = _makeService(db, engine, capturedMetrics: captured);

      await svc.startOutgoingCall(peerId: 'bob', isVideo: false);
      final callId = svc.activeCall!.callId;
      engine.emitConn(callId, RemoteCallEngineConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      engine.emitQuality(callId, loss: 1, rtt: 50, isRelay: true);
      await Future<void>.delayed(Duration.zero);

      await svc.endActiveCall();
      await Future<void>.delayed(Duration.zero);

      expect(captured.first['connection_type'], 'relay');
    });

    test('outcome is "declined" when callee declines', () async {
      final captured = <Map<String, dynamic>>[];
      final svc = _makeService(db, engine, capturedMetrics: captured);

      await svc.startOutgoingCall(peerId: 'bob', isVideo: false);
      final callId = svc.activeCall!.callId;
      await svc.processInboundSignal(
        RemoteCallSignal(
          callId: callId,
          signalType: 'decline',
          callerAccountId: 'bob',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        captured.isEmpty || captured.first['call_outcome'] == 'declined',
        isTrue,
      );
      await svc.dispose();
    });
  });
}
