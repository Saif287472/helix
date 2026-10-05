import 'dart:async';
import 'dart:io';

import 'package:helix_remote/core/platform/media_temp.dart';
import 'package:helix_remote/core/platform/voice_recorder.dart';
import 'package:record/record.dart';

/// The recording plugin as [DeviceVoiceRecorder] needs it, and nothing more.
///
/// An interface so the recorder's own logic (the clock that stops while it is
/// paused, the waveform, deleting the file) is tested with a fake, without a
/// microphone.
abstract interface class RecordBackend {
  /// Whether the microphone may be used; asks the person when it has not been
  /// decided.
  Future<bool> hasPermission();

  /// Starts recording voice into [path] (AAC in an MP4 container).
  Future<void> start(String path);
  Future<String?> stop();
  Future<void> cancel();
  Future<void> pause();
  Future<void> resume();

  /// Loudness in decibels full scale (0 loudest, negative quieter), every
  /// [interval] while recording.
  Stream<double> amplitudes(Duration interval);

  /// The recorder's own state changes, including pauses the system caused.
  Stream<VoicePhase> get phases;
  Future<void> dispose();
}

/// The microphone through the `record` plugin.
final class PluginRecordBackend implements RecordBackend {
  AudioRecorder? _recorder;

  AudioRecorder get _rec => _recorder ??= AudioRecorder();

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<void> start(String path) => _rec.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      // Speech: one channel, 48 kbit/s is about 360 KB a minute.
      numChannels: 1,
      bitRate: 48000,
      sampleRate: 44100,
      autoGain: true,
      noiseSuppress: true,
      // A call or another app that takes audio focus pauses the recording and
      // hands it back when it is done; the clock follows [phases].
      audioInterruption: AudioInterruptionMode.pauseResume,
    ),
    path: path,
  );

  @override
  Future<String?> stop() => _rec.stop();

  @override
  Future<void> cancel() => _rec.cancel();

  @override
  Future<void> pause() => _rec.pause();

  @override
  Future<void> resume() => _rec.resume();

  @override
  Stream<double> amplitudes(Duration interval) =>
      _rec.onAmplitudeChanged(interval).map((a) => a.current);

  @override
  Stream<VoicePhase> get phases => _rec.onStateChanged().map(
    (state) => switch (state) {
      RecordState.record => VoicePhase.recording,
      RecordState.pause => VoicePhase.paused,
      RecordState.stop => VoicePhase.idle,
    },
  );

  @override
  Future<void> dispose() async {
    final recorder = _recorder;
    _recorder = null;
    await recorder?.dispose();
  }
}

/// The real [VoiceRecorder]: one recording at a time, into a file in the
/// app's cache that is deleted when the note is sent or thrown away.
final class DeviceVoiceRecorder implements VoiceRecorder {
  DeviceVoiceRecorder({
    RecordBackend? backend,
    MediaTemp? temp,
    DateTime Function()? clock,
    bool? available,
  }) : _backend = backend ?? PluginRecordBackend(),
       _temp = temp ?? MediaTemp(),
       _now = clock ?? DateTime.now,
       isAvailable =
           available ??
           (Platform.isAndroid || Platform.isIOS || Platform.isWindows);

  final RecordBackend _backend;
  final MediaTemp _temp;
  final DateTime Function() _now;

  @override
  final bool isAvailable;

  /// How often loudness is read: ten readings a second.
  static const sampleEvery = Duration(milliseconds: 100);

  final _phases = StreamController<VoicePhase>.broadcast();
  StreamSubscription<VoicePhase>? _phaseSub;
  StreamSubscription<double>? _ampSub;

  String? _path;
  VoicePhase _phase = VoicePhase.idle;
  final List<double> _decibels = [];

  /// Time spent recording, not counting pauses: what was banked before the
  /// current run, and when the current run began (null while paused).
  Duration _banked = Duration.zero;
  DateTime? _runningSince;

