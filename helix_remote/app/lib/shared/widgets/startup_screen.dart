import 'package:flutter/material.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Shown while the encrypted database opens and the engine starts.
///
/// [status] is already a sentence ("Opening your chats…"), never a raw error:
/// nothing that reaches here may name a path, a server or a key.
class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key, this.status = 'Opening Helix…'});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const HelixSkeleton(
              width: 64,
              height: 64,
              radius: Radius.circular(16),
            ),
            const SizedBox(height: HelixSpace.lg),
            Semantics(
              liveRegion: true,
              child: Text(
                status,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the app could not start for a reason the person cannot fix, and
/// which is not the missing-key case ([ResetScreen] owns that).
class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.message, this.onRetry});

  /// Plain English, with any path, host or key scrubbed out before it gets
  /// here. Never an exception's `toString()`.
  final String message;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Helix Remote')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(HelixSpace.lg),
          child: HelixErrorState(message: message, onRetry: onRetry),
        ),
      ),
    );
  }
}

/// A centred, quiet indicator, used by screens that wait on the engine.
class EngineBusy extends StatelessWidget {
  const EngineBusy({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        if (label != null) ...[
          const SizedBox(height: HelixSpace.sm),
          Text(label!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}
