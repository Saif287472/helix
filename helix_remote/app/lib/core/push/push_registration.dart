import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/push/account_badges.dart';
import 'package:helix_remote/core/push/push_background.dart';
import 'package:helix_remote/core/push/push_token_source.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart'
    show FileDeviceSettingsStore;
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// Sends a push token to the server for the engine that is running now.
typedef PushRegistrar = Future<void> Function(String token);

/// Keeps the server's push token for this device current.
///
/// The token has to be registered by an engine that is signed in. Before
/// 2026-10-09 the app tried once, at launch, which on a fresh install was
/// before sign-up: nothing woke the phone until the next cold start. Now the
/// token goes up every time an engine reaches running (a signed-in launch,
/// sign-up, sign-in, linking, a new server), and the current and rotated token
/// go to every account signed in on this device.
final class PushRegistration {
  PushRegistration(
    this._tokens, {
    required this.current,
    this.onToken,
    this.onWake,
    this.enabled,
  });

  final PushTokens _tokens;

  /// Whether the person lets the server wake this phone (Settings >
  /// Notifications). Off, no token is sent to any account: the server has
  /// none to wake. Null means always on.
  final Future<bool> Function()? enabled;

  /// The running engine's registrar, or null when none is running.
  final PushRegistrar? Function() current;

  /// Sends the token to the accounts not on screen.
  final Future<void> Function(String token)? onToken;

  /// A wake-up arrived while the app is in front. One token serves every
  /// account here, and the one on screen reads its own messages over its
  /// socket: this is for the others ([ForegroundWakes]).
  final void Function()? onWake;

  StreamSubscription<String>? _refreshes;
  StreamSubscription<void>? _wakeUps;

  /// An engine has just reached running: send every account the current token.
  Future<void> engineRunning() async {
    if (!await _allowed()) return;
    if (!await _tokens.prepare()) return;
    _refreshes ??= _tokens.refreshes.listen((token) => unawaited(_send(token)));
    final onWake = this.onWake;
    if (onWake != null) _wakeUps ??= _tokens.wakeUps.listen((_) => onWake());
    final token = await _tokens.currentToken();
    if (token != null) await _send(token);
  }

  Future<bool> _allowed() async {
    try {
      return await enabled?.call() ?? true;
    } on Object {
      return true;
    }
  }

  Future<void> _send(String token) async {
    // A rotation that arrives while wake-ups are off is not sent either.
    if (!await _allowed()) return;
    final register = current();
    if (register != null) {
      try {
        await register(token);
      } on Object {
        // Offline, or the session just ended: the next start or rotation sends
        // it again.
      }
    }
    await onToken?.call(token);
  }

  Future<void> dispose() async {
    await _refreshes?.cancel();
    _refreshes = null;
    await _wakeUps?.cancel();
    _wakeUps = null;
  }
}

/// Runs [wake] one pass at a time: a wake-up that arrives during a pass gets
/// one more pass after it, never a second one alongside (two engines would
/// race over the same account's database).
final class ForegroundWakes {
  ForegroundWakes(this._wake);

  final Future<void> Function(String? pushToken) _wake;
  Future<void>? _running;
  bool _again = false;
  String? _pushToken;

  Future<void> wake({String? pushToken}) {
    if (pushToken != null) _pushToken = pushToken;
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop();
  }

  Future<void> _loop() async {
    try {
      do {
        _again = false;
        final pushToken = _pushToken;
        _pushToken = null;
        try {
          await _wake(pushToken);
        } on Object {
          // A failed pass is caught up by the next wake-up or by opening
          // the account.
        }
      } while (_again);
    } finally {
      _running = null;
    }
  }
}

