// The call tests drive the engine's real `CallsService` over an in-memory
// network (the engine's own test double, ported: the original lives in the
// engine's `test/`, which is not importable). `IdFactory` is the one engine
// internal they need.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/core/people/name_lookup.dart';
import 'package:helix_remote/features/calls/application/call_controller.dart';
import 'package:helix_remote/features/calls/application/call_effects.dart';
import 'package:helix_remote/features/calls/application/calls_port.dart';
import 'package:helix_remote/features/calls/application/media/call_media_hub.dart';
import 'package:helix_remote/features/calls/application/media/call_media_providers.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';
import 'package:helix_remote/features/calls/application/platform/notification_call_ringer.dart';
import 'package:helix_remote_crypto/v2.dart' show CryptoRandom;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/util/ids.dart' show IdFactory;
import 'package:helix_remote_engine/testing.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// A clock the test moves; every read advances a millisecond so rows written
/// one after another have distinct times.
final class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 3, 9);

  DateTime now;

  DateTime call() {
    final value = now;
    now = now.add(const Duration(milliseconds: 1));
    return value;
  }

  void advance(Duration d) => now = now.add(d);
}

/// Deterministic bytes (not random): ids only need to differ.
final class CounterRandom implements CryptoRandom {
  CounterRandom(this._seed);

  final int _seed;
  int _n = 0;

  @override
  Uint8List nextBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      _n = (_n * 1103515245 + 12345 + _seed) & 0x7fffffff;
      out[i] = (_n >> 16) & 0xff;
    }
    return out;
  }
}

/// A tiny in-memory stand-in for the server's calls module and the realtime
/// socket between [CallDevice]s: a signal reaches the other device a moment
/// later, an offer for an offline device waits as a pending call, and
/// answering or declining tells the account's other devices to stop ringing.
final class FakeCallNetwork {
  FakeCallNetwork(this.clock);

  final TestClock clock;
  final List<CallDevice> devices = [];

  Future<CallDevice> add(
    String name, {
    String? account,
    bool online = true,
    CallConfig config = const CallConfig(
      ringTimeout: Duration(seconds: 30),
      connectTimeout: Duration(seconds: 30),
      iceBatchDelay: Duration.zero,
      signalTimeout: Duration(seconds: 2),
    ),
  }) async {
    final device = CallDevice._(
      this,
      name,
      account ?? 'account-$name',
      'device-$name',
      online,
      config,
    );
    devices.add(device);
    return device;
  }

  Future<void> dispose() async {
    for (final d in devices) {
      await d.dispose();
    }
  }
}

/// One device: its own database, [CallsService] and fake media.
final class CallDevice implements CallSignaling {
  CallDevice._(
    this.net,
    this.name,
    this.account,
    this.device,
    this.online,
    CallConfig config,
  ) : db = HelixDb.inMemory(key: DatabaseKey.generate()),
      media = FakeCallMediaFactory(label: name) {
    service = CallsService(
      db: db,
      signaling: this,
      clock: net.clock.call,
      ids: IdFactory(net.clock.call, CounterRandom(name.hashCode)),
      selfAccount: () => account,
      postLog: (peer, body) async {},
      emit: (event) {
        if (!events.isClosed) events.add(event);
      },
      config: config,
      mediaFactory: media,
    );
  }

  final FakeCallNetwork net;
  final String name;
  final String account;
  final String device;
  bool online;
  final HelixDb db;
  final FakeCallMediaFactory media;
  late final CallsService service;

  final StreamController<EngineEvent> events =
      StreamController<EngineEvent>.broadcast();

  /// TURN credentials this device is given; null means no relay.
  TurnCredentials? turn;

  final Map<String, (PendingCall, CallSignalPayload)> _pending = {};

  /// The port the app code under test uses.
  CallsPort get port => EngineCallsPort(service, events.stream);

  Future<void> dispose() async {
    await service.release();
    await service.close();
    await events.close();
    await db.close();
  }

  Iterable<CallDevice> _devicesOf(String account) =>
      net.devices.where((d) => d.account == account);

  @override
  Future<TurnCredentials?> turnCredentials() async => turn;

  @override
  Future<CallSignalResponse> send(
    String callId,
    CallSignalPayload payload, {
    required String account,
    Set<String>? devices,
    Duration ttl = const Duration(seconds: 60),
  }) async {
    final delivered = <String>[];
    final pending = <String>[];
    for (final target in _devicesOf(account)) {
      if (devices != null && !devices.contains(target.device)) continue;
      if (target.online) {
        delivered.add(target.device);
        unawaited(
          Future<void>(
            () => target.service.onSignal(this.account, device, payload),
          ),
        );
      } else if (payload.type == CallSignalType.offer) {
        pending.add(target.device);
        target._pending[callId] = (
          PendingCall(
            callId: callId,
            from: EnvelopeSender(account: this.account, device: device),
            createdAt: net.clock.now,
            expiresAt: net.clock.now.add(ttl),
            payload: Uint8List(0),
          ),
          payload,
        );
      }
    }
    return CallSignalResponse(delivered: delivered, pending: pending);
  }

