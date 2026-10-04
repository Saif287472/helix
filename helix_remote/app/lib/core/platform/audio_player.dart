/// Where audio playback has got to.
final class AudioPlayback {
  const AudioPlayback({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.completed = false,
  });

  final Duration position;
  final Duration duration;
  final bool playing;

  /// Played to the end.
  final bool completed;
}

/// Thrown by [AudioPlayerAdapter.load] when this device cannot play audio
/// (no player in this build, or the file cannot be decoded).
final class AudioUnavailable implements Exception {
  const AudioUnavailable();

  @override
  String toString() => 'audio playback is not available';
}

/// One audio player: a voice note or an audio file at a time.
///
/// An interface so the app never imports a player plugin from the chat code
/// and a test drives playback by hand.
abstract interface class AudioPlayerAdapter {
  /// Loads the file at [path] and stops whatever was playing. Throws
  /// [AudioUnavailable].
  Future<void> load(String path);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// 1, 1.5 or 2.
  Future<void> setSpeed(double speed);

  /// Position and state, as they change.
  Stream<AudioPlayback> get states;

  Future<void> dispose();
}

/// The player of a build without a playback plugin.
final class UnavailableAudioPlayer implements AudioPlayerAdapter {
  const UnavailableAudioPlayer();

  @override
  Future<void> load(String path) async => throw const AudioUnavailable();

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Stream<AudioPlayback> get states => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
