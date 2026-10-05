import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/platform/engine_lease.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Shown when the local database cannot be opened.
///
/// There are two ways that happens, and the difference matters:
///
/// - the keystore has no key for a database that exists ([KeyUnavailable]) —
///   the file was written by an install whose keystore is gone, for instance
///   after a restore onto new hardware. Nothing can decrypt it.
/// - the key is wrong, SQLCipher is not loaded, or the file is plaintext
///   ([DbEncryptionException]). Refusing to open it is the point; the engine
///   never falls back to an unencrypted database.
///
/// Either way the only way forward is destructive: delete the database and the
/// key, then sign in again. That is why it is behind a typed confirmation and
/// says plainly what is lost.
class ResetScreen extends ConsumerWidget {
  const ResetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final recoverableKey = auth.hasError && auth.error is KeyUnavailable;

    if (auth.hasError && auth.error is EngineAlreadyRunning) {
      // Not damage: another window (or the background wake) has the database.
      // Nothing here may offer the reset.
      return _Shell(
        title: 'Helix Remote',
        message:
            'Helix is already open in another window. Close that one, then '
            'try again.',
        action: FilledButton(
          onPressed: () => ref.invalidate(runtimeProvider),
          child: const Text('Try again'),
        ),
      );
    }

    if (!auth.hasError) {
      // Nothing is wrong: the router sends people here only from an error, so
      // this is a stale location after a successful retry.
      return const _Shell(
        title: 'Helix Remote',
        message: 'Your local data is fine.',
        action: null,
      );
    }

    return _Shell(
      title: 'Reset required',
      message: recoverableKey
          ? 'An existing database was found, but its encryption key is not '
                'available in secure storage. A destructive reset is required '
                'to continue.'
          : 'Your local database could not be decrypted. Helix never opens it '
                'without its key, so a destructive reset is required to '
                'continue.',
      action: _ConfirmReset(
        onConfirmed: () async {
          await ref.read(destructiveResetProvider)();
        },
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
