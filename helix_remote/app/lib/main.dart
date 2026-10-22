import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/diagnostics/anomaly_log.dart';
import 'package:helix_remote/core/calls/call_host.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/lifecycle/app_lifecycle_host.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';
import 'package:helix_remote/core/notifications/message_alerts.dart';
import 'package:helix_remote/core/notifications/notification_accounts.dart';
import 'package:helix_remote/core/push/push_background.dart';
import 'package:helix_remote/core/push/push_registration.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/core/security/app_lock.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:helix_remote/features/settings/application/media_policy_sync.dart';
import 'package:helix_remote/shared/widgets/app_link_listener.dart';
import 'package:helix_remote/shared/widgets/phone_book_sync_host.dart';
import 'package:helix_remote/shared/widgets/unconfirmed_member_host.dart';
import 'package:helix_remote/shared/widgets/app_text_scale.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The app entry point.
///
/// The order matters and is fixed:
///
/// 1. the error handler and the zone, so nothing below is unguarded;
/// 2. the Firebase background handler, which must be registered before the
///    app starts;
/// 3. notifications, then the deep link the launcher handed us;
/// 4. [ProviderScope], because every screen below it is a `ConsumerWidget`.
Future<void> main(List<String> args) async {
  FlutterError.onError = (details) {
    // The console gets the exception's type only; the anomaly log masks
    // keys, tokens and phone numbers before anything leaves the device.
    FlutterError.presentError(details);
    debugPrint('[helix] flutter error: ${details.exception.runtimeType}');
    AnomalyLog.crash(details.exception, details.stack);
  };
  await runZonedGuarded(
    () async {
      final binding = WidgetsFlutterBinding.ensureInitialized();
      // Errors no zone or framework handler sees (platform channels).
      binding.platformDispatcher.onError = (error, stack) {
        debugPrint('[helix] platform error: ${error.runtimeType}');
        AnomalyLog.crash(error, stack);
        return true;
      };

      registerPushBackgroundHandler();
      await LocalNotifications.init();
      await CallNotifications.init();
      // The themes and the chosen one are read before the first frame, so
      // no screen ever draws without its tokens.
      final themes = await loadBuiltInThemes();
      final theme =
          await const FileDeviceSettingsStore().readTheme() ?? defaultThemeId;

      // Every screen below is a ConsumerWidget, so the scope is the root.
      runApp(
        ProviderScope(
          overrides: [
            orbitThemeLibraryProvider.overrideWithValue(themes),
            initialThemeIdProvider.overrideWithValue(theme),
          ],
          child: HelixRemoteApp(initialLink: _initialLink(args)),
        ),
      );
    },
    (error, stack) {
      debugPrint('[helix] uncaught: ${error.runtimeType}');
      AnomalyLog.crash(error, stack);
    },
  );
}

/// The link the launcher gave us, if it was one.
///
/// The launcher intent reaches Flutter as the default route name, but Flutter's
/// own deeplinking is deliberately off in the manifest, so the process
/// arguments are scanned too: which argument carries the link is not
/// guaranteed.
HelixDeepLink? _initialLink(List<String> args) {
  for (final argument in args) {
    final link = HelixDeepLink.tryParse(argument);
    if (link != null) return link;
  }
  return HelixDeepLink.tryParse(
    WidgetsBinding.instance.platformDispatcher.defaultRouteName,
  );
}

/// The one [MaterialApp], with the router inside it.
class HelixRemoteApp extends ConsumerStatefulWidget {
  const HelixRemoteApp({super.key, this.initialLink});

  /// A link the app was opened with, applied once the first frame is up.
  final HelixDeepLink? initialLink;

  @override
  ConsumerState<HelixRemoteApp> createState() => _HelixRemoteAppState();
}

class _HelixRemoteAppState extends ConsumerState<HelixRemoteApp> {
  @override
  void initState() {
    super.initState();
    final link = widget.initialLink;
    if (link != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(pendingLinkProvider.notifier).set(link);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_restoreServer());
      // These stay alive for the whole run: the anomaly log, the
      // auto-download limits that follow the network, the push token (sent
      // whenever an engine reaches running) and the message notification
      // while the app is in the background.
      ref.read(anomalyLogInstallProvider);
      ref.read(wipedRuntimeResetProvider);
      ref.read(accountListUpkeepProvider);
      ref.read(notificationAccountSwitchProvider);
      ref.listenManual(mediaPolicySyncProvider, (_, _) {});
      // Listened rather than read, so they stay active whatever else happens
      // to watch the providers they follow.
      ref.listenManual(pushRegistrationProvider, (_, _) {});
      ref.listenManual(runningAppAlertsProvider, (_, _) {});
    });
  }

  /// Points the app at the account last on screen, so a signed-in device
  /// opens its chats instead of sign-in again, or at the account whose
  /// notification started the app. A device with no account - a first
  /// install, or one whose accounts were all removed - stays on Helix
  /// Global's sign-in.
  Future<void> _restoreServer() async {
    String? launched;
    try {
      launched = await ref.read(notificationLaunchAccountProvider);
    } on Object {
      // No notifications on this platform.
    }
    if (!mounted) return;
    final restored = await ref
        .read(accountsProvider.notifier)
        .restore(prefer: launched);
    if (!mounted) return;
    ref.read(sessionRestoreProvider.notifier).finish(restored: restored);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final orbit = ref.watch(orbitTokensProvider);

    // The lock lives above the navigator, so it reads the account's setting
    // through a provider rather than being handed the runtime.
    return MaterialApp.router(
      title: 'Orbit',
      debugShowCheckedModeBanner: false,
      // The theme chosen on Appearance, light or dark; there is no separate
      // high-contrast theme, so the chosen one always shows.
      theme: OrbitTheme.of(orbit),
      routerConfig: router,
      builder: (context, child) => AppLifecycleHost(
        // The call host keeps calls working under every screen and opens the
        // full-screen call; the lock lets a live call through.
        child: CallHost(
          child: PhoneBookSyncHost(
            child: AppLockGate(
              child: AppLinkListener(
                child: UnconfirmedMemberHost(
                  // The Orbit screens draw on the theme's page colour with
                  // no Scaffold of their own, as in the preview.
                  child: AppTextScale(
                    child: Material(
                      color: orbit.bg,
                      child: _AboveKeyboard(
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps every screen above the on-screen keyboard. The Orbit pages have no
/// Scaffold to do it, so the whole app is laid out in the space the keyboard
/// leaves, the way Android's `adjustResize` means; the inset is then taken
/// out of the [MediaQuery] so a page that does have a Scaffold does not lift
/// itself a second time.
class _AboveKeyboard extends StatelessWidget {
  const _AboveKeyboard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: child,
      ),
    );
  }
}
