import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/features/settings/presentation/choice_sheet.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Chats.
///
/// The theme is not a choice here: Helix has one light theme. What can change
/// is the text size (applied on top of the phone's own), whether Enter sends,
/// and which incoming media downloads by itself.
class ChatsSettingsPage extends ConsumerWidget {
  const ChatsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(settingsActionsProvider);
    final scale = ref.watch(fontScaleSettingProvider).value ?? 100;
    final enter = ref.watch(enterToSendProvider).value ?? false;
    final images =
        ref.watch(mediaImagesProvider).value ?? MediaDownloadPolicy.always;
    final audio =
        ref.watch(mediaAudioProvider).value ?? MediaDownloadPolicy.always;
    final video =
        ref.watch(mediaVideoProvider).value ?? MediaDownloadPolicy.never;
    final documents =
        ref.watch(mediaDocumentsProvider).value ?? MediaDownloadPolicy.never;

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: ListView(
        children: [
          HelixSettingsSection(
            title: 'Display',
            footer:
                'Text size is added to your phone\'s own text size, so both '
                'apply. Helix has one theme, a light one.',
            children: [
              HelixSettingsTile(
                icon: Icons.text_fields,
                title: 'Text size',
                subtitle: fontScaleLabel(scale),
                showChevron: true,
                onTap: () async {
                  final picked = await showChoiceSheet<int>(
                    context,
                    title: 'Text size',
                    options: [
                      for (final p in fontScaleChoices) (p, fontScaleLabel(p)),
                    ],
                    selected: scale,
                  );
                  if (picked != null) await actions.setFontScale(picked.value);
                },
              ),
            ],
          ),
          HelixSettingsSection(
            title: 'Typing',
            children: [
              HelixSettingsSwitchTile(
                icon: Icons.keyboard_return,
                title: 'Enter key sends',
                subtitle:
                    'With a hardware keyboard. Otherwise Enter adds a '
                    'new line',
                value: enter,
                onChanged: actions.setEnterToSend,
              ),
            ],
          ),
          HelixSettingsSection(
            title: 'Media auto-download',
            footer:
                'Anything not downloaded by itself downloads when you tap it. '
                'Small previews always load so a chat is not blank. '
                'Downloading on mobile data uses your data plan.',
            children: [
              _mediaTile(
                context,
                actions,
                MediaKindChoice.images,
                Icons.image_outlined,
                'Photos',
                images,
              ),
              _mediaTile(
                context,
                actions,
                MediaKindChoice.audio,
                Icons.mic_none,
                'Voice messages',
                audio,
              ),
              _mediaTile(
                context,
                actions,
                MediaKindChoice.video,
                Icons.videocam_outlined,
                'Videos',
                video,
              ),
              _mediaTile(
                context,
                actions,
                MediaKindChoice.documents,
                Icons.description_outlined,
                'Documents',
                documents,
              ),
            ],
          ),
          const SizedBox(height: HelixSpace.lg),
        ],
      ),
    );
  }

  Widget _mediaTile(
    BuildContext context,
    SettingsActions actions,
    MediaKindChoice kind,
    IconData icon,
    String title,
    MediaDownloadPolicy value,
  ) => HelixSettingsTile(
    icon: icon,
    title: title,
    subtitle: _policyLabel(value),
    showChevron: true,
    onTap: () async {
      final picked = await showChoiceSheet<MediaDownloadPolicy>(
        context,
        title: 'Download $title automatically',
        options: [
          for (final p in MediaDownloadPolicy.values) (p, _policyLabel(p)),
        ],
        selected: value,
      );
      if (picked != null) await actions.setMediaPolicy(kind, picked.value);
    },
  );

  static String _policyLabel(MediaDownloadPolicy p) => switch (p) {
    MediaDownloadPolicy.never => 'Never',
    MediaDownloadPolicy.wifi => 'On Wi-Fi only',
    MediaDownloadPolicy.always => 'On Wi-Fi and mobile data',
  };
}
