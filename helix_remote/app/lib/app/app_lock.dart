import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// The in-app lock: the phone's own fingerprint, face or PIN prompt, shown
/// when the app opens and after it has been in the background for the
/// chosen time.
///
/// Static because the lock screen is drawn by the app shell, above the
/// bootstrap that owns the composition root. The composition root attaches
/// a settings reader once a session exists and detaches it on sign-out, so
/// onboarding is never locked.
abstract final class AppLock {
  /// True while the lock screen is covering the app.
  static final locked = ValueNotifier<bool>(false);

  /// A call is ringing or connected. Like a phone's lock screen, the lock
  /// then stays out of the call's way; it covers the app again afterwards.
  static final callInProgress = ValueNotifier<bool>(false);

  /// Replaceable in tests; the real one shows the system unlock prompt.
  @visibleForTesting
  static Future<bool> Function(String reason) authenticator = _systemPrompt;

  /// Whether the phone has a screen lock the prompt can use. Replaceable in
  /// tests.
  static Future<bool> Function() deviceSupportsLock = _deviceHasScreenLock;

  static ({bool enabled, int relockAfterSeconds})? Function()? _read;
  static bool Function()? _callActive;
  static DateTime? _backgroundedAt;
  static bool _authenticating = false;

  static void attach({
    required ({bool enabled, int relockAfterSeconds})? Function() read,
    required bool Function() callActive,
  }) {
    _read = read;
    _callActive = callActive;
  }

  static void detach() {
    _read = null;
    _callActive = null;
    _backgroundedAt = null;
    locked.value = false;
  }

  static bool get enabled => _read?.call()?.enabled ?? false;

  /// Locks now if the lock is on - on a cold start with a restored session.
  /// Never during a call: answering must not wait on an unlock prompt.
  static void lockIfEnabled() {
    if (!enabled || (_callActive?.call() ?? false)) return;
    locked.value = true;
  }

  static void onBackgrounded() {
    // The system unlock prompt itself pauses the activity; that is not the
    // user leaving the app.
    if (_authenticating || locked.value) return;
    _backgroundedAt = DateTime.now();
  }

  static void onResumed() {
    if (_authenticating) return;
    final since = _backgroundedAt;
    _backgroundedAt = null;
    final settings = _read?.call();
    if (since == null || settings == null || !settings.enabled) return;
    final away = DateTime.now().difference(since).inSeconds;
    if (away >= settings.relockAfterSeconds) lockIfEnabled();
  }

  /// Shows the unlock prompt; true when the user proved it is them.
  static Future<bool> authenticate(String reason) async {
    _authenticating = true;
    try {
      return await authenticator(reason);
    } catch (_) {
      return false;
    } finally {
      _authenticating = false;
      _backgroundedAt = null;
    }
  }

  static Future<bool> unlock(String reason) async {
    final ok = await authenticate(reason);
    if (ok) locked.value = false;
    return ok;
  }

  static Future<bool> _systemPrompt(String reason) => LocalAuthentication()
      .authenticate(localizedReason: reason, persistAcrossBackgrounding: true);

  static Future<bool> _deviceHasScreenLock() async {
    try {
      return await LocalAuthentication().isDeviceSupported();
    } catch (_) {
      return false;
    }
  }
}
