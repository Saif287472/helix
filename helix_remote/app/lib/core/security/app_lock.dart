import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:local_auth/local_auth.dart';

/// The app lock: a device-authentication prompt when the app comes back.
///
/// The lock screen sits above the navigator, so unlocking does not rebuild
/// the app underneath it. It is a UI gate only - there is no extra key beyond
/// the database's SQLCipher key (plan §13, resolved).
///
/// **When it locks.**
/// - *Cold start*: once per process, when the remembered session has come up
///   (`AppAuthState.ready`) and the setting has been read, the app locks if the
///   setting is on - before any content is shown (the gate covers the app
///   from the moment the session is ready until it knows). A sign-in made in
///   this process does not lock: the person has just proved who they are.
/// - *Coming back*: when the app was in the background for at least the
///   "Lock again" time. "Immediately" locks the moment it is backgrounded.
///   A clock set backwards counts as "long enough".
abstract final class AppLock {
  /// Whether the app is behind the lock right now.
  static final ValueNotifier<bool> locked = ValueNotifier(false);

  /// A live call keeps the screen awake and unlocks the UI, so somebody can
  /// put the phone down mid-call.
  static final ValueNotifier<bool> callInProgress = ValueNotifier(false);

  /// Whether the lock is wanted at all, and after how long in the background.
  static (bool enabled, int relockAfterSeconds)? Function()? _read;
  static bool Function()? _callActive;

  @visibleForTesting
  static Future<bool> Function(String reason) authenticator = _systemPrompt;

  @visibleForTesting
  static Future<bool> Function() deviceSupportsLock = _hasScreenLock;

  static DateTime? _backgroundedAt;
  static bool _authenticating = false;

  /// Set once the cold-start decision has been made (lock or not). One per
  /// process: a later sign-out and sign-in is not a cold start.
  static final ValueNotifier<bool> coldStartDone = ValueNotifier(false);

  /// The setting could not be read, so the lock stays on until the prompt is
  /// passed.
  static bool _forced = false;

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Puts every static back as at process start (tests).
  @visibleForTesting
  static void resetForTest() {
    _read = null;
    _callActive = null;
    _backgroundedAt = null;
    _authenticating = false;
    _forced = false;
    locked.value = false;
    callInProgress.value = false;
    coldStartDone.value = false;
    authenticator = _systemPrompt;
    deviceSupportsLock = _hasScreenLock;
    clock = DateTime.now;
  }

  /// Decides the cold start. [enabled] is the stored setting (never a value
  /// remembered in memory). With [unreadable] the lock is applied anyway:
  /// failing open would defeat it. Does nothing after the first call.
  static void completeColdStart({
    required bool enabled,
    bool unreadable = false,
  }) {
    if (coldStartDone.value) return;
    if ((enabled || unreadable) && !callInProgress.value) {
      _forced = unreadable;
      locked.value = true;
    }
    coldStartDone.value = true;
  }

  /// Wires the lock to the account's setting. The screen lives above the
  /// composition root, so this is the one thing it needs from it.
  static void attach({
    required (bool enabled, int relockAfterSeconds)? Function() read,
    required bool Function() callActive,
  }) {
    _read = read;
    _callActive = callActive;
  }

  static void detach() {
    _read = null;
    _callActive = null;
    _backgroundedAt = null;
    _forced = false;
    locked.value = false;
  }

  static bool get enabled => _read?.call()?.$1 ?? false;

  static int get _relockAfter => _read?.call()?.$2 ?? 60;

  /// Locks now, if the lock is on and no call is live.
  static void lockIfEnabled() {
    if (!enabled) return;
    if (_callActive?.call() ?? false) return;
    locked.value = true;
  }

  /// The pause the unlock prompt itself causes is not a backgrounding.
  static void onBackgrounded() {
    if (_authenticating) return;
    _backgroundedAt = clock();
    // "Immediately" does not wait for the person to come back: what the
    // recent-apps switcher shows is covered too.
    if (enabled && _relockAfter <= 0) lockIfEnabled();
  }

