import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/privacy_providers.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/features/settings/presentation/choice_sheet.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Privacy.
///
/// Two kinds of setting live here and the page does not blur them. **Who can
/// see** things (last seen, online, being added to groups, being found) is the
/// server's: it applies them to everyone else, so they are loaded from it and
/// saved to it. **Read receipts, typing and the disappearing-message default**
/// are this phone's own and take effect at once. Screenshots are not a setting:
/// Helix does not block them.
class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({super.key});

  /// Turning "find me by phone number" back on needs the account's own number
  /// (the server rebuilds the entry from it and checks it against the verified
  /// one). The engine knows it on a device that registered with it; otherwise
  /// the person types it once.
  Future<void> _askForNumber(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(privacyProvider.notifier);
    while (context.mounted) {
      final text = await showHelixTextInputDialog(
        context,
        title: 'Your phone number',
        label: 'With its country code, like +88017XXXXXXXX',
        confirmLabel: 'Turn on',
      );
      if (text == null) {
        controller.cancelNumber();
        return;
      }
      if (await controller.submitNumber(text)) return;
      if (!context.mounted) return;
      showHelixSnackBar(
        context,
        'Enter the number with its country code, like +88017XXXXXXXX.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(privacyProvider.select((s) => s.needsNumber), (was, now) {
      if (now && !(was ?? false)) _askForNumber(context, ref);
    });
    final privacy = ref.watch(privacyProvider);
    final controller = ref.read(privacyProvider.notifier);
    final prefs = privacy.prefs;
    final actions = ref.read(settingsActionsProvider);
    final receipts = ref.watch(readReceiptsProvider).value ?? true;
    final typing = ref.watch(typingIndicatorsProvider).value ?? true;
    final disappearing = ref.watch(defaultDisappearingProvider).value;
    final lock = ref.watch(appLockViewProvider).value ?? const AppLockView();

    return HelixSettingsScaffold(
      title: 'Privacy',
      body: ListView(
        children: [
          if (privacy.saving) const LinearProgressIndicator(),
          if (privacy.error != null)
            InlineNotice(
              kind: InlineNoticeKind.error,
              message: privacy.error!,
              action: prefs == null
                  ? TextButton(
                      onPressed: controller.load,
                      child: const Text('Try again'),
                    )
                  : null,
            ),
          if (privacy.loading && prefs == null)
            const Padding(
              padding: EdgeInsets.all(HelixSpace.md),
              child: LinearProgressIndicator(),
            ),
          if (prefs != null) ...[
            HelixSettingsSection(
              title: 'Who can see',
              footer: 'Helix applies these on its server, to everyone else.',
              children: [
                _audienceTile(
                  context,
                  icon: Icons.schedule,
                  title: 'Last seen',
                  value: prefs.lastSeen,
                  onChanged: controller.setLastSeen,
                ),
                _audienceTile(
                  context,
                  icon: Icons.circle_outlined,
                  title: 'Online status',
                  value: prefs.online,
                  onChanged: controller.setOnline,
                ),
                _audienceTile(
                  context,
                  icon: Icons.group_add_outlined,
                  title: 'Who can add me to groups',
                  value: prefs.groupAdd,
                  onChanged: controller.setGroupAdd,
                ),
              ],
            ),
            HelixSettingsSection(
              title: 'Being found',
              footer:
                  'Without these, people can still message you if they have '
                  'your number or ~name from somewhere else.',
              children: [
                HelixSettingsSwitchTile(
                  icon: Icons.phone_outlined,
                  title: 'Find me by phone number',
                  subtitle: 'People who have your number can find you',
                  value: prefs.discoverableByPhone,
                  onChanged: controller.setDiscoverableByPhone,
                ),
                HelixSettingsSwitchTile(
                  icon: Icons.alternate_email,
                  title: 'Find me by ~name',
                  value: prefs.discoverableByName,
                  onChanged: controller.setDiscoverableByName,
                ),
              ],
            ),
          ],
          HelixSettingsSection(
            title: 'Messages',
            footer:
                'If you turn read receipts or typing indicators off, you '
                'will not see other people\'s either. Read receipts in '
                'groups and your own devices are not affected.',
            children: [
              HelixSettingsSwitchTile(
                icon: Icons.done_all,
                title: 'Read receipts',
                subtitle: 'Let people know when you have read their message',
                value: receipts,
                onChanged: actions.setReadReceipts,
              ),
              HelixSettingsSwitchTile(
                icon: Icons.keyboard_outlined,
                title: 'Typing indicators',
                value: typing,
                onChanged: actions.setTypingIndicators,
              ),
              HelixSettingsTile(
                icon: Icons.timer_outlined,
                title: 'Disappearing messages',
                subtitle: 'New chats: ${disappearingLabel(disappearing)}',
                showChevron: true,
                onTap: () async {
                  final picked = await showChoiceSheet<int?>(
                    context,
                    title: 'Disappearing messages for new chats',
                    options: [
                      for (final seconds in disappearingChoices)
                        (seconds, disappearingLabel(seconds)),
                    ],
                    selected: disappearing,
                  );
                  if (picked != null) {
                    await actions.setDefaultDisappearing(picked.value);
                  }
                },
              ),
            ],
          ),
          HelixSettingsSection(
            title: 'Contacts',
            children: [
              HelixSettingsTile(
                icon: Icons.block,
                title: 'Blocked',
                subtitle: 'People who cannot message or call you',
                showChevron: true,
                onTap: () => context.push(RoutePaths.blocked),
              ),
            ],
          ),
          HelixSettingsSection(
            title: 'App lock',
            footer:
                'Asks for your fingerprint, face or phone PIN when you open '
                'Helix, and when you come back after the time you choose '
                'under "Lock again". It keeps the screen private; it does '
                'not add another key to your messages.',
            children: [
              HelixSettingsSwitchTile(
                icon: Icons.fingerprint,
                title: 'Lock Helix',
                value: lock.enabled,
                onChanged: (on) async {
                  final problem = await ref
                      .read(appLockActionsProvider)
                      .setEnabled(on);
                  if (problem != null && context.mounted) {
                    showHelixSnackBar(context, problem);
                  }
                },
              ),
              if (lock.enabled)
                HelixSettingsTile(
                  icon: Icons.lock_clock_outlined,
                  title: 'Lock again',
                  subtitle: relockLabel(lock.relockAfterSeconds),
                  showChevron: true,
                  onTap: () async {
                    final picked = await showChoiceSheet<int>(
                      context,
                      title: 'Lock again',
                      options: [
                        for (final s in relockChoices) (s, relockLabel(s)),
                      ],
                      selected: lock.relockAfterSeconds,
                    );
                    if (picked != null) {
                      await ref
                          .read(appLockActionsProvider)
                          .setRelockAfter(picked.value);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: HelixSpace.lg),
        ],
      ),
    );
  }

  Widget _audienceTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required AudienceChoice value,
    required Future<void> Function(AudienceChoice) onChanged,
  }) => HelixSettingsTile(
    icon: icon,
    title: title,
    subtitle: audienceLabel(value),
    showChevron: true,
    onTap: () async {
      final picked = await showChoiceSheet<AudienceChoice>(
        context,
        title: title,
        options: [
          for (final a in audienceChoicesFor(value)) (a, audienceLabel(a)),
        ],
        selected: value,
      );
      if (picked != null) await onChanged(picked.value);
    },
  );
}
