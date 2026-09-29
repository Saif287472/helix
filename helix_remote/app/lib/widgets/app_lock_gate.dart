import 'package:flutter/material.dart';
import 'package:helix_remote/app/app_lock.dart';

/// Covers the app with the lock screen while [AppLock.locked] is set, and
/// feeds app lifecycle changes into [AppLock] so it can relock after the
/// chosen time in the background.
///
/// The lock screen is stacked over [child] rather than replacing it, so the
/// navigator - and whatever screen the user was on - survives unlocking.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        AppLock.onBackgrounded();
      case AppLifecycleState.resumed:
        AppLock.onResumed();
      case _:
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLock.locked,
      builder: (context, locked, child) => Stack(
        children: [
          // Kept alive and out of reach of focus and screen readers while
          // covered.
          ExcludeSemantics(
            excluding: locked,
            child: ExcludeFocus(excluding: locked, child: child!),
          ),
          if (locked) const Positioned.fill(child: _LockScreen()),
        ],
      ),
      child: widget.child,
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    // Offer the prompt straight away rather than making the user tap first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_prompting || !mounted) return;
    setState(() => _prompting = true);
    await AppLock.unlock('Unlock Helix Remote');
    if (mounted) setState(() => _prompting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Helix Remote is locked',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Unlock with your fingerprint, face or phone PIN.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _prompting ? null : _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
