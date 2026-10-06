import 'package:flutter/material.dart';
import 'package:helix_admin/src/session/admin_session_scope.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Shown when App lock is on: the device's own unlock (biometrics, PIN,
/// pattern or password) opens the saved session.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AdminSessionScope.read(context).unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = AdminSessionScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(HelixSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: scheme.primary),
              const SizedBox(height: HelixSpace.md),
              Text(
                'Helix Admin is locked',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: HelixSpace.lg),
              if (session.lockError != null) ...[
                Text(
                  session.lockError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
                const SizedBox(height: HelixSpace.md),
              ],
              FilledButton.icon(
                onPressed: session.busy ? null : session.unlock,
                icon: session.busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open),
                label: Text(session.busy ? 'Unlocking…' : 'Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