/// Reads the mailboxes of the accounts not on screen and, when supplied,
/// registers a push token for them. Overridden in tests.
final otherAccountsPassProvider =
    Provider<Future<void> Function({String? pushToken})>(
      (ref) => ({String? pushToken}) async {
        await wakeSignedInAccounts(
          except: ref.read(activeAccountProvider)?.id,
          pushToken: pushToken,
          syncMailbox: pushToken == null,
        );
        // That pass left a new unread count for each account it read, and it
        // sends no notification: the number on an account's row is how the
        // person hears about it.
        if (ref.mounted) ref.invalidate(accountUnreadProvider);
      },
    );

final pushTokensProvider = Provider<PushTokens>((ref) => PushTokenSource());

/// Reads whether wake-ups are on. Overridden in tests.
final pushWakeupsReaderProvider = Provider<Future<bool> Function()>(
  (ref) => const FileDeviceSettingsStore().readPushWakeups,
);

/// Stops, for every account signed in here except the one on screen, the
/// server waking this phone. Overridden in tests.
final otherAccountsUnregisterProvider = Provider<Future<void> Function()>(
  (ref) =>
      () => wakeSignedInAccounts(
        except: ref.read(activeAccountProvider)?.id,
        syncMailbox: false,
        unregister: true,
      ),
);

/// Whether this build can be woken by the server at all: the control is shown
/// only where it could change something. Overridden in tests.
final pushAvailableProvider = Provider<bool>(
  (ref) => defaultTargetPlatform == TargetPlatform.android,
);

/// The "wake this phone" switch (Settings > Notifications, AUD-12j-1 / Q8).
///
/// Off, the server is told to forget this device's token - for the account on
/// screen and for every other account signed in here - so it stops waking the
/// phone; messages wait on the server until the app is opened. On, the token is
/// registered again for all of them. The phone's own notification permission is
/// a separate thing: it decides whether the platform shows what arrives.
final pushWakeupsProvider = AsyncNotifierProvider<PushWakeups, bool>(
  PushWakeups.new,
);

final class PushWakeups extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.read(pushWakeupsReaderProvider)();

  /// Turns wake-ups on or off. The choice is kept even when the server cannot
  /// be reached at the moment: an account whose call failed is reached by the
  /// next start (off: nothing is sent; on: the token goes up again).
  Future<void> set(bool on) async {
    state = AsyncData(on);
    await const FileDeviceSettingsStore().writePushWakeups(on);
    if (on) {
      await ref.read(pushRegistrationProvider).engineRunning();
      return;
    }
    final engine = ref.read(runtimeProvider).value?.engine;
    try {
      if (engine != null && engine.status == EngineStatus.running) {
        await engine.push.unregister();
      }
    } on Object {
      // Offline: the server keeps this device's token until it is told, and
      // the next change of this switch or sign-out tells it again.
    }
    try {
      await ref.read(otherAccountsUnregisterProvider)();
    } on Object {
      // The same, for the accounts that are not on screen.
    }
  }
}

/// The running engine's push registration, or null when no engine runs.
final currentPushRegistrarProvider = Provider<PushRegistrar? Function()>(
  (ref) => () {
    final engine = ref.read(runtimeProvider).value?.engine;
    if (engine == null || engine.status != EngineStatus.running) return null;
    return engine.push.register;
  },
);

/// Registers the push token whenever the engine reaches running. Read once,
/// by the app root, and kept for the whole run.
final pushRegistrationProvider = Provider<PushRegistration>((ref) {
  final pass = ref.watch(otherAccountsPassProvider);
  final wakes = ForegroundWakes((pushToken) => pass(pushToken: pushToken));
  final registration = PushRegistration(
    ref.watch(pushTokensProvider),
    enabled: ref.watch(pushWakeupsReaderProvider),
    current: ref.watch(currentPushRegistrarProvider),
    onToken: (token) => wakes.wake(pushToken: token),
    onWake: () => unawaited(wakes.wake()),
  );
  ref.onDispose(registration.dispose);
  ref.listen<AsyncValue<AppAuthState>>(authStateProvider, (_, next) {
    if (next.isLoading || next.value != AppAuthState.ready) return;
    unawaited(registration.engineRunning());
  }, fireImmediately: true);
  return registration;
});
