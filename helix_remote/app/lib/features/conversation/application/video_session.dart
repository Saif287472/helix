import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/core/platform/video_player.dart';
import 'package:helix_remote/features/conversation/application/audio_playback.dart';

/// Where opening the player has got to.
enum VideoPhase {
  /// Waiting for the decoder.
  opening,

  /// Playing or paused, with a picture.
  ready,

  /// This device cannot play the file; the screen offers the share sheet.
  failed,
}

/// What the full-screen video player draws.
@immutable
class VideoViewState {
  const VideoViewState({
    this.phase = VideoPhase.opening,
    this.surface,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.fraction = 0,
    this.positionLabel = '0:00',
    this.durationLabel = '0:00',
    this.speed = 1,
    this.message,
  });

  final VideoPhase phase;

  /// The picture, once [phase] is [VideoPhase.ready].
  final Widget? surface;
  final bool playing;
  final bool buffering;

  /// Played to the end: the centre button replays.
  final bool completed;

  /// 0..1.
  final double fraction;
  final String positionLabel;
  final String durationLabel;
  final double speed;

  /// A sentence for the failed state; never an exception.
  final String? message;

  VideoViewState copyWith({
    VideoPhase? phase,
    Widget? surface,
    bool? playing,
    bool? buffering,
    bool? completed,
    double? fraction,
    String? positionLabel,
    String? durationLabel,
    double? speed,
    String? message,
  }) => VideoViewState(
    phase: phase ?? this.phase,
    surface: surface ?? this.surface,
    playing: playing ?? this.playing,
    buffering: buffering ?? this.buffering,
    completed: completed ?? this.completed,
    fraction: fraction ?? this.fraction,
    positionLabel: positionLabel ?? this.positionLabel,
    durationLabel: durationLabel ?? this.durationLabel,
    speed: speed ?? this.speed,
    message: message ?? this.message,
  );
}

/// Plays the one video the viewer is showing.
///
/// Created when the video's page becomes the current one and disposed when it
/// stops being (`autoDispose`), which releases the decoder and gives audio
/// focus back. Starting it stops a voice note that is playing: two sounds at
/// once is never wanted in a chat.
final class VideoSession extends Notifier<VideoViewState> {
  VideoSession(this.path);

  final String path;

  VideoPlayback? _playback;
  bool _disposed = false;

  /// The speeds a tap on the speed chip cycles through.
  static const speeds = [1.0, 1.5, 2.0];

  @override
  VideoViewState build() {
    ref.onDispose(() {
      _disposed = true;
      final playback = _playback;
      playback?.state.removeListener(_sync);
      unawaited(playback?.dispose());
    });
    final players = ref.read(videoPlayersProvider);
    if (!players.isSupported) {
      return const VideoViewState(
        phase: VideoPhase.failed,
        message: 'Videos cannot be played inside Helix on this device.',
      );
    }
    // Not in `build`: state may not change while a provider is being built.
    unawaited(Future<void>.microtask(() => _open(players)));
    return const VideoViewState();
  }

  Future<void> _open(VideoPlayers players) async {
    if (_disposed) return;
    final VideoPlayback playback;
    try {
      playback = players.open(path);
      _playback = playback;
      await playback.initialize();
    } on Object {
      if (!_disposed) {
        state = const VideoViewState(
          phase: VideoPhase.failed,
          message: 'This video cannot be played on this device.',
        );
      }
      return;
    }
    if (_disposed) return;
    await ref.read(playbackProvider.notifier).stop();
    playback.state.addListener(_sync);
    state = state.copyWith(
      phase: VideoPhase.ready,
      surface: playback.surface(),
    );
    _sync();
    await playback.play();
  }

  void _sync() {
    final playback = _playback;
    if (playback == null || _disposed) return;
    final v = playback.state.value;
    if (v.failed) {
      state = const VideoViewState(
        phase: VideoPhase.failed,
        message: 'This video stopped playing.',
      );
      return;
    }
    final duration = v.duration.inMilliseconds;
    state = state.copyWith(
      playing: v.playing,
      buffering: v.buffering,
      completed: v.completed,
      fraction: duration <= 0
          ? 0
          : (v.position.inMilliseconds / duration).clamp(0.0, 1.0),
      positionLabel: formatDurationMs(v.position.inMilliseconds),
      durationLabel: formatDurationMs(duration),
      speed: v.speed,
    );
  }

  /// Play or pause (from the end, plays again from the start).
  Future<void> toggle() async {
    final playback = _playback;
    if (playback == null || state.phase != VideoPhase.ready) return;
    if (state.playing) {
      await playback.pause();
    } else {
      await playback.play();
    }
  }

  /// Jump to [fraction] (0..1) of the video.
  Future<void> seek(double fraction) async {
    final playback = _playback;
    if (playback == null || state.phase != VideoPhase.ready) return;
    final total = playback.state.value.duration.inMilliseconds;
    await playback.seek(
      Duration(milliseconds: (total * fraction.clamp(0.0, 1.0)).round()),
    );
  }

  /// 1x, 1.5x, 2x.
  Future<void> cycleSpeed() async {
    final playback = _playback;
    if (playback == null || state.phase != VideoPhase.ready) return;
    final next = speeds[(speeds.indexOf(state.speed) + 1) % speeds.length];
    await playback.setSpeed(next);
  }

  /// The app went to the background: video does not play behind it.
  Future<void> pause() async {
    final playback = _playback;
    if (playback == null || !state.playing) return;
    await playback.pause();
  }
}

/// Keyed by the file's path. Auto-disposed: leaving the page frees the
/// decoder.
final videoSessionProvider = NotifierProvider.autoDispose
    .family<VideoSession, VideoViewState, String>(VideoSession.new);