  @override
  Future<void> setState(String callId, CallState state) async {
    for (final d in _devicesOf(account)) {
      d._pending.remove(callId);
      if (d.device == device || !d.online) continue;
      unawaited(Future<void>(() => d.service.onEndedElsewhere(callId, state)));
    }
  }

  @override
  Future<List<PendingCall>> pending() async => [
    for (final (call, _) in _pending.values)
      if (call.expiresAt.isAfter(net.clock.now)) call,
  ];

  @override
  Future<CallSignalPayload?> open(PendingCall call) async =>
      _pending[call.callId]?.$2;

  CallSnapshot? get current => service.current;

  /// Waits (real time) until [check] holds.
  Future<void> until(
    bool Function() check, {
    String? reason,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!check()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting: ${reason ?? 'condition'} on $name');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> untilPhase(CallPhase phase) =>
      until(() => current?.phase == phase, reason: 'phase ${phase.name}');
}

// ---------------------------------------------------------------- platform

final class FakeCallPermissions implements CallPermissions {
  FakeCallPermissions([this.result = CallPermissionResult.granted]);

  CallPermissionResult result;
  final List<bool> asked = [];

  @override
  Future<CallPermissionResult> ensure({required bool video}) async {
    asked.add(video);
    return result;
  }
}

final class FakeCallPlatform implements CallPlatform {
  final List<String> log = [];
  bool fullScreen = true;

  @override
  Future<void> setCallActive({
    required bool active,
    required bool keepScreenOn,
  }) async => log.add('active:$active keepOn:$keepScreenOn');

  @override
  Future<bool> shouldUseFullScreenIncomingCall() async => fullScreen;

  @override
  Future<void> startForegroundService({
    required String callId,
    required String callerName,
    required bool video,
  }) async => log.add('service:start $callerName video:$video');

  @override
  Future<void> stopForegroundService() async => log.add('service:stop');

  @override
  Future<void> setProximityScreenOff(bool enabled) async =>
      log.add('proximity:$enabled');
}

final class FakeRinger implements CallRinger {
  final List<String> log = [];

  @override
  Future<void> startIncoming({
    required String callId,
    required String callerName,
    required bool video,
    required bool fullScreen,
  }) async => log.add('ring $callerName video:$video full:$fullScreen');

  @override
  Future<void> stop(String callId) async => log.add('stop');
}

final class FakeAudioPlatform implements CallAudioPlatform {
  FakeAudioPlatform([Set<CallAudioRoute>? available])
    : available_ =
          available ?? {CallAudioRoute.earpiece, CallAudioRoute.speaker};

  Set<CallAudioRoute> available_;
  final List<CallAudioRoute> selected = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Future<Set<CallAudioRoute>> available() async => available_;

  @override
  Future<void> select(CallAudioRoute route) async => selected.add(route);

  @override
  Stream<void> get changes => _changes.stream;

  /// A headset appears or goes.
  void change(Set<CallAudioRoute> next) {
    available_ = next;
    _changes.add(null);
  }
}

/// A surface that draws a labelled box.
final class FakeSurface implements CallVideoSurface {
  FakeSurface(this.label, {bool frames = true}) : _frames = frames;

  final String label;
  bool _frames;
  final ChangeNotifier _notifier = ChangeNotifier();

  @override
  Listenable get changes => _notifier;

  @override
  bool get hasFrames => _frames;

  set frames(bool value) {
    _frames = value;
    _notifier.notifyListeners();
  }

  @override
  Widget build({bool mirror = false}) =>
      SizedBox.expand(child: Text('video:$label${mirror ? ':mirror' : ''}'));
}

/// The overrides that take a call off the platform and the runtime.
List<Override> callOverrides({
  required CallsPort port,
  FakeCallPermissions? permissions,
  FakeCallPlatform? platform,
  FakeRinger? ringer,
  FakeAudioPlatform? audio,
  CallMediaHub? hub,
  PeopleNames names = PeopleNames.empty,
  Duration linger = const Duration(milliseconds: 50),
  DateTime Function()? clock,
  Stream<CallNotificationResponse>? responses,
}) => [
  callsPortProvider.overrideWith((ref) async => port),
  callPermissionsProvider.overrideWithValue(
    permissions ?? FakeCallPermissions(),
  ),
  callPlatformProvider.overrideWithValue(platform ?? FakeCallPlatform()),
  callRingerProvider.overrideWithValue(ringer ?? FakeRinger()),
  callAudioPlatformProvider.overrideWithValue(audio ?? FakeAudioPlatform()),
  callMediaHubProvider.overrideWithValue(hub ?? CallMediaHub()),
  peopleNamesProvider.overrideWith((ref) => Stream.value(names)),
  callEndedLingerProvider.overrideWithValue(linger),
  callNotificationResponsesProvider.overrideWithValue(
    responses ?? const Stream.empty(),
  ),
  callLaunchResponseProvider.overrideWithValue(Future.value(null)),
  ?(clock == null ? null : callClockProvider.overrideWithValue(clock)),
];

/// A [CallsPort] the test drives by hand: it records what the UI asked for and
/// emits whatever snapshots and log rows the test says.
class FakeCallsPort implements CallsPort {
  final StreamController<CallSnapshot?> _current =
      StreamController<CallSnapshot?>.broadcast();
  final StreamController<List<CallLogRow>> _log =
      StreamController<List<CallLogRow>>.broadcast();
  final StreamController<MissedCallEvent> _missed =
      StreamController<MissedCallEvent>.broadcast();
  CallSnapshot? _snapshot;
  List<CallLogRow> _rows = const [];

  final List<String> calls = [];

  /// Makes the log stream fail.
  Object? logError;

  /// Make the next action throw this.
  Object? failWith;

  /// What `startCall` returns for the peer.
  CallSnapshot Function(String peer, bool video)? onStart;

  void emit(CallSnapshot? snapshot) {
    _snapshot = snapshot;
    _current.add(snapshot);
  }

  void setLog(List<CallLogRow> rows) {
    _rows = rows;
    _log.add(rows);
  }

  void missed(MissedCallEvent event) => _missed.add(event);

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }

  @override
  CallSnapshot? get current => _snapshot;

  @override
  Stream<CallSnapshot?> watchCurrent() async* {
    yield _snapshot;
    yield* _current.stream;
  }

  @override
  Stream<IncomingCallEvent> get incomingCalls => const Stream.empty();

  @override
  Stream<MissedCallEvent> get missedCalls => _missed.stream;

  @override
  Future<CallSnapshot> startCall(String peer, {required bool video}) async {
    calls.add('start $peer video:$video');
    _maybeFail();
    final snapshot =
        onStart?.call(peer, video) ??
        CallSnapshot(
          callId: 'call-1',
          peer: peer,
          direction: CallDirection.outgoing,
          video: video,
          phase: CallPhase.calling,
          startedAt: DateTime.utc(2026, 10, 3, 9),
        );
    emit(snapshot);
    return snapshot;
  }

  @override
  Future<void> accept() async {
    calls.add('accept');
    _maybeFail();
  }

  @override
  Future<void> decline() async {
    calls.add('decline');
    _maybeFail();
  }

  @override
  Future<void> hangUp() async {
    calls.add('hangUp');
    _maybeFail();
  }

  @override
  Future<void> setMuted({required bool muted}) async {
    calls.add('mute:$muted');
    _maybeFail();
  }

  @override
  Future<void> setCameraEnabled({required bool enabled}) async {
    calls.add('camera:$enabled');
    _maybeFail();
  }

  @override
  Future<int> fetchPending() async => 0;

  @override
  Stream<List<CallLogRow>> watchLog({int limit = 50}) async* {
    if (logError != null) throw logError!;
    yield _rows;
    yield* _log.stream;
  }

  @override
  Future<void> forget(String callId) async {
    calls.add('forget $callId');
    _rows = [
      for (final row in _rows)
        if (row.callId != callId) row,
    ];
    _log.add(_rows);
  }
}

/// A call log row.
CallLogRow logRow(
  String id, {
  String peer = 'peer-1',
  String direction = 'outgoing',
  String state = 'ended',
  bool video = false,
  required DateTime at,
  int? answeredAfterSeconds,
  int? talkSeconds,
  String? name,
}) => CallLogRow(
  callId: id,
  peerAccountId: peer,
  peerDisplayName: name,
  kind: 'direct',
  direction: direction,
  video: video,
  state: state,
  startedAt: at,
  answeredAt: answeredAfterSeconds == null
      ? null
      : at.add(Duration(seconds: answeredAfterSeconds)),
  endedAt: talkSeconds == null
      ? null
      : at.add(Duration(seconds: (answeredAfterSeconds ?? 0) + talkSeconds)),
);

/// A snapshot of a call.
CallSnapshot snapshot({
  String id = 'call-1',
  String peer = 'peer-1',
  CallDirection direction = CallDirection.outgoing,
  bool video = false,
  CallPhase phase = CallPhase.calling,
  CallEnd? end,
  DateTime? answeredAt,
  DateTime? endedAt,
  bool muted = false,
  bool cameraOn = false,
}) => CallSnapshot(
  callId: id,
  peer: peer,
  direction: direction,
  video: video,
  phase: phase,
  startedAt: DateTime.utc(2026, 10, 3, 9),
  answeredAt: answeredAt,
  endedAt: endedAt,
  end: end,
  muted: muted,
  cameraOn: cameraOn,
);