  static void onResumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null) return;
    final away = clock().difference(since);
    if (!away.isNegative && away.inSeconds < _relockAfter) return;
    lockIfEnabled();
  }

  /// Asks the device to prove it is the owner. Returns true when the lock is
  /// lifted.
  static Future<bool> unlock(String reason) async {
    if (!enabled && !_forced) {
      locked.value = false;
      return true;
    }
    _authenticating = true;
    try {
      final ok = await authenticator(reason);
      if (ok) {
        _forced = false;
        locked.value = false;
      }
      return ok;
    } on Object {
      // The platform refused or is unavailable: stay locked.
      return false;
    } finally {
      _authenticating = false;
    }
  }

  static Future<bool> _systemPrompt(String reason) async {
    try {
      return await LocalAuthentication().authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } on Object {
      return false;
    }
  }

  static Future<bool> _hasScreenLock() async {
    try {
      return await LocalAuthentication().isDeviceSupported();
    } on Object {
      return false;
    }
  }
}

/// The lock screen, stacked over the app while [AppLock.locked] is set.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Feeds the lock its setting. The gate is above the navigator, so it reads
  /// the account's preference through a provider rather than being handed the
  /// runtime; a change applies at once, not at the next launch.
  void _attach(AppLockSetting setting) {
    AppLock.attach(
      read: () => (setting.enabled, setting.relockAfterSeconds),
      // A live call keeps the phone awake, so the lock must not cover it
      // (the call host sets this from the engine's call state).
      callActive: () => AppLock.callInProgress.value,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        AppLock.onBackgrounded();
      case AppLifecycleState.resumed:
        AppLock.onResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingAsync = ref.watch(appLockSettingProvider);
    final setting = settingAsync.value;
    if (setting != null) _attach(setting);

    // The cold-start decision. It waits for the remembered session to be
    // restored: until then "signed out" only means "not looked yet".
    final restore = ref.watch(sessionRestoreProvider);
    final auth = ref.watch(authStateProvider);
    final authState = auth.isLoading ? null : auth.value;
    var covering = false;
    if (!AppLock.coldStartDone.value && restore != SessionRestore.pending) {
      if (restore == SessionRestore.none ||
          authState == AppAuthState.signedOut ||
          authState == AppAuthState.revoked) {
        // Nothing to protect yet, and the person is about to sign in.
        _decide(enabled: false);
      } else if (authState == AppAuthState.ready) {
        // The session is up: the app is covered until the setting is known.
        covering = true;
        if (setting != null) {
          _decide(enabled: setting.enabled);
        } else if (settingAsync.hasError) {
          _decide(enabled: false, unreadable: true);
        }
      }
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        AppLock.locked,
        AppLock.callInProgress,
        AppLock.coldStartDone,
      ]),
      child: widget.child,
      builder: (context, child) {
        final waiting = covering && !AppLock.coldStartDone.value;
        final locked =
            (AppLock.locked.value || waiting) && !AppLock.callInProgress.value;
        return Stack(
          children: [
            // Nothing behind the lock may be reachable or announced: it is
            // excluded from both.
            ExcludeSemantics(
              excluding: locked,
              child: ExcludeFocus(excluding: locked, child: child!),
            ),
            if (locked)
              Positioned.fill(
                child: waiting && !AppLock.locked.value
                    ? const _Cover()
                    : const _LockScreen(),
              ),
          ],
        );
      },
    );
  }

  /// Applies the decision after this frame, so no notifier changes while the
  /// tree is building. The cover keeps the app hidden until then.
  void _decide({required bool enabled, bool unreadable = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLock.completeColdStart(enabled: enabled, unreadable: unreadable);
    });
  }
}

/// Plain surface shown for the moment between "the session is up" and "the
/// lock setting has been read".
class _Cover extends StatelessWidget {
  const _Cover();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface);
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen();

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  @override
  void initState() {
    super.initState();
    // Ask straight away: the person opened the app to use it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(_unlockAction)();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: scheme.primary),
            const SizedBox(height: HelixSpace.md),
            Text(
              'Helix Remote is locked',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: HelixSpace.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HelixSpace.xl),
              child: Text(
                'Unlock with your fingerprint, face or phone PIN.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: HelixSpace.lg),
            FilledButton.icon(
              onPressed: () => ref.read(_unlockAction)(),
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}

final _unlockAction = Provider<void Function()>((ref) {
  return () async {
    await AppLock.unlock('Unlock Helix Remote');
  };
});
