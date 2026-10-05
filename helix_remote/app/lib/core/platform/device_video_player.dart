import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:helix_remote/core/platform/video_player.dart';
import 'package:video_player/video_player.dart';

/// Video playback through the first-party `video_player` plugin (ExoPlayer on
/// Android, AVFoundation on iOS). It has no Windows implementation, so there
/// [isSupported] is false and the viewer hands the file to the system instead.
final class DeviceVideoPlayers implements VideoPlayers {
  const DeviceVideoPlayers();

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  VideoPlayback open(String path) {
    if (!isSupported) throw const VideoUnavailable();
    return _PluginVideoPlayback(
      VideoPlayerController.file(
        File(path),
        // A video takes audio focus from other apps and gives it back.
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      ),
    );
  }
}

final class _PluginVideoPlayback implements VideoPlayback {
  _PluginVideoPlayback(this._controller);

  final VideoPlayerController _controller;
  final ValueNotifier<VideoPlaybackState> _state = ValueNotifier(
    const VideoPlaybackState(),
  );
  double _speed = 1;
  bool _disposed = false;

  @override
  ValueListenable<VideoPlaybackState> get state => _state;

  @override
  Future<void> initialize() async {
    try {
      await _controller.initialize();
    } on Object {
      throw const VideoUnavailable();
    }
    _controller.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final v = _controller.value;
    final done =
        v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration;
    _state.value = VideoPlaybackState(
      position: done ? Duration.zero : v.position,
      duration: v.duration,
      playing: v.isPlaying && !done,
      buffering: v.isBuffering,
      completed: done,
      failed: v.hasError,
      speed: _speed,
      aspectRatio: v.isInitialized && v.aspectRatio > 0
          ? v.aspectRatio
          : 16 / 9,
    );
  }

  @override
  Future<void> play() async {
    // After the end, play starts again from the beginning.
    final v = _controller.value;
    if (v.duration > Duration.zero && v.position >= v.duration) {
      await _controller.seekTo(Duration.zero);
    }
    await _controller.play();
  }

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seek(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _controller.setPlaybackSpeed(speed);
    _sync();
  }

  @override
  Widget surface() => AspectRatio(
    aspectRatio: _state.value.aspectRatio,
    child: VideoPlayer(_controller),
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_sync);
    await _controller.dispose();
    _state.dispose();
  }
}
