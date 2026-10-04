import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/calls/application/platform/call_platform.dart';

/// Where the call's sound goes, and where it can go.
final class CallAudioState {
  const CallAudioState({
    this.route = CallAudioRoute.earpiece,
    this.available = const [],
  });

  final CallAudioRoute route;

  /// The outputs the phone offers right now, in display order. Empty where
  /// there is no choice to make (a desktop): the screen shows no route
  /// control then.
  final List<CallAudioRoute> available;

  bool get canChoose => available.length > 1;

  CallAudioState copyWith({
    CallAudioRoute? route,
    List<CallAudioRoute>? available,
  }) => CallAudioState(
    route: route ?? this.route,
    available: available ?? this.available,
  );
}

/// The audio route of the call in progress.
///
/// A voice call starts on the earpiece and a video call on the speaker, like
/// the phone app; a headset or Bluetooth device that is connected wins over
/// both. When the chosen output disappears (the headset is pulled) the call
/// falls back to the earpiece or the speaker rather than going silent.
final callAudioProvider = NotifierProvider<CallAudioController, CallAudioState>(
  CallAudioController.new,
);

final class CallAudioController extends Notifier<CallAudioState> {
  StreamSubscription<void>? _changes;
  bool _video = false;
  bool _active = false;
  CallAudioRoute? _chosen;

  @override
  CallAudioState build() {
    ref.onDispose(() => _changes?.cancel());
    return const CallAudioState();
  }

  CallAudioPlatform get _platform => ref.read(callAudioPlatformProvider);

  /// The call's media is up: read the outputs, pick the default and start
  /// following changes. Safe to call more than once for one call.
  Future<void> begin({required bool video}) async {
    if (_active || !ref.mounted) return;
    _active = true;
    _video = video;
    _chosen = null;
    await _refresh();
    _changes = _platform.changes.listen((_) => unawaited(_refresh()));
  }

  /// The call is over: forget the choice, so the next call starts fresh.
  void end() {
    // The app can be shutting down while a call ends.
    if (!ref.mounted) return;
    _active = false;
    _chosen = null;
    _changes?.cancel();
    _changes = null;
    state = const CallAudioState();
  }

  /// The person picked [route].
  Future<void> select(CallAudioRoute route) async {
    if (!ref.mounted || !state.available.contains(route)) return;
    _chosen = route;
    state = state.copyWith(route: route);
    await _platform.select(route);
  }

  Future<void> _refresh() async {
    final found = await _platform.available();
    if (!_active || !ref.mounted) return;
    final available = [
      for (final route in CallAudioRoute.values)
        if (found.contains(route)) route,
    ];
    final route = _pick(available);
    final changed = route != state.route;
    state = CallAudioState(route: route, available: available);
    if (available.isNotEmpty && (changed || _chosen == null)) {
      await _platform.select(route);
    }
  }

  CallAudioRoute _pick(List<CallAudioRoute> available) {
    final chosen = _chosen;
    if (chosen != null && available.contains(chosen)) return chosen;
    // A connected headset or Bluetooth device wins over the built-ins.
    if (available.contains(CallAudioRoute.bluetooth)) {
      return CallAudioRoute.bluetooth;
    }
    if (available.contains(CallAudioRoute.wiredHeadset)) {
      return CallAudioRoute.wiredHeadset;
    }
    final builtIn = _video ? CallAudioRoute.speaker : CallAudioRoute.earpiece;
    if (available.contains(builtIn)) return builtIn;
    return available.isEmpty ? CallAudioRoute.earpiece : available.first;
  }
}
