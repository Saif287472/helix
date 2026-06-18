// lib/main.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:helix/app.dart';
import 'package:helix_domain/core/constants.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/services/app_logger.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// main() must be sync so ensureInitialized and runApp share the same zone.
void main() {
  // ── Global error logging — must be set before ensureInitialized ─────────────
  FlutterError.onError = (details) {
    debugPrint('[Helix ERROR] ${details.exception}');
    debugPrint('[Helix STACK] ${details.stack}');
    AppLogger.instance.error('flutter', '${details.exception}', details.stack);
  };

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await AppLogger.instance.init();

      // ── Platform: Windows ─────────────────────────────────────────────────────
      if (isDesktop) {
        await windowManager.ensureInitialized();

        const windowOptions = WindowOptions(
          minimumSize: Size(480, 640),
          title: 'Helix',
          center: true,
        );

        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.show();
          await windowManager.focus();
        });
      }

      // ── Platform: Android ─────────────────────────────────────────────────────
      if (Platform.isAndroid) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }

      // ── Local notifications ───────────────────────────────────────────────────
      const androidInitSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const windowsInitSettings = WindowsInitializationSettings(
        appName: 'Helix',
        appUserModelId: kWindowsAppUserModelId,
        guid: kWindowsNotificationGuid,
      );
      const initSettings = InitializationSettings(
        android: androidInitSettings,
        windows: windowsInitSettings,
      );
      await flutterLocalNotificationsPlugin.initialize(settings: initSettings);

      // ── Run app ───────────────────────────────────────────────────────────────
      runApp(const ProviderScope(child: HelixApp()));
    },
    (error, stack) {
      debugPrint('[Helix UNCAUGHT] $error');
      debugPrint('[Helix STACK] $stack');
      AppLogger.instance.error('uncaught', '$error', stack);
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Windows close-button guard (FR-SESSION-009)
// ─────────────────────────────────────────────────────────────────────────────

/// Attach this listener to [windowManager] on Windows after [ProviderScope] is
/// set up.  It is driven by a [WidgetRef] so it can read live Riverpod state.
class HelixWindowListener extends WindowListener {
  HelixWindowListener(this._ref, this._context);

  final WidgetRef _ref;
  final BuildContext _context;

  @override
  void onWindowClose() async {
    final hasActiveSession = _ref.read(hasActiveSessionProvider);

    if (hasActiveSession && _context.mounted) {
      final confirmed = await showDialog<bool>(
        context: _context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('End session?'),
          content: const Text(
            'You have active chats or pending requests.\n'
            'Closing will disconnect all peers.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('End session and exit'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await _shutdownSession();
        await windowManager.destroy();
      }
    } else {
      await _shutdownSession();
      await windowManager.destroy();
    }
  }

  @override
  void onWindowMinimize() async {
    // Minimise to tray instead of taskbar when tray is active
    if (isDesktop) {
      await windowManager.hide();
    }
  }

  Future<void> _shutdownSession() async {
    await _ref.read(discoveryCoordinatorProvider).stop();
    await _ref.read(requestServiceProvider).close();
    await _ref.read(messagingServiceProvider).dispose();
    await _ref.read(sessionServiceProvider).stopSession();
    _ref.read(sessionStateProvider.notifier).stopSession();
  }
}
