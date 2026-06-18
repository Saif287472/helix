// lib/app.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:helix_domain/core/constants.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix/main.dart' show HelixWindowListener;
import 'package:helix_platform/platform/windows_tray.dart';
import 'package:helix/providers/app_providers.dart';
import 'package:helix/ui/app_router.dart';
import 'package:helix/ui/app_theme.dart';
import 'package:helix/ui/screens/lock_screen.dart';
import 'package:helix/ui/widgets/app_logo.dart';
import 'package:helix/ui/widgets/call_overlay.dart';

class HelixApp extends ConsumerStatefulWidget {
  const HelixApp({super.key});

  @override
  ConsumerState<HelixApp> createState() => _HelixAppState();
}

class _HelixAppState extends ConsumerState<HelixApp>
    with WindowListener, WidgetsBindingObserver {
  late final MethodChannel _platformChannel;

  HelixWindowListener? _windowListener;
  final WindowsTrayService _trayService = WindowsTrayService();
  bool _shuttingDown = false;

  /// Timestamp when the app last went into the background (paused).
  DateTime? _pausedAt;

  /// Whether the lock screen is currently pushed.
  bool _lockPushed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final descriptor = ref.read(productDescriptorProvider);
    _platformChannel = MethodChannel('${descriptor.methodChannelNamespace}/foreground');

    if (isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _windowListener = HelixWindowListener(ref, context);
        windowManager.addListener(_windowListener!);
        windowManager.setPreventClose(true);
        await _trayService.init(
          displayName: descriptor.displayName,
          onOpenWindow: () async {
            await windowManager.show();
            await windowManager.focus();
          },
          onToggleDiscoverability: _toggleDiscoverability,
          onExitSession: _shutdownAndExit,
          isDiscoverable: () =>
              ref.read(profileServiceProvider).profile?.discoverability ==
              DiscoverabilityState.discoverable,
        );
        if (!mounted) {
          await _trayService.dispose().catchError((_) {});
          windowManager.removeListener(_windowListener!);
        }
      });
    }
    if (Platform.isAndroid) {
      _platformChannel.setMethodCallHandler((call) async {
        if (call.method == 'onTaskRemoved') {
          await _shutdownAndExit();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_windowListener != null) {
      windowManager.removeListener(_windowListener!);
    }
    if (isDesktop) {
      _trayService.dispose();
    }
    if (Platform.isAndroid) {
      _platformChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  // ── AppLifecycleState — biometric lock + idle timer ───────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(appLifecycleStateProvider.notifier).state = state;
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _handleResume();
    }
  }

  void _handleResume() {
    final profile = ref.read(profileServiceProvider).profile;
    if (profile == null || !profile.biometricLock) return;
    if (_lockPushed) return;

    final shouldLock = _shouldLockAfterIdle(profile);
    if (shouldLock) {
      _pushLockScreen();
    }
  }

  bool _shouldLockAfterIdle(Profile profile) {
    final minutes = profile.lockAfterMinutes;
    if (minutes == 0) {
      // Lock every time (immediate lock on resume).
      return true;
    }
    final paused = _pausedAt;
    if (paused == null) return false;
    return DateTime.now().difference(paused).inMinutes >= minutes;
  }

  void _pushLockScreen() {
    final nav = AppRouter.navigatorKey.currentState;
    if (nav == null) return;
    _lockPushed = true;
    nav
        .push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => const LockScreen(),
          ),
        )
        .then((_) => _lockPushed = false);
  }

  // ── Shutdown / tray ───────────────────────────────────────────────────────

  Future<void> _shutdownAndExit() async {
    if (_shuttingDown) return;
    _shuttingDown = true;

    try {
      await ref.read(discoveryCoordinatorProvider).stop().catchError((_) {});
      await ref.read(requestServiceProvider).close().catchError((_) {});
      await ref.read(messagingServiceProvider).dispose().catchError((_) {});
      await ref.read(sessionServiceProvider).stopSession().catchError((_) {});
      ref.read(sessionStateProvider.notifier).stopSession();
    } finally {
      if (isDesktop) {
        await _trayService.dispose().catchError((_) {});
        await windowManager.destroy();
      } else {
        await SystemNavigator.pop();
      }
    }
  }

  Future<void> _toggleDiscoverability() async {
    final profileService = ref.read(profileServiceProvider);
    final current = profileService.profile?.discoverability;
    if (current == null) return;

    final next = current == DiscoverabilityState.discoverable
        ? DiscoverabilityState.hidden
        : DiscoverabilityState.discoverable;
    await profileService.updateDiscoverability(next);
    await ref
        .read(discoveryCoordinatorProvider)
        .updateDiscoverability(next == DiscoverabilityState.discoverable);
    await _trayService.updateDiscoverabilityStatus(
      next == DiscoverabilityState.discoverable,
    );
  }

  // ── WindowListener stubs ──────────────────────────────────────────────────

  @override
  void onWindowClose() {}

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final initAsync = ref.watch(appInitProvider);

    return initAsync.when(
      loading: () => const _SplashScreen(),
      error: (err, _) => _ErrorApp(message: err.toString()),
      data: (_) => _buildApp(context),
    );
  }

  Widget _buildApp(BuildContext context) {
    if (Platform.isAndroid) {
      final profileAsync = ref.watch(profileProvider);
      final screenshotProtect = profileAsync.maybeWhen(
        data: (p) => p.screenshotProtect,
        orElse: () => true,
      );
      if (screenshotProtect) {
        SystemChrome.setSystemUIChangeCallback((_) async {});
      }
    }

    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.value;
    final themeMode = profileAsync.maybeWhen(
      data: (p) => _resolveThemeMode(p.themeMode),
      orElse: () => ThemeMode.system,
    );

    final isFirstRun = ref.read(profileServiceProvider).isFirstRun;
    final initialRoute = isFirstRun ? AppRoutes.setup : AppRoutes.home;

    return MaterialApp(
      title: 'Helix',
      navigatorKey: AppRouter.navigatorKey,
      theme: HelixTheme.light(accentColor: profile?.accentColor ?? 'teal'),
      darkTheme: HelixTheme.dark(
        accentColor: profile?.accentColor ?? 'teal',
        amoled: profile?.amoledDark ?? false,
      ),
      highContrastTheme: HelixTheme.light(
        accentColor: profile?.accentColor ?? 'teal',
        highContrast: true,
      ),
      highContrastDarkTheme: HelixTheme.dark(
        accentColor: profile?.accentColor ?? 'teal',
        amoled: profile?.amoledDark ?? false,
        highContrast: true,
      ),
      themeMode: themeMode,
      onGenerateRoute: AppRouter.generateRoute,
      initialRoute: initialRoute,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Overlay(
        initialEntries: [OverlayEntry(builder: (_) => CallOverlay(child: child))],
      ),
    );
  }

  ThemeMode _resolveThemeMode(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Splash / loading screen shown while appInitProvider is in-flight
// ─────────────────────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLogo(size: 72),
              SizedBox(height: 20),
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Starting Helix…'),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error screen shown when appInitProvider throws
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorApp extends StatelessWidget {
  const _ErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Helix failed to start',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
