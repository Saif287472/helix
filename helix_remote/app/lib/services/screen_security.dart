import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Blocks screenshots, screen recording, and the recents-thumbnail preview
/// while a sensitive screen is in front.
///
/// The product advertises that locked chats and strict mode redact content,
/// but nothing ever set `FLAG_SECURE`, so message text was screenshot-able,
/// recordable by any app holding MediaProjection, and — the quiet one — left
/// sitting in the task-switcher thumbnail in plaintext after the user
/// switched away.
///
/// Applied per screen rather than app-wide on purpose. Ordinary screens
/// (settings, onboarding, diagnostics) stay capturable, which is what support
/// and bug reports need; only screens showing message content, backup key
/// material, or verification codes turn it on.
///
/// Nesting is reference-counted. Pushing a sensitive screen on top of another
/// and popping it must not clear the flag while the first is still visible,
/// and route transitions overlap by design — the new screen's `initState`
/// runs before the old screen's `dispose`.
class ScreenSecurity {
  ScreenSecurity._();

  static final ScreenSecurity instance = ScreenSecurity._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel(
    'com.helix.remote/screen_security',
  );

  /// Overridable so widget tests can assert the acquire/release protocol
  /// without a platform channel. Null means "use the real channel".
  @visibleForTesting
  static Future<void> Function({required bool secure})? platformOverride;

  int _holders = 0;

  /// Visible for tests: how many screens currently hold the flag.
  @visibleForTesting
  int get holderCount => _holders;

  @visibleForTesting
  void resetForTest() => _holders = 0;

  /// Marks one more screen as needing protection. The platform call is made
  /// only on the transition from zero, so repeated acquires are cheap.
  Future<void> acquire() async {
    _holders++;
    if (_holders == 1) await _apply(secure: true);
  }

  /// Releases one screen's claim. The flag is cleared only when the last
  /// holder goes away.
  Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _apply(secure: false);
  }

  Future<void> _apply({required bool secure}) async {
    final override = platformOverride;
    if (override != null) {
      await override(secure: secure);
      return;
    }
    // Android sets FLAG_SECURE; Windows sets display affinity to
    // WDA_EXCLUDEFROMCAPTURE in the runner (`windows/runner/screen_security.cpp`).
    // Both serve the same channel and method name, so this side does not care
    // which one answers. Any other platform has no handler registered, and
    // calling out would only throw MissingPluginException on every sensitive
    // screen.
    if (!Platform.isAndroid && !Platform.isWindows) return;
    try {
      await channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on PlatformException {
      // A missing handler must not take down a conversation screen. The
      // protection is best-effort at the platform boundary; failing loudly
      // here would trade a privacy nicety for an unusable app.
    } on MissingPluginException {
      // Same reasoning: unit tests and any embedding without the handler.
    }
  }
}

/// Mixin for a [State] whose screen shows content that must not be captured.
///
/// Acquires on init and releases on dispose, so the lifetime matches the
/// screen's rather than depending on every exit path remembering to clean up.
mixin SecureScreenStateMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    ScreenSecurity.instance.acquire();
  }

  @override
  void dispose() {
    ScreenSecurity.instance.release();
    super.dispose();
  }
}
