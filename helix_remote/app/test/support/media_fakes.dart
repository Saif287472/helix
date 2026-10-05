import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:helix_remote/core/platform/attachment_picker.dart';
import 'package:helix_remote/core/platform/audio_player.dart';
import 'package:helix_remote/core/platform/device_audio_player.dart';
import 'package:helix_remote/core/platform/device_voice_recorder.dart';
import 'package:helix_remote/core/platform/media_sanitizer.dart';
import 'package:helix_remote/core/platform/media_temp.dart';
import 'package:helix_remote/core/platform/video_player.dart';
import 'package:helix_remote/core/platform/voice_recorder.dart';

/// A [MediaTemp] rooted in a fresh directory (deleted by the caller).
MediaTemp tempIn(Directory root) => MediaTemp(root: () async => root);

/// A fake [VoiceRecorder] a test drives by hand.
final class FakeVoiceRecorder implements VoiceRecorder {
  FakeVoiceRecorder(this.dir);

  final Directory dir;
  bool available = true;
  Object? startError;
  Duration startDelay = Duration.zero;
  int durationMs = 3000;
  final events = <String>[];
  final _phases = StreamController<VoicePhase>.broadcast();
  String? _path;

  @override
  bool get isAvailable => available;

  @override
  Stream<VoicePhase> get phases => _phases.stream;

  /// What the system does to the recording (a call).
  void systemPhase(VoicePhase phase) => _phases.add(phase);

  @override
  Future<void> start() async {
    events.add('start');
    if (startDelay > Duration.zero) await Future<void>.delayed(startDelay);
    final error = startError;
    if (error != null) throw error;
    _path = '${dir.path}${Platform.pathSeparator}note${events.length}.m4a';
    File(_path!).writeAsBytesSync([1, 2, 3, 4]);
  }

  @override
  Future<void> pause() async => events.add('pause');

  @override
  Future<void> resume() async => events.add('resume');

  @override
  Future<RecordedVoice?> stop() async {
    events.add('stop');
    final path = _path;
    if (path == null) return null;
    return RecordedVoice(
      path: path,
      durationMs: durationMs,
      waveform: Uint8List.fromList([10, 200, 90]),
    );
  }

  @override
  Future<void> cancel() async {
    events.add('cancel');
    final path = _path;
    if (path != null && File(path).existsSync()) File(path).deleteSync();
    _path = null;
  }

  @override
  Future<void> dispose() async {}
}

/// A fake [RecordBackend] for [DeviceVoiceRecorder].
final class FakeRecordBackend implements RecordBackend {
  bool permission = true;
  Object? startError;
  bool writeFile = true;
  final calls = <String>[];
  final amps = StreamController<double>.broadcast();
  final states = StreamController<VoicePhase>.broadcast();
  String? path;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start(String path) async {
    calls.add('start');
    final error = startError;
    if (error != null) throw error;
    this.path = path;
    if (writeFile) File(path).writeAsBytesSync([9, 9, 9]);
  }

  @override
  Future<String?> stop() async {
    calls.add('stop');
    return path;
  }

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Stream<double> amplitudes(Duration interval) => amps.stream;

  @override
  Stream<VoicePhase> get phases => states.stream;

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// A fake [AudioPlayerAdapter] for the playback state machine.
final class FakeAudioPlayer implements AudioPlayerAdapter {
  final loaded = <String>[];
  final calls = <String>[];
  bool failLoad = false;
  final controller = StreamController<AudioPlayback>.broadcast();

  @override
  Future<void> load(String path) async {
    if (failLoad) throw const AudioUnavailable();
    loaded.add(path);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    controller.add(
      const AudioPlayback(duration: Duration(seconds: 10), playing: true),
    );
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    controller.add(const AudioPlayback(duration: Duration(seconds: 10)));
  }

  @override
  Future<void> seek(Duration position) async => calls.add('seek:$position');

  @override
  Future<void> setSpeed(double speed) async => calls.add('speed:$speed');

  @override
  Stream<AudioPlayback> get states => controller.stream;

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// A fake [AudioBackend] for [DeviceAudioPlayer].
final class FakeAudioBackend implements AudioBackend {
  final calls = <String>[];
  bool failSource = false;
  Duration? length = const Duration(seconds: 8);
  final pos = StreamController<Duration>.broadcast();
  final dur = StreamController<Duration>.broadcast();
  final playingCtl = StreamController<bool>.broadcast();
  final done = StreamController<void>.broadcast();
  final err = StreamController<Object>.broadcast();

  @override
  Future<void> setSource(String path) async {
    calls.add('source');
    if (failSource) throw StateError('bad file');
  }

  @override
  Future<Duration?> duration() async => length;

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> seek(Duration position) async => calls.add('seek:$position');

  @override
  Future<void> setRate(double rate) async => calls.add('rate:$rate');

  @override
  Stream<Duration> get positions => pos.stream;

  @override
  Stream<Duration> get durations => dur.stream;

  @override
  Stream<bool> get playing => playingCtl.stream;

  @override
  Stream<void> get completions => done.stream;

  @override
  Stream<Object> get errors => err.stream;

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// A picker that hands over what a test sets.
final class FakePicker implements AttachmentPicker {
  FakePicker({this.camera = true});

  bool camera;
  bool denied = false;
  PickedFile? photo;
  PickedFile? video;
  List<PickedFile> gallery = const [];

