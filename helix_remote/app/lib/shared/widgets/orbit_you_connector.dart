import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/core/platform/qr_encoder.dart';
import 'package:helix_remote/core/platform/share_adapter.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:helix_remote/features/backup/application/backup_providers.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:helix_remote/features/profile/application/profile_providers.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:helix_remote/features/settings/application/account_providers.dart';
import 'package:helix_remote/features/settings/application/settings_providers.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote/shared/you_checkup.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// What to call the phone's own unlock: Windows Hello on a computer.
String unlockWhat() => defaultTargetPlatform == TargetPlatform.windows
    ? 'Windows Hello'
    : 'your fingerprint, face or phone PIN';

/// Connector: the You page (`orbit/contracts/you.md`), your profile as an
/// orbit, the privacy checkup, the topic tiles and the other rows, drawn by
/// `orbit_ui`'s [orbit.YouScreen]. It reads the profile, settings, devices
/// and backup features, so it lives in `shared/` like Home's connector.
class OrbitYouConnector extends ConsumerWidget {
  const OrbitYouConnector({super.key});

  static String routeOf(orbit.YouTopic topic) => switch (topic) {
    orbit.YouTopic.appearance => RoutePaths.appearance,
    orbit.YouTopic.privacy => RoutePaths.privacy,
    orbit.YouTopic.notifications => RoutePaths.notifications,
    orbit.YouTopic.chats => RoutePaths.chats,
    orbit.YouTopic.devices => RoutePaths.devices,
    orbit.YouTopic.backup => RoutePaths.backup,
    orbit.YouTopic.account => RoutePaths.account,
    orbit.YouTopic.accounts => RoutePaths.accounts,
    orbit.YouTopic.storage => RoutePaths.storage,
    orbit.YouTopic.about => RoutePaths.about,
    orbit.YouTopic.advanced => RoutePaths.advanced,
    orbit.YouTopic.profile => RoutePaths.profile,
    orbit.YouTopic.recovery => RoutePaths.backupRecovery,
    orbit.YouTopic.password => RoutePaths.changePassword,
    orbit.YouTopic.blocked => RoutePaths.blocked,
  };

