import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/features/calls/application/media/call_media_providers.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show CallLogRow;
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// The engine's call service as the call screens use it.
///
/// An interface so everything above it - the call state the screen draws, the
/// log, the effects - runs in widget tests against a fake or against the
/// engine's own `CallsService` over its in-memory network, with no runtime.
abstract interface class CallsPort {
  /// The call in progress, or null.
  CallSnapshot? get current;

  /// The current call and every change to it: first the call as it is (or
  /// null), then a snapshot per change; a finished call arrives as an
  /// [CallPhase.ended] snapshot and then as null.
  Stream<CallSnapshot?> watchCurrent();

  /// A call is ringing on this device.
  Stream<IncomingCallEvent> get incomingCalls;

  /// A call rang here and nobody answered it.
  Stream<MissedCallEvent> get missedCalls;

  Future<CallSnapshot> startCall(String peer, {required bool video});
  Future<void> accept();
  Future<void> decline();
  Future<void> hangUp();
  Future<void> setMuted({required bool muted});
  Future<void> setCameraEnabled({required bool enabled});

  /// Opens the offers that waited for this device on the server and rings the
  /// newest. Run after a call push woke the app.
  Future<int> fetchPending();

  /// The call log, newest first (live).
  Stream<List<CallLogRow>> watchLog({int limit});

  /// Removes one entry from the log.
  Future<void> forget(String callId);
}

/// [CallsPort] over the engine's [CallsService].
final class EngineCallsPort implements CallsPort {
  EngineCallsPort(this._calls, Stream<EngineEvent> events)
    : incomingCalls = events.whereType<IncomingCallEvent>(),
      missedCalls = events.whereType<MissedCallEvent>();

  final CallsService _calls;

  @override
  final Stream<IncomingCallEvent> incomingCalls;

  @override
  final Stream<MissedCallEvent> missedCalls;

  @override
  CallSnapshot? get current => _calls.current;

  @override
  Stream<CallSnapshot?> watchCurrent() => _calls.watchCurrent();

  @override
  Future<CallSnapshot> startCall(String peer, {required bool video}) =>
      _calls.startCall(peer, video: video);

  @override
  Future<void> accept() => _calls.accept();

  @override
  Future<void> decline() => _calls.decline();

  @override
  Future<void> hangUp() => _calls.hangUp();

  @override
  Future<void> setMuted({required bool muted}) => _calls.setMuted(muted: muted);

  @override
  Future<void> setCameraEnabled({required bool enabled}) =>
      _calls.setCameraEnabled(enabled: enabled);

  @override
  Future<int> fetchPending() => _calls.fetchPending();

  @override
  Stream<List<CallLogRow>> watchLog({int limit = 50}) =>
      _calls.watchLog(limit: limit);

  @override
  Future<void> forget(String callId) => _calls.forget(callId);
}

extension on Stream<EngineEvent> {
  Stream<T> whereType<T extends EngineEvent>() =>
      where((event) => event is T).cast<T>();
}

/// The live call service, with this app's media attached.
///
/// Reading this is what gives the engine its `CallMediaFactory`: without one a
/// call cannot be placed or answered, so everything that touches a call goes
/// through here (the call host reads it as soon as the runtime is up, so an
/// offer that rings at start-up can be answered).
final callsPortProvider = FutureProvider<CallsPort>((ref) async {
  final runtime = await ref.watch(runtimeProvider.future);
  runtime.engine.calls.mediaFactory = ref.watch(callMediaFactoryProvider);
  return EngineCallsPort(runtime.engine.calls, runtime.engine.events);
});

/// The call in progress as the engine reports it, with a short hold on a call
/// that just ended so the screen can say how it ended before it goes.
///
/// The engine delivers `ended` and then null straight away; held for
/// [callEndedLingerProvider] here so "Answered on another device" and "No
/// answer" are readable. A new call during the hold replaces it at once, and a
/// call that lost a glare (both called at once) is held only briefly: its
/// replacement is the same conversation continuing.
final currentCallProvider = StreamProvider<CallSnapshot?>((ref) {
  final linger = ref.watch(callEndedLingerProvider);
  final out = StreamController<CallSnapshot?>();
  StreamSubscription<CallSnapshot?>? sub;
  Timer? hold;
  var closed = false;

  void emit(CallSnapshot? value) {
    if (!out.isClosed) out.add(value);
  }

  void listen(CallsPort port) {
    sub = port.watchCurrent().listen((snapshot) {
      if (snapshot == null) {
        // Null follows `ended`: keep showing the ended call for the hold.
        if (hold != null) return;
        emit(null);
        return;
      }
      hold?.cancel();
      hold = null;
      emit(snapshot);
      if (snapshot.phase == CallPhase.ended) {
        // A call that lost a glare is replaced by the winner at once; a
        // short hold covers the gap without showing a second screen.
        final wait = snapshot.end == CallEnd.glare
            ? const Duration(milliseconds: 400)
            : linger;
        hold = Timer(wait, () {
          hold = null;
          emit(null);
        });
      }
    }, onError: out.addError);
  }

  ref.onDispose(() {
    closed = true;
    hold?.cancel();
    sub?.cancel();
    out.close();
  });

  ref.watch(callsPortProvider.future).then((port) {
    if (!closed) listen(port);
  }, onError: out.addError);
  return out.stream;
});

/// How long an ended call stays on screen.
final callEndedLingerProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 2200),
);
