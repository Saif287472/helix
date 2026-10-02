import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';

/// What the shell shows: sign-in, or the home tabs.
enum AppAuthState {
  /// Opening the database and starting the engine.
  starting,

  /// No account on this device. Sign-in.
  signedOut,

  /// Signed in; the home tabs.
  ready,

  /// The server revoked this device. Its data has been wiped and the only
  /// way forward is to sign in again.
  revoked,
}

/// The engine's status as the shell needs it.
///
/// `stopped` maps to [AppAuthState.ready]: the engine is only stopped while
/// the app is shutting down or a call is being handed over, and the database
/// is still there. `idle` is the moment before [Engine.start] has decided.
final authStateProvider = StreamProvider<AppAuthState>((ref) async* {
  final serverUrl = ref.watch(serverUrlProvider);
  if (serverUrl == null) {
    yield AppAuthState.signedOut;
    return;
  }
  final runtime = await ref.watch(runtimeProvider.future);
  final engine = runtime.engine;
  yield _authStateOf(engine.status);
  yield* engine.statuses.map(_authStateOf);
});

AppAuthState _authStateOf(EngineStatus status) => switch (status) {
  EngineStatus.idle => AppAuthState.starting,
  EngineStatus.signedOut => AppAuthState.signedOut,
  EngineStatus.running || EngineStatus.stopped => AppAuthState.ready,
  EngineStatus.revoked => AppAuthState.revoked,
};

final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => SecureKeyStore(),
);

/// Signs the device out, and forgets the server with it.
///
/// The engine's own `signOut` revokes this device on the server (best effort)
/// and **always wipes the local database**: a device that kept its keys could
/// sign itself back in with its signing key. The keystore's database key goes
/// too, because the next account on this device gets a new one.
final signOutProvider = Provider<SignOutAction>(SignOutAction.new);

final class SignOutAction {
  SignOutAction(this._ref);

  final Ref _ref;

  Future<void> call() async {
    final runtime = await _ref.read(runtimeProvider.future);
    await runtime.engine.signOut();
    await _ref.read(secureKeyStoreProvider).forget();
    await _ref.read(serverUrlStoreProvider).clear();
    // Rebuilding the runtime is what makes the wipe visible to the UI.
    _ref.invalidate(runtimeProvider);
    _ref.read(serverUrlProvider.notifier).forget();
  }
}

/// Deletes the encrypted database and the key, so a device that cannot open
/// its own data can start again. Only ever offered behind an explicit
/// confirmation, because it is not recoverable.
final destructiveResetProvider = Provider<DestructiveReset>(
  DestructiveReset.new,
);

final class DestructiveReset {
  DestructiveReset(this._ref);

  final Ref _ref;

  Future<void> call() async {
    _ref.read(serverUrlProvider.notifier).forget();
    final runtime = await _ref.read(runtimeProvider.future);
    await runtime.engine.stop();
    await runtime.db.close();
    final file = await AppPaths.databaseFile();
    if (await file.exists()) await file.delete();
    await _ref.read(secureKeyStoreProvider).forget();
    await _ref.read(serverUrlStoreProvider).clear();
    _ref.invalidate(runtimeProvider);
  }
}
