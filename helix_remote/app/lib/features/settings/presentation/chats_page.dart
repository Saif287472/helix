import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Settings > Chats, drawn by `orbit_ui`'s
/// [orbit.ChatsSettingsScreen]: the text size (applied on top of the phone's
/// own), whether Enter sends, and which incoming media downloads by itself.
/// The theme is on its own page, Appearance.
class ChatsSettingsPage extends ConsumerWidget {
  const ChatsSettingsPage({super.key});

  static orbit.TextSizeChoice sizeOf(int percent) => switch (percent) {
    <= 90 => orbit.TextSizeChoice.small,
    < 115 => orbit.TextSizeChoice.normal,
    < 130 => orbit.TextSizeChoice.large,
    _ => orbit.TextSizeChoice.extraLarge,
  };

  static int percentOf(orbit.TextSizeChoice size) => switch (size) {
    orbit.TextSizeChoice.small => 90,
    orbit.TextSizeChoice.normal => 100,
    orbit.TextSizeChoice.large => 115,
    orbit.TextSizeChoice.extraLarge => 130,
  };

  static orbit.DownloadWhen whenOf(MediaDownloadPolicy p) => switch (p) {
    MediaDownloadPolicy.never => orbit.DownloadWhen.never,
    MediaDownloadPolicy.wifi => orbit.DownloadWhen.wifi,
    MediaDownloadPolicy.always => orbit.DownloadWhen.always,
  };

  static MediaDownloadPolicy policyOf(orbit.DownloadWhen w) => switch (w) {
    orbit.DownloadWhen.never => MediaDownloadPolicy.never,
    orbit.DownloadWhen.wifi => MediaDownloadPolicy.wifi,
    orbit.DownloadWhen.always => MediaDownloadPolicy.always,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(settingsActionsProvider);

    return orbit.ChatsSettingsScreen(
      model: orbit.ChatsSettingsModel(
        textSize: sizeOf(ref.watch(fontScaleSettingProvider).value ?? 100),
        enterSends: ref.watch(enterToSendProvider).value ?? false,
        photos: whenOf(
          ref.watch(mediaImagesProvider).value ?? MediaDownloadPolicy.wifi,
        ),
        voice: whenOf(
          ref.watch(mediaAudioProvider).value ?? MediaDownloadPolicy.always,
        ),
        videos: whenOf(
          ref.watch(mediaVideoProvider).value ?? MediaDownloadPolicy.never,
        ),
        documents: whenOf(
          ref.watch(mediaDocumentsProvider).value ?? MediaDownloadPolicy.never,
        ),
      ),
      actions: orbit.ChatsSettingsActions(
        onTextSize: (size) => actions.setFontScale(percentOf(size)),
        onEnterSends: actions.setEnterToSend,
        onDownload: (kind, when) {
          final media = switch (kind) {
            'photos' => MediaKindChoice.images,
            'voice' => MediaKindChoice.audio,
            'videos' => MediaKindChoice.video,
            'documents' => MediaKindChoice.documents,
            _ => null,
          };
          if (media != null) actions.setMediaPolicy(media, policyOf(when));
        },
      ),
    );
  }
}
