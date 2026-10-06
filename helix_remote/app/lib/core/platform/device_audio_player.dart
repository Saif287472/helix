import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:helix_remote/core/platform/audio_player.dart';

/// The playback plugin as [DeviceAudioPlayer] needs it, and nothing more.
///
/// An interface so the player's state machine (what "completed" does to the
/// position, a failed load, speed before and after loading) is tested with a
/// fake, without a speaker.
abstract interface class AudioBackend {
  /// Prepares the file at [path]. Throws when it cannot be played.
  Future<void> setSource(String path);
  Future<Duration?> duration();
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);

  Stream<Duration> get positions;
  Stream<Duration> get durations;

  /// True while sound is coming out.
  Stream<bool> get playing;

  /// Emits when the file has been played to its end.
  Stream<void> get completions;

  /// Playback failed after it had started.
  Stream<Object> get errors;
  Future<void> dispose();
}

/// Playback through the `audioplayers` plugin: Android's media player and
/// Media Foundation on Windows.
///
/// Audio focus is requested when playback starts (other apps' music pauses
/// and a phone call pauses this), and the platform gives it back on its own.
final class PluginAudioBackend implements AudioBackend {
  PluginAudioBackend() {
    unawaited(_configure());
    _player.eventStream.listen(
      (_) {},
      onError: (Object error) {
        if (!_errors.isClosed) _errors.add(error);
      },
    );
  }

  Future<void> _configure() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.gain).build(),
      );
    } on Object {
      // The defaults still play; only the focus request is lost.
    }
  }

  final AudioPlayer _player = AudioPlayer();
  final _errors = StreamController<Object>.broadcast();

  @override
  Future<void> setSource(String path) =>
      _player.setSource(DeviceFileSource(path));

  @override
  Future<Duration?> duration() => _player.getDuration();

  @override
  Future<void> play() => _player.resume();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setRate(double rate) => _player.setPlaybackRate(rate);

  @override
  Stream<Duration> get positions => _player.onPositionChanged;

  @override
  Stream<Duration> get durations => _player.onDurationChanged;

  @override
  Stream<bool> get playing =>
      _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  @override
  Stream<void> get completions => _player.onPlayerComplete;

  @override
  Stream<Object> get errors => _errors.stream;

  @override
  Future<void> dispose() async {
    await _errors.close();
    await _player.dispose();
  }
}

/// The real [AudioPlayerAdapter]: one file at a time, with its position and
/// state reported as they change.
final class DeviceAudioPlayer implements AudioPlayerAdapter {
  DeviceAudioPlayer({AudioBackend? backend})
    : _backend = backend ?? PluginAudioBackend() {
    _subs.addAll([
      _backend.positions.listen((position) {
        _state = _copy(position: position);
        _emit();
      }),
      _backend.durations.listen((duration) {
        _state = _copy(duration: duration);
        _emit();
      }),
      _backend.playing.listen((playing) {
        _state = _copy(playing: playing, completed: false);
        _emit();
      }),
      _backend.completions.listen((_) {
        // Back to the start and not playing, so a second tap plays it again.
        _state = AudioPlayback(
          position: Duration.zero,
          duration: _state.duration,
          completed: true,
        );
        _emit();
      }),
      _backend.errors.listen((_) {
        _state = AudioPlayback(duration: _state.duration, failed: true);
        _emit();
      }),
    ]);
  }

  final AudioBackend _backend;
  final List<StreamSubscription<Object?>> _subs = [];
  final _states = StreamController<AudioPlayback>.broadcast();
  AudioPlayback _state = const AudioPlayback();
  double _speed = 1;
  bool _loaded = false;

  @override
  Stream<AudioPlayback> get states => _states.stream;

  @override
  Future<void> load(String path) async {
    _loaded = false;
    try {
      await _backend.stop();
      await _backend.setSource(path);
      _state = AudioPlayback(
        duration: await _backend.duration() ?? Duration.zero,
      );
      _loaded = true;
      await _backend.setRate(_speed);
    } on Object {
      _state = const AudioPlayback();
      throw const AudioUnavailable();
    }
    _emit();
  }

  @override
  Future<void> play() async {
    if (!_loaded) return;
    try {
      await _backend.play();
    } on Object {
      _state = AudioPlayback(duration: _state.duration, failed: true);
      _emit();
    }
  }

  @override
  Future<void> pause() async {
    if (!_loaded) return;
    try {
      await _backend.pause();
    } on Object {
      // Already stopped.
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_loaded) return;
    final limit = _state.duration;
    final target = limit > Duration.zero && position > limit ? limit : position;
    try {
      await _backend.seek(target < Duration.zero ? Duration.zero : target);
    } on Object {
      return;
    }
    _state = _copy(position: target);
    _emit();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    if (!_loaded) return;
    try {
      await _backend.setRate(speed);
    } on Object {
      // Some files cannot change speed; they play at 1x.
    }
  }

  @override
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _backend.dispose();
    await _states.close();
  }

  AudioPlayback _copy({
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? completed,
  }) => AudioPlayback(
    position: position ?? _state.position,
    duration: duration ?? _state.duration,
    playing: playing ?? _state.playing,
    completed: completed ?? _state.completed,
  );

  void _emit() {
    if (!_states.isClosed) _states.add(_state);
  }
}
