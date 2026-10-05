import 'dart:math' as math;
import 'dart:typed_data';

/// A finished voice recording.
final class RecordedVoice {
  const RecordedVoice({
    required this.path,
    required this.durationMs,
    required this.waveform,
    this.mime = 'audio/mp4',
  });

  /// A file the engine can copy into its store. The app made it in its cache
  /// and deletes it once it has been sent or thrown away.
  final String path;
  final int durationMs;

  /// One byte (0-255) per sample, what the bubble draws.
  final Uint8List waveform;
  final String mime;
}

/// What the microphone is doing right now. A call or another app taking the
/// microphone moves it from [recording] to [paused] without the person
/// touching anything, which is why the composer follows this stream rather
/// than its own idea of the state.
enum VoicePhase { idle, recording, paused }

/// Thrown by [VoiceRecorder.start] when this device cannot record (no
/// microphone, or no recorder in this build).
final class VoiceRecorderUnavailable implements Exception {
  const VoiceRecorderUnavailable();

  @override
  String toString() => 'voice recording is not available';
}

/// Thrown by [VoiceRecorder.start] when the microphone permission is
/// refused (now, or earlier and for good).
final class VoiceRecorderPermissionDenied implements Exception {
  const VoiceRecorderPermissionDenied();

  @override
  String toString() => 'microphone permission denied';
}

/// The microphone, as the composer needs it: start, and a result file (with
/// its waveform) when it stops.
///
/// An interface so the composer never imports a recorder plugin and a test
/// drives it by hand.
abstract interface class VoiceRecorder {
  /// The longest voice note. The composer stops and sends at this length.
  static const maxDuration = Duration(minutes: 10);

  /// Whether recording can work on this device at all.
  bool get isAvailable;

  /// Changes of [VoicePhase], including ones the system made.
  Stream<VoicePhase> get phases;

  /// Asks for the microphone permission when it is not granted yet (the
  /// system prompt), and starts recording. Throws
  /// [VoiceRecorderPermissionDenied] and [VoiceRecorderUnavailable].
  Future<void> start();

  /// Holds the recording (the app went to the background); [resume] carries
  /// on into the same file.
  Future<void> pause();
  Future<void> resume();

  /// Stops and returns the recording, or null when nothing usable was
  /// recorded.
  Future<RecordedVoice?> stop();

  /// Stops and throws the recording away (the file is deleted).
  Future<void> cancel();

  /// Releases the microphone.
  Future<void> dispose();
}

/// The recorder of a build that has no recording plugin: every attempt says
/// so. Voice notes can still be received and played.
final class UnavailableVoiceRecorder implements VoiceRecorder {
  const UnavailableVoiceRecorder();

  @override
  bool get isAvailable => false;

  @override
  Stream<VoicePhase> get phases => const Stream.empty();

  @override
  Future<void> start() async => throw const VoiceRecorderUnavailable();

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<RecordedVoice?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

/// Turns the loudness readings taken while recording into the waveform the
/// bubble draws.
abstract final class VoiceWaveform {
  /// Most samples a voice note carries: enough for the 36 bars the bubble
  /// draws, small enough not to matter in the message.
  static const maxSamples = 72;

  /// Readings quieter than this (decibels full scale) draw as silence.
  static const floorDb = -45.0;

  /// One byte per sample from [decibels] (0 is the loudest a microphone
  /// reports, quieter is negative). More readings than [samples] are merged
  /// by taking the loudest of each group, so a short word is not averaged
  /// away. Empty when there are no readings.
  static Uint8List fromDecibels(
    List<double> decibels, {
    int samples = maxSamples,
  }) {
    if (decibels.isEmpty) return Uint8List(0);
    final count = math.min(samples, decibels.length);
    final out = Uint8List(count);
    for (var i = 0; i < count; i++) {
      final from = (i * decibels.length / count).floor();
      final to = math.max(from + 1, ((i + 1) * decibels.length / count).ceil());
      var peak = floorDb;
      for (var j = from; j < to && j < decibels.length; j++) {
        final db = decibels[j];
        if (db.isFinite && db > peak) peak = db;
      }
      // Loudness is not linear in decibels; a gentle curve keeps speech
      // from looking flat next to a shout.
      final level = ((peak - floorDb) / -floorDb).clamp(0.0, 1.0);
      out[i] = (math.pow(level, 0.8) * 255).round();
    }
    return out;
  }
}
