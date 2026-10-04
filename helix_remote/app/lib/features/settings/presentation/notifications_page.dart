import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/privacy_providers.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Notifications.
///
/// A notification only ever says that something arrived. Its text is never
/// sent through the push service, so the message preview switch controls what
/// this phone reads out of its own database - and is off by default.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(settingsActionsProvider);
    final messages = ref.watch(notifyMessagesProvider).value ?? true;
    final groups = ref.watch(notifyGroupsProvider).value ?? true;
    final calls = ref.watch(notifyCallsProvider).value ?? true;
    final sound = ref.watch(notifySoundProvider).value ?? true;
    final vibrate = ref.watch(notifyVibrateProvider).value ?? true;
    final preview = ref.watch(notificationPreviewsProvider).value ?? false;
    final permission = ref.watch(notificationPermissionProvider);
    final muted = ref.watch(mutedChatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          if (permission.value == false)
            InlineNotice(
              kind: InlineNoticeKind.error,
              message:
                  'Notifications are turned off for Helix in your phone\'s '
                  'settings, so nothing below will make a sound.',
              action: TextButton(
                onPressed: ref
                    .read(notificationPermissionProvider.notifier)
                    .request,
                child: const Text('Allow notifications'),
              ),
            ),
          HelixSettingsSection(
            title: 'Alerts',
            footer:
                'Turning an alert off still delivers the message. It only '
                'stays quiet until you open Helix.',
            children: [
              HelixSettingsSwitchTile(
                icon: Icons.chat_bubble_outline,
                title: 'Messages',
                value: messages,
                onChanged: actions.setNotifyMessages,
              ),
              HelixSettingsSwitchTile(
                icon: Icons.group_outlined,
                title: 'Groups',
                value: groups,
                onChanged: actions.setNotifyGroups,
              ),
              HelixSettingsSwitchTile(
                icon: Icons.call_outlined,
                title: 'Calls',
                value: calls,
                onChanged: actions.setNotifyCalls,
              ),
            ],
          ),
          HelixSettingsSection(
            title: 'Sound',
            children: [
              HelixSettingsSwitchTile(
                icon: Icons.volume_up_outlined,
                title: 'Sound',
                subtitle: 'Use your phone\'s default notification sound',
                value: sound,
                onChanged: actions.setNotifySound,
              ),
              HelixSettingsSwitchTile(
                icon: Icons.vibration,
                title: 'Vibrate',
                value: vibrate,
                onChanged: actions.setNotifyVibrate,
              ),
            ],
          ),
          HelixSettingsSection(
            title: 'Lock screen',
            footer:
                'Off, a notification says "New message" and nothing more. On, '
                'this phone shows the text it has already decrypted. Helix '
                'servers and the push service never see message text either '
                'way.',
            children: [
              HelixSettingsSwitchTile(
                icon: Icons.visibility_outlined,
                title: 'Show message previews',
                value: preview,
                onChanged: actions.setNotificationPreviews,
              ),
            ],
          ),
          HelixSettingsSection(
            title: 'Muted chats',
            footer:
                'Mute or unmute a single chat from the chat itself. The ones '
                'muted right now are listed here.',
            children: [
              switch (muted) {
                AsyncData(:final value) when value.isEmpty =>
                  const HelixSettingsTile(
                    icon: Icons.notifications_active_outlined,
                    title: 'No muted chats',
                  ),
                AsyncData(:final value) => Column(
                  children: [
                    for (final chat in value)
                      HelixSettingsTile(
                        icon: Icons.notifications_off_outlined,
                        title: chat.title,
                        subtitle: chat.until == null
                            ? 'Muted'
                            : 'Muted for now',
                        trailing: TextButton(
                          onPressed: () =>
                              ref.read(mutedActionsProvider).unmute(chat.id),
                          child: const Text('Unmute'),
                        ),
                      ),
                  ],
                ),
                AsyncError() => const HelixSettingsTile(
                  icon: Icons.error_outline,
                  title: 'Muted chats could not be loaded',
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(HelixSpace.md),
                  child: LinearProgressIndicator(),
                ),
              },
            ],
          ),
          const SizedBox(height: HelixSpace.lg),
        ],
      ),
    );
  }
}
