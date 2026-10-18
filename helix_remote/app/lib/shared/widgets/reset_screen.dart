import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/engine_lease.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final error = auth.error;

    void retry() {
      setState(() => _retried = error);
      ref.invalidate(runtimeProvider);
    }

    if (error is EngineAlreadyRunning) {
      // Not damage: another window (or the background wake) has the database.
      // Nothing here may offer the reset.
      return _Shell(
        title: 'Helix Remote',
        message:
            'Helix is already open in another window. Close that one, then '
            'try again.',
        action: FilledButton(onPressed: retry, child: const Text('Try again')),
      );
    }

    if (!auth.hasError || error == null) {
      // Nothing is wrong: the router sends people here only from an error, so
      // this is a stale location after a successful retry.
      return const _Shell(
        title: 'Helix Remote',
        message: 'Your local data is fine.',
        action: null,
      );
    }

    // Only these two are known to be past retrying, and known to be about the
    // key rather than about anything that happens to be wrong right now.
    final lost = error is KeyUnavailable || error is DbEncryptionException;
    if (lost) {
      return _Shell(
        title: 'Reset required',
        message: error is KeyUnavailable
            ? 'An existing database was found, but its encryption key is not '
                  'available in secure storage. A destructive reset is '
                  'required to continue.'
            : 'Your local database could not be decrypted. Helix never opens '
                  'it without its key, so a destructive reset is required to '
                  'continue.',
        action: _ConfirmReset(
          onConfirmed: () async {
            await ref.read(destructiveResetProvider)();
          },
        ),
      );
    }

    final retried = _retried != null && !identical(_retried, error);
    return _Shell(
      title: 'Helix could not start',
      message:
          'Helix could not open the data on this phone. Nothing has been '
          'deleted. Try again.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: retry, child: const Text('Try again')),
          if (retried) ...[
            const SizedBox(height: HelixSpace.lg),
            Text(
              'If Helix still cannot start, you can delete the data on this '
              'phone and sign in again. Every message and key stored here '
              'will be lost.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: HelixSpace.sm),
            _ConfirmReset(
              onConfirmed: () async {
                await ref.read(destructiveResetProvider)();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.title, required this.message, this.action});

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(HelixSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_outline, size: 48, color: scheme.error),
              const SizedBox(height: HelixSpace.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (action != null) ...[
                const SizedBox(height: HelixSpace.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The reset needs the word DELETE typed, so it cannot happen by a stray tap.
class _ConfirmReset extends StatefulWidget {
  const _ConfirmReset({required this.onConfirmed});

  final Future<void> Function() onConfirmed;

  @override
  State<_ConfirmReset> createState() => _ConfirmResetState();
}

class _ConfirmResetState extends State<_ConfirmReset> {
  static const _word = 'DELETE';

  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirmed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller.text.trim() == _word;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Type $_word to confirm',
            hintText: _word,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: HelixSpace.md),
        FilledButton(
          onPressed: ready && !_busy ? _run : null,
          child: Text(_busy ? 'Deleting…' : 'Reset Helix Remote'),
        ),
      ],
    );
  }
}
