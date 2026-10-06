import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/helix_runtime.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/links/pending_link.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/picker_cleanup.dart';
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
    // The engine's sign-out ends in the hard wipe (database file destroyed,
    // key and plaintext files deleted, see `HelixRuntime.hardWipe`); this
    // covers an engine that had nothing to sign out.
    await runtime.ensureWiped();
    await _ref.read(secureKeyStoreProvider).forget();
    await _ref.read(serverUrlStoreProvider).clear();
    await _wipeLeftovers();
    // Rebuilding the runtime is what makes the wipe visible to the UI.
    _ref.invalidate(runtimeProvider);
    _ref.read(serverUrlProvider.notifier).forget();
  }

  /// What the engine's wipe does not reach: the avatar picture, downloaded
  /// attachments, the file picker's temporary copies, and any link still
  /// parked for the next sign-in.
  Future<void> _wipeLeftovers() async {
    _ref.read(pendingLinkProvider.notifier).set(null);
    await AppPaths.wipeLocalFiles();
    await PickerTemporaryFiles.clear();
  }
}

/// After a revocation that wiped this device, the runtime is spent (its
/// database file is gone and its key deleted): open a new one, so the
/// sign-in that follows gets a fresh file and a fresh key.
///
/// A signed-out device is handled by [SignOutAction]; this is for the one
/// wipe nobody on this phone asked for. Read once, by the app root.
final wipedRuntimeResetProvider = Provider<void>((ref) {
  ref.listen(authStateProvider, (_, next) {
    if (next.value != AppAuthState.revoked) return;
    final runtime = ref.read(runtimeProvider).value;
    if (runtime != null && runtime.wasWiped) ref.invalidate(runtimeProvider);
  });
});

/// Deletes the encrypted database and the key, so a device that cannot open
/// its own data can start again. Only ever offered behind an explicit
/// confirmation, because it is not recoverable.
final destructiveResetProvider = Provider<DestructiveReset>(
  DestructiveReset.new,
);

final class DestructiveReset {
  DestructiveReset(this._ref);

  final Ref _ref;

  /// Completes however broken the runtime is: this is the way out of a
  /// database that will not open, so it works from the files alone. The
  /// runtime is closed first if there is one, but a runtime that failed to
  /// open (the usual reason to be here) only means there is nothing to close.
  Future<void> call() async {
    HelixRuntime? runtime;
    try {
      runtime = await _ref.read(runtimeProvider.future);
    } on Object {
      runtime = null;
    }
    if (runtime != null) {
      try {
        await runtime.engine.stop();
        await runtime.db.close();
      } on Object {
        // Closing is best effort; the files are deleted regardless.
      }
    }
    _ref.read(serverUrlProvider.notifier).forget();
    _ref.read(pendingLinkProvider.notifier).set(null);
    await AppPaths.wipeLocalFiles(includeDatabase: true);
    await PickerTemporaryFiles.clear();
    await _ref.read(secureKeyStoreProvider).forget();
    await _ref.read(serverUrlStoreProvider).clear();
    _ref.invalidate(runtimeProvider);
  }
}