  static orbit.CheckupItem _item(YouCheck c) => switch (c.key) {
    YouCheckKey.backup => orbit.CheckupItem(
      key: 'backup',
      ok: c.ok,
      icon: orbit.OrbitIcons.cloudCheck,
      title: 'Chat backup',
      okText: c.text,
      badText: c.text,
      fixLabel: 'Back up',
      opens: orbit.YouTopic.backup,
    ),
    YouCheckKey.devices => orbit.CheckupItem(
      key: 'devices',
      ok: c.ok,
      icon: orbit.OrbitIcons.devices,
      title: 'Linked devices',
      okText: c.text,
      badText: c.text,
      fixLabel: 'Review',
      opens: orbit.YouTopic.devices,
    ),
    YouCheckKey.password => orbit.CheckupItem(
      key: 'password',
      ok: c.ok,
      icon: orbit.OrbitIcons.password,
      title: 'Password',
      okText: c.text,
      badText: c.text,
      fixLabel: 'Set one',
      opens: orbit.YouTopic.password,
    ),
    YouCheckKey.recovery => orbit.CheckupItem(
      key: 'recovery',
      ok: c.ok,
      icon: orbit.OrbitIcons.key,
      title: 'Recovery backup',
      okText: c.text,
      badText: c.text,
      fixLabel: 'Fix',
      opens: orbit.YouTopic.recovery,
    ),
    YouCheckKey.lock => orbit.CheckupItem(
      key: 'lock',
      ok: c.ok,
      icon: orbit.OrbitIcons.lockSimple,
      title: 'App lock',
      okText: c.text,
      badText: c.text,
      fixLabel: 'Turn on',
    ),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final header = ref.watch(settingsHeaderProvider).value;
    final bytes = ref.watch(settingsAvatarProvider);
    final profile = ref.watch(profileProvider).value;
    final overview = ref.watch(accountOverviewProvider).value;
    final serverTitle = ref.watch(serverTitleProvider);
    final devices = ref.watch(deviceHealthProvider).value;
    final backup = ref.watch(backupSummaryProvider).value;
    final storage = ref.watch(storageSummaryProvider).value;
    final theme = ref.watch(orbitTokensProvider).meta.name;
    final receipts = ref.watch(readReceiptsProvider).value ?? true;
    final sound = ref.watch(notifySoundProvider).value ?? true;
    final textSize = ref.watch(fontScaleSettingProvider).value ?? 100;

    final name = header == null
        ? 'You'
        : header.name.isEmpty
        ? 'Add your name'
        : header.name;
    final accountId = header?.accountId ?? '';
    final count = devices?.count ?? 1;
    final lastBackup = backup?.lastBackupAt;
    // The share link is `/u/<~name>`, so there is nothing to share until the
    // account has a ~name: without one the sheet, and the code in it, is not
    // offered at all.
    final helixName = profile?.helixName;
    final share = helixName == null || helixName.isEmpty
        ? null
        : _shareCode(helixName);
    final link = share?.link;

    return orbit.YouScreen(
      model: orbit.YouModel(
        name: name,
        avatar: orbit.HelixAvatarModel(
          name: name,
          colorIndex: orbit.HelixAvatarModel.colorIndexFor(
            accountId.isEmpty ? 'helix' : accountId,
          ),
          image: bytes == null ? null : MemoryImage(bytes),
        ),
        about: header?.about ?? '',
        helixName: profile?.helixName,
        phoneMasked: profile?.phoneMasked ?? overview?.phoneMasked,
        serverName: serverTitle ?? header?.serverHost ?? '',
        deviceCount: count,
        checks: [for (final c in ref.watch(youChecksProvider)) _item(c)],
        tiles: [
          orbit.YouTile(
            topic: orbit.YouTopic.appearance,
            icon: orbit.OrbitIcons.palette,
            colour: 6,
            title: 'Appearance',
            status: theme,
          ),
          orbit.YouTile(
            topic: orbit.YouTopic.privacy,
            icon: orbit.OrbitIcons.lockSimple,
            colour: 3,
            title: 'Privacy',
            status: 'Receipts ${receipts ? 'on' : 'off'}',
          ),
          orbit.YouTile(
            topic: orbit.YouTopic.notifications,
            icon: orbit.OrbitIcons.bell,
            colour: 4,
            title: 'Notifications',
            status: 'Sound ${sound ? 'on' : 'off'}',
          ),
          orbit.YouTile(
            topic: orbit.YouTopic.chats,
            icon: orbit.OrbitIcons.chatCenteredText,
            colour: 1,
            title: 'Chats',
            status: 'Text ${fontScaleLabel(textSize).toLowerCase()}',
          ),
          orbit.YouTile(
            topic: orbit.YouTopic.devices,
            icon: orbit.OrbitIcons.devices,
            colour: 2,
            title: 'Devices',
            status: '$count linked',
          ),
          orbit.YouTile(
            topic: orbit.YouTopic.backup,
            icon: orbit.OrbitIcons.cloudArrowUp,
            colour: 0,
            title: 'Backup',
            status: lastBackup == null
                ? 'Not yet'
                : formatAgoShort(lastBackup, now),
          ),
        ],
        storageLabel: storage == null
            ? 'What Orbit keeps on this phone'
            : '${formatBytes(storage.totalBytes)} on this phone',
        versionLabel: ref.watch(aboutAppProvider).version,
        serverHost: header?.serverHost ?? '',
        unlockWhat: unlockWhat(),
        share: share,
      ),
      actions: orbit.YouActions(
        openProfile: () => context.push(RoutePaths.profile),
        openTopic: (topic) => context.push(routeOf(topic)),
        fixRecovery: () => context.push(RoutePaths.backupRecovery),
        turnOnAppLock: () => ref.read(appLockActionsProvider).setEnabled(true),
        copyShareLink: link == null
            ? null
            : () {
                unawaited(Clipboard.setData(ClipboardData(text: link)));
                orbit.showOrbitToast(context, 'Link copied');
              },
        shareLink: link == null
            ? null
            : () => unawaited(
                ref
                    .read(shareAdapterProvider)
                    .shareText(text: link, subject: 'Message me on Orbit'),
              ),
        scanCode: () => context.push(RoutePaths.scanChat),
      ),
    );
  }

  /// Your share code: the link, and the QR that carries it, so a scan of the
  /// screen is the same as a tap on the link.
  static orbit.ShareCodeModel _shareCode(String helixName) {
    final link = helixProfileLink(helixName);
    return orbit.ShareCodeModel(
      link: link,
      qrSeed: helixName,
      qr: encodeQr(link),
    );
  }
}
