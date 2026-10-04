import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show CallMediaState;

/// One side's video, as the call screen draws it.
///
/// An interface so `presentation/` never meets the WebRTC renderer type: the
/// screen asks a surface to [build] itself and listens to [changes]. Tests
/// plug in a coloured box.
abstract interface class CallVideoSurface {
  /// Fires when frames start or stop arriving.
  Listenable get changes;

  /// Frames are arriving (the camera is on and the first one landed).
  bool get hasFrames;

  /// The video widget; [mirror] flips it for a front camera preview.
  Widget build({bool mirror = false});
}

/// What the media of the live call looks like right now.
@immutable
final class CallMediaInfo {
  const CallMediaInfo({
    this.local,
    this.remote,
    this.frontCamera = true,
    this.weak = false,
    this.state = CallMediaState.connecting,
  });

  final CallVideoSurface? local;
  final CallVideoSurface? remote;
  final bool frontCamera;

  /// The transport reports loss or jitter that makes the call hard to follow.
  final bool weak;
  final CallMediaState state;

  CallMediaInfo copyWith({
    CallVideoSurface? local,
    CallVideoSurface? remote,
    bool? frontCamera,
    bool? weak,
    CallMediaState? state,
  }) => CallMediaInfo(
    local: local ?? this.local,
    remote: remote ?? this.remote,
    frontCamera: frontCamera ?? this.frontCamera,
    weak: weak ?? this.weak,
    state: state ?? this.state,
  );
}

/// Why a call's media could not be set up, when the engine only reports that
/// it could not (`CallFailure.noMedia`).
enum CallMediaProblem {
  /// The server gave no relay and the privacy mode forbids a direct
  /// connection.
  noRelay,

  /// The microphone or camera could not be opened.
  deviceUnavailable,
}

/// The one live call's media, shared between the engine's media session and
/// the call screen.
///
/// The engine owns the call's state; the media adapter owns the peer
/// connection. The things only the media knows - the video surfaces, which
/// camera is facing, how the connection is doing - and the one action the
/// engine's media interface has no verb for (flip the camera) pass through
/// this hub, so neither side imports the other.
final class CallMediaHub {
  CallMediaInfo? _info;
  final StreamController<CallMediaInfo?> _changes =
      StreamController<CallMediaInfo?>.broadcast();
  Future<void> Function()? _switchCamera;

  /// Why the last media setup failed, or null.
  CallMediaProblem? lastProblem;

  CallMediaInfo? get info => _info;

  /// The current info, then every change.
  Stream<CallMediaInfo?> watch() async* {
    yield _info;
    yield* _changes.stream;
  }

  void publish(CallMediaInfo? info) {
    _info = info;
    if (!_changes.isClosed) _changes.add(info);
  }

  void update(CallMediaInfo Function(CallMediaInfo current) change) {
    final current = _info;
    if (current == null) return;
    publish(change(current));
  }

  /// Registers the live session's camera flip (null when it closes).
  // ignore: use_setters_to_change_properties
  void bindCameraSwitch(Future<void> Function()? action) =>
      _switchCamera = action;

  Future<void> switchCamera() async => _switchCamera?.call();

  Future<void> dispose() => _changes.close();
}
