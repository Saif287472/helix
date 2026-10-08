import 'package:flutter/material.dart';
import 'package:helix_admin/src/session/admin_session_scope.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: ConsoleCard(
                radius: 20,
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: HelixConsoleColors.accentSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: HelixConsoleColors.accentContainer,
                          ),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          size: 30,
                          color: HelixConsoleColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Semantics(
                      header: true,
                      child: const Text(
                        'Helix Admin is locked',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: HelixConsoleColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Use this device's screen lock to open the console",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: HelixConsoleColors.textMuted,
                      ),
                    ),
                    if (session.lockError != null) ...[
                      const SizedBox(height: 16),
                      ConsoleBanner(message: session.lockError!),
                    ],
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: session.busy ? null : session.unlock,
                      style: ConsoleButtons.filled,
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
          ),
        ),
      ),
    );
  }
}