  @override
  bool get cameraAvailable => camera;

  @override
  Future<List<PickedFile>> pickGallery() async => gallery;

  @override
  Future<List<PickedFile>> pickDocuments() async => const [];

  @override
  Future<List<PickedFile>> pickAudio() async => const [];

  @override
  Future<PickedFile?> takePhoto() async {
    if (denied) throw const AttachmentPermissionDenied('camera');
    return photo;
  }

  @override
  Future<PickedFile?> recordVideo() async {
    if (denied) throw const AttachmentPermissionDenied('camera');
    return video;
  }
}

/// A sanitizer that writes a ".clean" copy (or refuses) and records its use.
final class FakeSanitizer implements MediaSanitizer {
  FakeSanitizer(this.dir);

  final Directory dir;
  final Set<String> refuse = {};
  final seen = <String>[];

  @override
  Future<SanitizedFile> sanitize(PickedFile file) async {
    seen.add(file.name);
    if (refuse.contains(file.name)) {
      return SanitizedFile(file, SanitizeOutcome.failed);
    }
    if (file.kind != PickedKind.image && file.kind != PickedKind.video) {
      return SanitizedFile(file, SanitizeOutcome.clean);
    }
    final copy = File('${dir.path}${Platform.pathSeparator}${file.name}.clean')
      ..writeAsBytesSync([7, 7]);
    return SanitizedFile(
      file.copyWith(path: copy.path, size: 2, temporary: true),
      SanitizeOutcome.stripped,
    );
  }
}

/// A [VideoPlayback] driven by the test.
final class FakeVideoPlayback implements VideoPlayback {
  FakeVideoPlayback({this.failInit = false});

  final bool failInit;
  final calls = <String>[];
  final ValueNotifier<VideoPlaybackState> value = ValueNotifier(
    const VideoPlaybackState(duration: Duration(seconds: 20)),
  );

  @override
  ValueListenable<VideoPlaybackState> get state => value;

  @override
  Future<void> initialize() async {
    calls.add('init');
    if (failInit) throw const VideoUnavailable();
  }

  VideoPlaybackState get _v => value.value;

  @override
  Future<void> play() async {
    calls.add('play');
    value.value = VideoPlaybackState(
      duration: _v.duration,
      position: _v.completed ? Duration.zero : _v.position,
      playing: true,
      speed: _v.speed,
    );
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    value.value = VideoPlaybackState(
      duration: _v.duration,
      position: _v.position,
      speed: _v.speed,
    );
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inSeconds}');
    value.value = VideoPlaybackState(
      duration: _v.duration,
      position: position,
      playing: _v.playing,
      speed: _v.speed,
    );
  }

  @override
  Future<void> setSpeed(double speed) async {
    calls.add('speed:$speed');
    value.value = VideoPlaybackState(
      duration: _v.duration,
      position: _v.position,
      playing: _v.playing,
      speed: speed,
    );
  }

  @override
  Widget surface() =>
      const SizedBox(key: Key('video-surface'), width: 160, height: 90);

  @override
  Future<void> dispose() async => calls.add('dispose');
}

final class FakeVideoPlayers implements VideoPlayers {
  FakeVideoPlayers({this.supported = true, this.failInit = false});

  final bool supported;
  final bool failInit;
  final opened = <FakeVideoPlayback>[];

  @override
  bool get isSupported => supported;

  @override
  VideoPlayback open(String path) {
    final playback = FakeVideoPlayback(failInit: failInit);
    opened.add(playback);
    return playback;
  }
}

/// An ISO box.
Uint8List testBox(String type, List<int> payload) {
  final size = 8 + payload.length;
  return Uint8List.fromList([
    size >> 24, (size >> 16) & 255, (size >> 8) & 255, size & 255, //
    ...latin1.encode(type), ...payload,
  ]);
}

List<int> u32(int v) => [v >> 24, (v >> 16) & 255, (v >> 8) & 255, v & 255];

/// A small MP4: ftyp, moov (mvhd with times, a rotated video track, udta with
/// a position) and mdat.
Uint8List testMp4() {
  final mvhd = testBox('mvhd', [
    0, 0, 0, 0, ...u32(0x11111111), ...u32(0x22222222), //
    ...u32(1000), ...u32(5000), ...List.filled(80, 0),
  ]);
  final tkhd = testBox('tkhd', [
    0, 0, 0, 3, ...u32(0x33333333), ...u32(0x44444444), ...u32(1),
    ...u32(0), ...u32(5000), ...List.filled(8, 0), 0, 0, 0, 0, 0, 0, 0, 0,
    // matrix: a=0 b=1 c=-1 d=0 (a quarter turn)
    ...u32(0), ...u32(0x10000), ...u32(0), //
    ...u32(0xFFFF0000), ...u32(0), ...u32(0), //
    ...u32(0), ...u32(0), ...u32(0x40000000),
    ...u32(1920 << 16), ...u32(1080 << 16),
  ]);
  final trak = testBox('trak', tkhd);
  final udta = testBox('udta', testBox('©xyz', ascii.encode('+23.7+090.4/')));
  final moov = testBox('moov', [...mvhd, ...trak, ...udta]);
  return Uint8List.fromList([
    ...testBox('ftyp', ascii.encode('isom\u0000\u0000\u0002\u0000isom')),
    ...moov,
    ...testBox('mdat', List.filled(1000, 0xAB)),
  ]);
}