  @override
  Stream<VoicePhase> get phases => _phases.stream;

  Duration get _elapsed {
    final since = _runningSince;
    return since == null ? _banked : _banked + _now().difference(since);
  }

  @override
  Future<void> start() async {
    if (!isAvailable) throw const VoiceRecorderUnavailable();
    if (_phase != VoicePhase.idle || _path != null) return;
    final bool allowed;
    try {
      allowed = await _backend.hasPermission();
    } on Object {
      throw const VoiceRecorderUnavailable();
    }
    if (!allowed) throw const VoiceRecorderPermissionDenied();

    final path = await _temp.newPath(MediaTemp.voice, extension: 'm4a');
    _path = path;
    _decibels.clear();
    _banked = Duration.zero;
    _runningSince = null;
    _phaseSub = _backend.phases.listen(_onBackendPhase, onError: (_) {});
    try {
      await _backend.start(path);
    } on Object {
      await _release();
      await _temp.delete(path);
      throw const VoiceRecorderUnavailable();
    }
    _ampSub = _backend
        .amplitudes(sampleEvery)
        .listen(
          (db) {
            if (_phase == VoicePhase.recording) _decibels.add(db);
          },
          onError: (_) {},
        );
    _enter(VoicePhase.recording);
  }

  @override
  Future<void> pause() async {
    if (_phase != VoicePhase.recording) return;
    try {
      await _backend.pause();
    } on Object {
      return;
    }
    _enter(VoicePhase.paused);
  }

  @override
  Future<void> resume() async {
    if (_phase != VoicePhase.paused) return;
    try {
      await _backend.resume();
    } on Object {
      return;
    }
    _enter(VoicePhase.recording);
  }

  @override
  Future<RecordedVoice?> stop() async {
    final path = _path;
    if (path == null) return null;
    final durationMs = _elapsed.inMilliseconds;
    final waveform = VoiceWaveform.fromDecibels(_decibels);
    String? written;
    try {
      written = await _backend.stop();
    } on Object {
      written = null;
    }
    await _release();
    final file = File(written ?? path);
    if (!await file.exists() || await file.length() == 0) {
      await _temp.delete(file.path);
      await _temp.delete(path);
      return null;
    }
    return RecordedVoice(
      path: file.path,
      durationMs: durationMs,
      waveform: waveform,
    );
  }

  @override
  Future<void> cancel() async {
    final path = _path;
    if (path == null) return;
    try {
      await _backend.cancel();
    } on Object {
      // Stopping failed; the file is deleted below either way.
    }
    await _release();
    await _temp.delete(path);
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _backend.dispose();
    await _phases.close();
  }

  /// A state change the recorder itself reported: a pause or resume that a
  /// call (or another app taking the microphone) caused.
  void _onBackendPhase(VoicePhase reported) {
    // Our own start and stop already move [_phase]; only the system's pauses
    // and resumes need following here.
    if (_path == null) return;
    if (reported == VoicePhase.paused && _phase == VoicePhase.recording) {
      _enter(VoicePhase.paused);
    } else if (reported == VoicePhase.recording &&
        _phase == VoicePhase.paused) {
      _enter(VoicePhase.recording);
    }
  }

  void _enter(VoicePhase next) {
    if (next == _phase) return;
    if (_phase == VoicePhase.recording) {
      _banked = _elapsed;
      _runningSince = null;
    }
    if (next == VoicePhase.recording) _runningSince = _now();
    _phase = next;
    if (!_phases.isClosed) _phases.add(next);
  }

  Future<void> _release() async {
    await _ampSub?.cancel();
    await _phaseSub?.cancel();
    _ampSub = null;
    _phaseSub = null;
    _banked = Duration.zero;
    _runningSince = null;
    _path = null;
    _decibels.clear();
    if (_phase != VoicePhase.idle) {
      _phase = VoicePhase.idle;
      if (!_phases.isClosed) _phases.add(VoicePhase.idle);
    }
  }
}
