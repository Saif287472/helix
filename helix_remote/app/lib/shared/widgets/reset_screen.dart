import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/engine_lease.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Shown when the app cannot open its own data.
///
/// Opening the database can fail in ways that are not the same kind of thing,
/// and the difference decides what this screen may offer:
///
/// - **The key is gone or wrong** ([KeyUnavailable], [DbEncryptionException]).
///   The file exists but cannot be decrypted — a restore onto new hardware, a
///   plaintext file, a wrong key, a damaged file (SQLCipher reports those the
///   same way). Retrying cannot help, ever. The only way forward is
///   destructive: delete the database and the key, then sign in again.
/// - **Another window has it** ([EngineAlreadyRunning]). Nothing is damaged;
///   the other window (or the background wake) holds the lease. Close that one
///   and try again. The data is never at risk here.
/// - **Anything else.** A file that could not be locked, a platform channel
///   that was not ready, a schema step that would not run. We cannot say what
///   is wrong, and most of it passes. So this screen says *that* Helix could
///   not start and nothing more — it never claims the data could not be
///   decrypted, which would be a guess — and it does not offer to delete
///   anything until a retry has failed as well.
///
/// That last rule is the point of the screen. A destructive, irreversible
/// action must never be one tap away because of an error that may be over in a
/// second; a person who loses their chats to a stray "try again" cannot get
/// them back.
class ResetScreen extends ConsumerStatefulWidget {
  const ResetScreen({super.key});

  @override
  ConsumerState<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends ConsumerState<ResetScreen> {
  /// The error the person was last asked to retry, if any. While the screen
  /// shows *that* error the retry has not happened yet; once it shows a
  /// different one, it did, and the failure is not passing.
  Object? _retried;

  /// "Type DELETE to confirm", as typed (spaces around it do not count).
  var _typed = '';
  var _busy = false;
  var _failed = false;

  Future<void> _reset() async {
    if (_busy || _typed.trim() != 'DELETE') return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await ref.read(destructiveResetProvider)();
    } on Object {
      // A reset that fails says so; the button comes back.
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final error = auth.error;

    void retry() {
      setState(() => _retried = error);
      ref.invalidate(runtimeProvider);
    }

    final kind = !auth.hasError || error == null
        // Nothing is wrong: the router sends people here only from an
        // error, so this is a stale location after a successful retry.
        ? orbit.ResetKind.fine
        // Not damage: another window (or the background wake) has the
        // database. Nothing here may offer the reset.
        : error is EngineAlreadyRunning
        ? orbit.ResetKind.window
        // Only these two are known to be past retrying, and known to be about
        // the key rather than about anything that happens to be wrong now.
        : error is KeyUnavailable
        ? orbit.ResetKind.keyMissing
        : error is DbEncryptionException
        ? orbit.ResetKind.cannotDecrypt
        : orbit.ResetKind.start;
    return orbit.ResetScreen(
      model: orbit.ResetModel(
        kind: kind,
        // The screen matches exactly; the app has always trimmed spaces.
        typed: _typed.trim(),
        busy: _busy,
        failed: _failed,
        // The delete is offered for an unknown failure only once a retry has
        // failed as well.
        offerReset: _retried != null && !identical(_retried, error),
      ),
      actions: orbit.ResetActions(
        onTyped: (v) => setState(() => _typed = v),
        onReset: _reset,
        onTryAgain: kind == orbit.ResetKind.fine
            ? () => ref.invalidate(runtimeProvider)
            : retry,
      ),
    );
  }
}
