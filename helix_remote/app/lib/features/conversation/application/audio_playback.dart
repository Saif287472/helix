import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/platform/audio_player.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';

/// Which voice note or audio file is playing, and how far it has got.
@immutable
class PlaybackState {
  const PlaybackState({
    this.messageRowid,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1,
    this.played = const {},
    this.notice,
    this.noticeSerial = 0,
  });

  /// The message being played (one at a time), or null.
  final int? messageRowid;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double speed;

  /// Voice notes that were played to the end on this device.
  final Set<int> played;

  /// A sentence for a snackbar ("Downloading..."); never an exception.
  final String? notice;
  final int noticeSerial;

  @override
  bool operator ==(Object other) =>
      other is PlaybackState &&
      other.messageRowid == messageRowid &&
      other.playing == playing &&
      other.position == position &&
      other.duration == duration &&
      other.speed == speed &&
      setEquals(other.played, played);

  @override
  int get hashCode => Object.hash(
    messageRowid,
    playing,
    position,
    duration,
    speed,
    Object.hashAllUnordered(played),
  );

  /// 0..1.
  double get fraction => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  PlaybackState copyWith({
    int? Function()? messageRowid,
    bool? playing,
    Duration? position,
    Duration? duration,
    double? speed,
    Set<int>? played,
    String? notice,
  }) => PlaybackState(
    messageRowid: messageRowid == null ? this.messageRowid : messageRowid(),
    playing: playing ?? this.playing,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    speed: speed ?? this.speed,
    played: played ?? this.played,
    notice: notice ?? this.notice,
    noticeSerial: notice == null ? noticeSerial : noticeSerial + 1,
  );
}

/// Plays one voice note or audio file at a time, through the injected player.
final class PlaybackNotifier extends Notifier<PlaybackState> {
  AudioPlayerAdapter? _player;
  StreamSubscription<AudioPlayback>? _sub;

  @override
  PlaybackState build() {
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      unawaited(_player?.dispose());
    });
    return const PlaybackState();
  }

  /// The speeds a tap on the speed chip cycles through.
  static const speeds = [1.0, 1.5, 2.0];

  AudioPlayerAdapter get _adapter =>
      _player ??= ref.read(audioPlayerFactoryProvider)();

  /// Play, pause or resume the attachment [attachmentId] of message
  /// [rowid]. A file that is not on the device yet is fetched first.
  Future<void> toggle(int rowid, int attachmentId) async {
    if (state.messageRowid == rowid) {
      if (state.playing) {
        await _adapter.pause();
      } else {
        await _adapter.play();
      }
      return;
    }
    final gateway = await ref.read(chatGatewayProvider.future);
    final path = await gateway.localPathOf(attachmentId);
    if (path == null) {
      state = state.copyWith(notice: 'Downloading the audio...');
      try {
        await gateway.downloadNow(attachmentId);
      } on Object {
        state = state.copyWith(notice: 'The audio could not be downloaded.');
      }
      return;
    }
    try {
      await _adapter.load(path);
    } on AudioUnavailable {
      state = state.copyWith(
        notice: 'Audio playback is not available on this device.',
      );
      return;
    }
    await _sub?.cancel();
    state = state.copyWith(
      messageRowid: () => rowid,
      playing: false,
      position: Duration.zero,
      duration: Duration.zero,
    );
    await _adapter.setSpeed(state.speed);
    _sub = _adapter.states.listen((playback) {
      if (playback.failed) {
        // The file broke off (or the output went away): nothing is playing.
        state = state.copyWith(
          messageRowid: () => null,
          playing: false,
          position: Duration.zero,
          notice: 'This audio could not be played.',
        );
        return;
      }
      final finished = playback.completed;
      state = state.copyWith(
        playing: playback.playing && !finished,
        position: finished ? Duration.zero : playback.position,
        duration: playback.duration,
        played: finished ? {...state.played, rowid} : null,
      );
      if (finished) state = state.copyWith(messageRowid: () => null);
    });
    await _adapter.play();
  }

  /// Seek the message being played to [fraction] (0..1).
  Future<void> seek(int rowid, double fraction) async {
    if (state.messageRowid != rowid) return;
    final target = Duration(
      milliseconds: (state.duration.inMilliseconds * fraction).round(),
    );
    await _adapter.seek(target);
  }

  /// 1x, 1.5x, 2x.
  Future<void> cycleSpeed() async {
    final next = speeds[(speeds.indexOf(state.speed) + 1) % speeds.length];
    state = state.copyWith(speed: next);
    if (state.messageRowid != null) await _adapter.setSpeed(next);
  }

  /// Stop whatever is playing (the conversation closed).
  Future<void> stop() async {
    if (state.messageRowid == null) return;
    await _adapter.pause();
    state = state.copyWith(
      messageRowid: () => null,
      playing: false,
      position: Duration.zero,
    );
  }
}

final playbackProvider = NotifierProvider<PlaybackNotifier, PlaybackState>(
  PlaybackNotifier.new,
);
