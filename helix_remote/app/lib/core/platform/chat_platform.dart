import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/platform/attachment_picker.dart';
import 'package:helix_remote/core/platform/audio_player.dart';
import 'package:helix_remote/core/platform/device_audio_player.dart';
import 'package:helix_remote/core/platform/device_camera.dart';
import 'package:helix_remote/core/platform/device_video_player.dart';
import 'package:helix_remote/core/platform/device_voice_recorder.dart';
import 'package:helix_remote/core/platform/file_actions.dart';
import 'package:helix_remote/core/platform/media_sanitizer.dart';
import 'package:helix_remote/core/platform/media_temp.dart';
import 'package:helix_remote/core/platform/video_player.dart';
import 'package:helix_remote/core/platform/voice_recorder.dart';

// The clock lives in `core/engine/clock.dart`; chat code reads it from here too.
export 'package:helix_remote/core/engine/clock.dart' show clockProvider;

/// The platform seams of the chat screens: where files come from, the
/// microphone, the speaker, the screen that plays video, and the share sheet.
/// Each is an interface with a real implementation here and a fake in the
/// tests; the plugins behind them are named in this folder and nowhere else.

/// The app's cache folders for media in flight (captures, voice notes,
/// cleaned copies) and the one place they are deleted from.
final mediaTempProvider = Provider<MediaTemp>((ref) => MediaTemp());

final attachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => DeviceAttachmentPicker(
    camera: ImagePickerCamera(temp: ref.watch(mediaTempProvider)),
    temp: ref.watch(mediaTempProvider),
  ),
);

/// Removes location, time and camera details from a photo or video before the
/// engine copies it.
final mediaSanitizerProvider = Provider<MediaSanitizer>(
  (ref) => FileMediaSanitizer(temp: ref.watch(mediaTempProvider)),
);

final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final recorder = DeviceVoiceRecorder(temp: ref.watch(mediaTempProvider));
  ref.onDispose(recorder.dispose);
  return recorder;
});

/// Makes the one audio player the app uses for voice notes and audio files.
final audioPlayerFactoryProvider = Provider<AudioPlayerAdapter Function()>(
  (ref) =>
      () => DeviceAudioPlayer(),
);

/// Plays a video file in the full-screen viewer.
final videoPlayersProvider = Provider<VideoPlayers>(
  (ref) => const DeviceVideoPlayers(),
);

final fileActionsProvider = Provider<FileActions>(
  (ref) => const DeviceFileActions(),
);
