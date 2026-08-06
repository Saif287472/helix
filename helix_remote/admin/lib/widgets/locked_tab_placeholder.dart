import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shown in place of a server-dependent tab (Dashboard, Configurations, Log
/// Tailing, Maintenance & Backups) when no server is connected yet. The
/// Self-Hosting Guide and Settings tabs are never gated behind this - they
/// must stay reachable with no server connected.
class LockedTabPlaceholder extends StatelessWidget {
  const LockedTabPlaceholder({
    super.key,
    required this.onGoToSettings,
    this.message = 'Connect a server to see this tab.',
  });

  final VoidCallback onGoToSettings;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: HelixInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: context.textFaint),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onGoToSettings,
                icon: const Icon(Icons.tune),
                label: const Text('Connect a server first'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HelixColorTokens.cFF8A2BE2,
                  foregroundColor: Colors.white,
                  padding: HelixInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
