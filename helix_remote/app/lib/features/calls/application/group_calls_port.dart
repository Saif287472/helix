import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/features/calls/application/calls_port.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// What the app asks of the engine's group calls (ADR-034); an interface so
/// tests drive a room by hand.
abstract interface class GroupCallsPort {
  GroupCallSnapshot? get current;

  /// The room, then every change, then the ended room and null.
  Stream<GroupCallSnapshot?> watchCurrent();

  Future<GroupCallSnapshot> start(
    String group, {
    required List<String> invite,
    required bool video,
  });
  Future<void> accept();
  Future<void> decline();
  Future<void> hangUp();
  Future<void> setMuted({required bool muted});
  Future<void> setCameraEnabled({required bool enabled});
}

/// [GroupCallsPort] over the engine's [GroupCallsService].
final class EngineGroupCallsPort implements GroupCallsPort {
  const EngineGroupCallsPort(this._rooms);

  final GroupCallsService _rooms;

  @override
  GroupCallSnapshot? get current => _rooms.current;

  @override
  Stream<GroupCallSnapshot?> watchCurrent() => _rooms.watchCurrent();

  @override
  Future<GroupCallSnapshot> start(
    String group, {
    required List<String> invite,
    required bool video,
  }) => _rooms.start(group, invite: invite, video: video);

  @override
  Future<void> accept() => _rooms.accept();

  @override
  Future<void> decline() => _rooms.decline();

  @override
  Future<void> hangUp() => _rooms.hangUp();

  @override
  Future<void> setMuted({required bool muted}) => _rooms.setMuted(muted: muted);

  @override
  Future<void> setCameraEnabled({required bool enabled}) =>
      _rooms.setCameraEnabled(enabled: enabled);
}

/// The live group-call service. Reading the 1:1 port first gives the engine
/// its media factory, which rooms use too.
final groupCallsPortProvider = FutureProvider<GroupCallsPort>((ref) async {
  await ref.watch(callsPortProvider.future);
  final runtime = await ref.watch(runtimeProvider.future);
  return EngineGroupCallsPort(runtime.engine.groupCalls);
});

/// The room as the engine reports it, with a short hold on one that just
/// ended so the screen can say how it ended.
final currentGroupCallProvider = StreamProvider<GroupCallSnapshot?>((ref) {
  final linger = ref.watch(callEndedLingerProvider);
  final out = StreamController<GroupCallSnapshot?>();
  StreamSubscription<GroupCallSnapshot?>? sub;
  Timer? hold;
  var closed = false;

  void emit(GroupCallSnapshot? value) {
    if (!out.isClosed) out.add(value);
  }

  void listen(GroupCallsPort port) {
    sub = port.watchCurrent().listen((snapshot) {
      if (snapshot == null) {
        if (hold != null) return;
        emit(null);
        return;
      }
      hold?.cancel();
      hold = null;
      emit(snapshot);
      if (snapshot.phase == GroupCallPhase.ended) {
        hold = Timer(linger, () {
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

  ref.watch(groupCallsPortProvider.future).then((port) {
    if (!closed) listen(port);
  }, onError: out.addError);
  return out.stream;
});
