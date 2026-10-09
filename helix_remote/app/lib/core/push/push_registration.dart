import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/push/push_token_source.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// Sends a push token to the server for the engine that is running now.
typedef PushRegistrar = Future<void> Function(String token);

/// Keeps the server's push token for this device current.
///
/// The token has to be registered by an engine that is signed in. Before
/// 2026-10-09 the app tried once, at launch, which on a fresh install was
/// before sign-up: nothing woke the phone until the next cold start. Now the
/// token goes up every time an engine reaches running (a signed-in launch,
/// sign-up, sign-in, linking, a new server), and every rotated token goes to
/// whichever engine is running when it arrives, never to a closed one.
final class PushRegistration {
  PushRegistration(this._tokens, {required this.current});

  final PushTokens _tokens;

  /// The running engine's registrar, or null when none is running.
  final PushRegistrar? Function() current;

  StreamSubscription<String>? _refreshes;

  /// An engine has just reached running: send it the current token.
  Future<void> engineRunning() async {
    if (!await _tokens.prepare()) return;
    _refreshes ??= _tokens.refreshes.listen((token) => unawaited(_send(token)));
    final token = await _tokens.currentToken();
    if (token != null) await _send(token);
  }

  Future<void> _send(String token) async {
    final register = current();
    if (register == null) return;
    try {
      await register(token);
    } on Object {
      // Offline, or the session just ended: the next start or rotation sends
      // it again.
    }
  }

  Future<void> dispose() async {
    await _refreshes?.cancel();
    _refreshes = null;
  }
}

final pushTokensProvider = Provider<PushTokens>((ref) => PushTokenSource());

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
  final registration = PushRegistration(
    ref.watch(pushTokensProvider),
    current: ref.watch(currentPushRegistrarProvider),
  );
  ref.onDispose(registration.dispose);
  ref.listen<AsyncValue<AppAuthState>>(authStateProvider, (_, next) {
    if (next.isLoading || next.value != AppAuthState.ready) return;
    unawaited(registration.engineRunning());
  }, fireImmediately: true);
  return registration;
});
