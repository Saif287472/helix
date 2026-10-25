import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/privacy_providers.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/features/settings/application/sound_packs.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Settings > Notifications, drawn by `orbit_ui`'s
/// [orbit.NotificationsScreen].
///
/// A notification only ever says that something arrived. Its text is never
/// sent through the push service, so the message preview switch controls what
/// this phone reads out of its own database - and is off by default. The
/// ringtone row opens [RingtonesPage] and says what the next call rings with;
/// it is hidden on a platform that rings a call through the app rather than
/// through a notification channel, where the page could change nothing.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(settingsActionsProvider);
    final muted = ref.watch(mutedLinesProvider);

    return orbit.NotificationsScreen(
      model: orbit.NotificationsModel(
        osOff: ref.watch(notificationPermissionProvider).value == false,
        mutedLoading: muted.isLoading && !muted.hasValue,
        mutedFailed: muted.hasError && !muted.hasValue,
        showRingtone: ref.watch(canChooseRingtoneProvider),
        ringtone: ref.watch(ringtoneLabelProvider),
        messages: ref.watch(notifyMessagesProvider).value ?? true,
        groups: ref.watch(notifyGroupsProvider).value ?? true,
        calls: ref.watch(notifyCallsProvider).value ?? true,
        sound: ref.watch(notifySoundProvider).value ?? true,
        vibrate: ref.watch(notifyVibrateProvider).value ?? true,
        previews: ref.watch(notificationPreviewsProvider).value ?? true,
        muted: [
          for (final (chat, label) in muted.value ?? const <Never>[])
            orbit.MutedChatItem(
              id: chat.id,
              title: chat.title,
              avatar: orbit.HelixAvatarModel(
                name: chat.title,
                colorIndex: orbit.HelixAvatarModel.colorIndexFor(chat.id),
              ),
              label: label,
            ),
        ],
        previewName: ref.watch(privacyViewerNameProvider).value ?? 'Someone',
        previewText: 'See you at six?',
        dateLabel: ref.watch(lockScreenDateProvider),
      ),
      actions: orbit.NotificationsActions(
        onChanged: (key, on) {
          switch (key) {
            case 'messages':
              actions.setNotifyMessages(on);
            case 'groups':
              actions.setNotifyGroups(on);
            case 'calls':
              actions.setNotifyCalls(on);
            case 'sound':
              actions.setNotifySound(on);
            case 'vibrate':
              actions.setNotifyVibrate(on);
            case 'previews':
              actions.setNotificationPreviews(on);
          }
        },
        onOpenSystemSettings: ref
            .read(notificationPermissionProvider.notifier)
            .request,
        onUnmute: ref.read(mutedActionsProvider).unmute,
        onOpenRingtones: () => context.push(RoutePaths.ringtones),
      ),
    );
  }
}
