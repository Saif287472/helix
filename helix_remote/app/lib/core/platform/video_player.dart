import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Where video playback has got to.
@immutable
final class VideoPlaybackState {
  const VideoPlaybackState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.failed = false,
    this.speed = 1,
    this.aspectRatio = 16 / 9,
  });

  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;

  /// Played to the end.
  final bool completed;

  /// Playback broke off: the file could not be decoded.
  final bool failed;
  final double speed;

  /// Width over height of the picture as it is shown.
  final double aspectRatio;

  @override
  bool operator ==(Object other) =>
      other is VideoPlaybackState &&
      other.position == position &&
      other.duration == duration &&
      other.playing == playing &&
      other.buffering == buffering &&
      other.completed == completed &&
      other.failed == failed &&
      other.speed == speed &&
      other.aspectRatio == aspectRatio;

  @override
  int get hashCode => Object.hash(
    position,
    duration,
    playing,
    buffering,
    completed,
    failed,
    speed,
    aspectRatio,
  );
}

/// Thrown by [VideoPlayback.initialize] when this device cannot play the file
/// (no player on this platform, or a format the decoder refuses).
final class VideoUnavailable implements Exception {
  const VideoUnavailable();

  @override
  String toString() => 'video playback is not available';
}

/// One video being played: the picture, and the controls' effects.
///
/// An interface so the full-screen player is tested with a fake, and so the
/// app imports the video plugin in exactly one file.
abstract interface class VideoPlayback {
  /// Position and state, updated as they change.
  ValueListenable<VideoPlaybackState> get state;

  /// Opens the file. Throws [VideoUnavailable].
  Future<void> initialize();

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// 1, 1.5 or 2.
  Future<void> setSpeed(double speed);

  /// The picture. Sized by its parent; keeps its own aspect ratio.
  Widget surface();

  /// Releases the decoder and the audio focus.
  Future<void> dispose();
}

/// Makes a [VideoPlayback] for a file.
abstract interface class VideoPlayers {
  /// Whether this platform has a player at all. When false the viewer offers
  /// the share sheet instead.
  bool get isSupported;

  VideoPlayback open(String path);
}

/// The players of a build or platform with no video plugin.
final class UnavailableVideoPlayers implements VideoPlayers {
  const UnavailableVideoPlayers();

  @override
  bool get isSupported => false;

  @override
  VideoPlayback open(String path) => throw const VideoUnavailable();
}
