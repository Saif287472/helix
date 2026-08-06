import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';

/// First-launch welcome screen. Purely informational - no URL/token fields
/// live here anymore (those moved into the Settings tab), since the app no
/// longer gates entry on having a working server connection. Shown exactly
/// once per install; the caller persists that via AdminPreferences.
class IntroScreen extends StatelessWidget {
  const IntroScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [HelixColorTokens.cFF0F0F16, HelixColorTokens.cFF1E0B36],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: HelixInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: HelixColorTokens.cFF161624.withValues(alpha: 0.9),
                child: Container(
                  padding: HelixInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.admin_panel_settings,
                        size: 64,
                        color: HelixColorTokens.cFF00E5FF,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'HELIX SERVER ADMIN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Manage a self-hosted Helix Remote server, or read '
                        'the Self-Hosting Guide to set one up first. You can '
                        'connect a server at any time from Settings.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: onGetStarted,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: HelixColorTokens.cFF8A2BE2,
                          foregroundColor: Colors.white,
                          padding: HelixInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'GET STARTED',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
