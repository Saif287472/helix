import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/platform/attachment_picker.dart';
import 'package:helix_remote/core/platform/audio_player.dart';
import 'package:helix_remote/core/platform/file_actions.dart';
import 'package:helix_remote/core/platform/voice_recorder.dart';

// The clock lives in `core/engine/clock.dart`; chat code reads it from here too.
export 'package:helix_remote/core/engine/clock.dart' show clockProvider;

/// The platform seams of the chat screens: where files come from, the
/// microphone, the speaker, and the share sheet. Each is an interface with a
/// real implementation here and a fake in the tests.
final attachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => const DeviceAttachmentPicker(),
);

final voiceRecorderProvider = Provider<VoiceRecorder>(
  (ref) => const UnavailableVoiceRecorder(),
);

/// Makes the one audio player the app uses for voice notes and audio files.
final audioPlayerFactoryProvider = Provider<AudioPlayerAdapter Function()>(
  (ref) =>
      () => const UnavailableAudioPlayer(),
);

final fileActionsProvider = Provider<FileActions>(
  (ref) => const DeviceFileActions(),
);
