import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/crash_reporter.dart';
import 'package:helix_remote/core/calls/call_host.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/server_policy.dart';
import 'package:helix_remote/core/lifecycle/app_lifecycle_host.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/core/notifications/call_notifications.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';
import 'package:helix_remote/core/push/push_background.dart';
import 'package:helix_remote/core/push/push_token_source.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/core/security/app_lock.dart';
import 'package:helix_remote/features/settings/application/media_policy_sync.dart';
import 'package:helix_remote/shared/widgets/app_link_listener.dart';
import 'package:helix_remote/shared/widgets/phone_book_sync_host.dart';
import 'package:helix_remote/shared/widgets/app_text_scale.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

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
    // The exception's type only: nothing here may name a message, a key, a
    // token or a full phone number.
    FlutterError.presentError(details);
    debugPrint('[helix] flutter error: ${details.exception.runtimeType}');
    CrashReporter.report(details.exception);
  };

  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      registerPushBackgroundHandler();
      await LocalNotifications.init();
      await CallNotifications.init();

      // Every screen below is a ConsumerWidget, so the scope is the root.
      runApp(
        ProviderScope(child: HelixRemoteApp(initialLink: _initialLink(args))),
      );
    },
    (error, stack) {
      debugPrint('[helix] uncaught: ${error.runtimeType}');
      CrashReporter.report(error);
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
      // Both stay alive for the whole run: crash reports (opt-in) and the
      // auto-download limits that follow the network.
      ref.read(crashReporterInstallProvider);
      ref.listenManual(mediaPolicySyncProvider, (_, _) {});
    });
  }

  /// Points the app at the remembered server, so a signed-in device opens its
  /// chats instead of sign-in again. A device with no remembered server - a
  /// first install, or one whose data was reset - stays on Helix Global.
  Future<void> _restoreServer() async {
    final saved = await ref.read(serverUrlStoreProvider).load();
    final uri = saved == null ? null : Uri.tryParse(saved);
    // A remembered address that is not https (or not an address at all) is
    // not used: the device opens on Helix Global's sign-in rather than
    // talking to it in the clear.
    final usable =
        uri != null && uri.hasScheme && ServerPolicy.check(uri) == null;
    if (usable) ref.read(serverUrlProvider.notifier).use(uri);
    if (!mounted) return;
    ref.read(sessionRestoreProvider.notifier).finish(restored: usable);
    unawaited(_startPush());
  }

  /// Registers the push token once there is a runtime. Optional throughout: a
  /// build without `google-services.json` simply never gets one.
  Future<void> _startPush() async {
    try {
      final runtime = await ref.read(runtimeProvider.future);
      await PushTokenSource().start(onToken: runtime.engine.push.register);
    } on Object {
      // No server chosen yet, or the database could not open. The router is
      // showing sign-in or the reset screen; both are correct without push.
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // The lock lives above the navigator, so it reads the account's setting
    // through a provider rather than being handed the runtime.
    return MaterialApp.router(
      title: 'Helix Remote',
      debugShowCheckedModeBanner: false,
      theme: HelixThemes.light(),
      highContrastTheme: HelixThemes.highContrastLight(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) => AppLifecycleHost(
        // The call host keeps calls working under every screen and opens the
        // full-screen call; the lock lets a live call through.
        child: CallHost(
          child: PhoneBookSyncHost(
            child: AppLockGate(
              child: AppLinkListener(
                child: AppTextScale(child: child ?? const SizedBox.shrink()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
