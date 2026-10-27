import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/privacy_providers.dart';
import 'package:helix_remote/features/settings/application/settings_models.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Settings > Privacy, drawn by `orbit_ui`'s [orbit.PrivacyScreen].
///
/// Two kinds of setting live here and the page does not blur them. **Who can
/// see** things (last seen, online, being added to groups, being found) is the
/// server's: it applies them to everyone else, so they are loaded from it and
/// saved to it. **Read receipts, typing and the disappearing-message default**
/// are this phone's own and take effect at once. Screenshots are not a setting:
/// Orbit does not block them.
class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({super.key});

  /// The timer segments, in seconds (null = off).
  static const timers = <String, int?>{
    'Off': null,
    '24 h': 86400,
    '7 d': 604800,
    '90 d': 7776000,
  };

  /// The "Lock again" segments, in seconds.
  static const lockAfters = <String, int>{
    'Now': 0,
    '1 min': 60,
    '5 min': 300,
    '30 min': 1800,
  };

  static String timerLabel(int? seconds) => timers.entries
      .firstWhere(
        (e) => e.value == seconds,
        orElse: () => MapEntry(disappearingLabel(seconds), seconds),
      )
      .key;

  static String lockAfterLabel(int seconds) => lockAfters.entries
      .firstWhere(
        (e) => e.value == seconds,
        orElse: () => MapEntry(relockLabel(seconds), seconds),
      )
      .key;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(privacyProvider);
    final controller = ref.read(privacyProvider.notifier);
    final prefs = privacy.prefs;
    final actions = ref.read(settingsActionsProvider);
    final lockActions = ref.read(appLockActionsProvider);
    final header = ref.watch(settingsHeaderProvider).value;
    final bytes = ref.watch(settingsAvatarProvider);
    final lock = ref.watch(appLockViewProvider).value ?? const AppLockView();
    final blocked = ref.watch(blockedProvider).value ?? const [];

    final name = header == null || header.name.isEmpty ? 'You' : header.name;
    final accountId = header?.accountId ?? '';

    Future<void> audience(
      Future<void> Function(AudienceChoice) set,
      Object value,
    ) => set(value == true ? AudienceChoice.everyone : AudienceChoice.nobody);

    return orbit.PrivacyScreen(
      model: orbit.PrivacyModel(
        meName: name,
        meAvatar: orbit.HelixAvatarModel(
          name: name,
          colorIndex: orbit.HelixAvatarModel.colorIndexFor(
            accountId.isEmpty ? 'helix' : accountId,
          ),
          image: bytes == null ? null : MemoryImage(bytes),
        ),
        server: prefs != null
            ? orbit.PrivacyServerStatus.ready
            : privacy.loading
            ? orbit.PrivacyServerStatus.loading
            : orbit.PrivacyServerStatus.failed,
        saving: privacy.saving,
        error: privacy.error,
        contacts: {
          if (prefs?.lastSeen == AudienceChoice.contacts) 'lastSeen',
          if (prefs?.online == AudienceChoice.contacts) 'online',
          if (prefs?.groupAdd == AudienceChoice.contacts) 'groups',
        },
        viewerName: ref.watch(privacyViewerNameProvider).value ?? 'Someone',
        lastSeenEveryone: prefs?.lastSeen != AudienceChoice.nobody,
        onlineEveryone: prefs?.online != AudienceChoice.nobody,
        groupsEveryone: prefs?.groupAdd != AudienceChoice.nobody,
        receipts: ref.watch(readReceiptsProvider).value ?? true,
        typing: ref.watch(typingIndicatorsProvider).value ?? true,
        silenceUnknownCalls:
            ref.watch(silenceUnknownCallersProvider).value ?? false,
        timerLabel: timerLabel(ref.watch(defaultDisappearingProvider).value),
        byNumber: prefs?.discoverableByPhone ?? true,
        byName: prefs?.discoverableByName ?? true,
        lockOn: lock.enabled,
        lockAfter: lockAfterLabel(lock.relockAfterSeconds),
        lockSub: defaultTargetPlatform == TargetPlatform.windows
            ? 'Windows Hello to open Orbit'
            : 'Fingerprint, face or phone PIN to open Orbit',
        blockedCount: blocked.length,
        blockedAvatar: blocked.isEmpty
            ? null
            : orbit.HelixAvatarModel(
                name: blocked.first.name,
                colorIndex: orbit.HelixAvatarModel.colorIndexFor(
                  blocked.first.id,
                ),
              ),
        askNumber: privacy.needsNumber,
      ),
      actions: orbit.PrivacyActions(
        onChanged: (key, value) async {
          switch (key) {
            case 'lastSeen':
              await audience(controller.setLastSeen, value);
            case 'online':
              await audience(controller.setOnline, value);
            case 'groups':
              await audience(controller.setGroupAdd, value);
            case 'receipts':
              await actions.setReadReceipts(value as bool);
            case 'typing':
              await actions.setTypingIndicators(value as bool);
            case 'silenceCalls':
              await actions.setSilenceUnknownCallers(value as bool);
            case 'timer':
              await actions.setDefaultDisappearing(timers[value]);
            case 'byNumber':
              await controller.setDiscoverableByPhone(value as bool);
            case 'byName':
              await controller.setDiscoverableByName(value as bool);
            case 'lock':
              return lockActions.setEnabled(value as bool);
            case 'lockAfter':
              final seconds = lockAfters[value];
              if (seconds != null) await lockActions.setRelockAfter(seconds);
          }
          return null;
        },
        onOpenBlocked: () => context.push(RoutePaths.blocked),
        onPhoneNumber: controller.submitNumber,
        onCancelNumber: controller.cancelNumber,
        onRetry: controller.load,
      ),
    );
  }
}
