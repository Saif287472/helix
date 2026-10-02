import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/util/ids.dart' show IdFactory;
import 'package:helix_remote_engine/testing.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'peers.dart';

/// An in-memory stand-in for the server's `calls` module and the realtime
/// socket, between [CallDevice]s: signals reach online devices a moment
/// later (like a network hop), offers for offline devices wait as pending
/// calls, `end` clears them, a blocker's callers are dropped silently and
/// `setState` stops the account's other devices ringing, as the real server
/// does. Signals are not sealed here (the sealing is covered by the
/// end-to-end tests); everything else is the state machine's own.
final class FakeCallNetwork {
  FakeCallNetwork(this.clock);

  final TestClock clock;
  final List<CallDevice> devices = [];

  /// `(blocker, blocked)` account pairs.
  final Set<(String, String)> blocks = {};

  /// Every signal sent, in order: `(from device, to device, payload)`.
  final List<(String, String, CallSignalPayload)> log = [];

  /// Signals of one type that went to [device].
  List<CallSignalPayload> received(CallDevice device, CallSignalType type) => [
    for (final (_, to, p) in log)
      if (to == device.device && p.type == type) p,
  ];

  int _seed = 0;

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
    bool media = true,
  }) async {
    final device = CallDevice._(
      this,
      name,
      account ?? 'account-$name',
      'device-$name',
      online,
      config,
      SeededRandom('call-$name${_seed++}'),
      media,
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

/// One device with its own database, [CallsService] and fake media.
final class CallDevice implements CallSignaling {
  CallDevice._(
    this.net,
    this.name,
    this.account,
    this.device,
    this.online,
    CallConfig config,
    SeededRandom random,
    bool withMedia,
  ) : db = HelixDb.inMemory(key: DatabaseKey.generate()),
      media = withMedia ? FakeCallMediaFactory(label: name) : null {
    service = CallsService(
      db: db,
      signaling: this,
      clock: net.clock.call,
      ids: IdFactory(net.clock.call, random),
      selfAccount: () => account,
      postLog: (peer, body) async => posted.add((peer, body)),
      emit: events.add,
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
  final FakeCallMediaFactory? media;
  late final CallsService service;

  /// What the service emitted (`IncomingCallEvent`, `MissedCallEvent`).
  final List<EngineEvent> events = [];

  /// What the service posted to the chat (`call_log` messages).
  final List<(String, CallLogBody)> posted = [];

  /// Every state the UI stream showed, in order (nulls included).
  final List<CallSnapshot?> shown = [];
  StreamSubscription<CallSnapshot?>? _watch;

  /// TURN credentials this device is given; null means no relay.
  TurnCredentials? turn;

  /// Make the next [send] calls throw.
  Object? failSends;

  /// Calls to [setState], as `(call id, state)`.
  final List<(String, CallState)> stateCalls = [];

  /// The offers kept for this device while it is offline.
  final Map<String, (PendingCall, CallSignalPayload)> _pending = {};

  void startWatching() {
    _watch = service.watchCurrent().listen(shown.add);
  }

  Future<void> dispose() async {
    await _watch?.cancel();
    await service.release();
    await service.close();
    await db.close();
  }

  Iterable<CallDevice> _devicesOf(String account) =>
      net.devices.where((d) => d.account == account);

  // ------------------------------------------------------- CallSignaling

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
    final failure = failSends;
    if (failure != null) throw failure;
    final targets = [
      for (final d in _devicesOf(account))
        if (devices == null || devices.contains(d.device)) d,
    ];
    final blocked = net.blocks.contains((account, this.account));
    final delivered = <String>[];
    final pending = <String>[];
    for (final target in targets) {
      net.log.add((device, target.device, payload));
      if (blocked) continue; // Dropped silently, as the server does.
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
    if (payload.type == CallSignalType.end) {
      // The server clears the offers the sender is in.
      for (final d in net.devices) {
        d._pending.removeWhere(
          (id, p) =>
              id == callId &&
              (p.$1.from.account == this.account || d.account == this.account),
        );
      }
    }
    return CallSignalResponse(delivered: delivered, pending: pending);
  }

  @override
  Future<void> setState(String callId, CallState state) async {
    stateCalls.add((callId, state));
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

  // ------------------------------------------------------------- helpers

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

  Future<CallLogRow?> logRow(String callId) => db.callsDao.byId(callId);

  /// Waits for the log row of [callId] to reach [state].
  Future<CallLogRow> untilLogged(String callId, String state) async {
    CallLogRow? row;
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      row = await logRow(callId);
      if (row?.state == state) return row!;
      if (DateTime.now().isAfter(deadline)) {
        fail('$name: log of $callId is ${row?.state}, wanted $state');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}
