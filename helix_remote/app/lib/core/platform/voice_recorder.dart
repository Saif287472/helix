import 'dart:typed_data';

/// A finished voice recording.
final class RecordedVoice {
  const RecordedVoice({
    required this.path,
    required this.durationMs,
    required this.waveform,
    this.mime = 'audio/ogg',
  });

  /// A file the engine can copy into its store.
  final String path;
  final int durationMs;

  /// One byte (0-255) per sample, what the bubble draws.
  final Uint8List waveform;
  final String mime;
}

/// Thrown by [VoiceRecorder.start] when this device cannot record (no
/// microphone, permission refused, or no recorder in this build).
final class VoiceRecorderUnavailable implements Exception {
  const VoiceRecorderUnavailable();

  @override
  String toString() => 'voice recording is not available';
}

/// The microphone, as the composer needs it: start, and a result file (with
/// its waveform) when it stops.
///
/// An interface so the composer never imports a recorder plugin and a test
/// drives it by hand.
abstract interface class VoiceRecorder {
  /// Whether recording can work on this device at all.
  bool get isAvailable;

  /// Starts recording. Throws [VoiceRecorderUnavailable].
  Future<void> start();

  /// Stops and returns the recording, or null when nothing usable was
  /// recorded (too short).
  Future<RecordedVoice?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();
}

/// The recorder of a build that has no recording plugin: every attempt says
/// so. Voice notes can still be received and played.
final class UnavailableVoiceRecorder implements VoiceRecorder {
  const UnavailableVoiceRecorder();

  @override
  bool get isAvailable => false;

  @override
  Future<void> start() async => throw const VoiceRecorderUnavailable();

  @override
  Future<RecordedVoice?> stop() async => null;

  @override
  Future<void> cancel() async {}
}
