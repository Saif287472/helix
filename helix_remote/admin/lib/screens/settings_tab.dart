import 'package:flutter/material.dart';

/// Hosts the server-connection form (formerly a standalone login screen)
/// plus app-level preferences. Always reachable, even with no server
/// connected - this is where a connection is established or changed, wired
/// to update the shell's state in place rather than navigating away.
class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.isDarkMode,
    required this.onDarkModeChanged,
    required this.urlController,
    required this.tokenController,
    required this.isConnected,
    required this.isConnecting,
    required this.errorMessage,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final TextEditingController urlController;
  final TextEditingController tokenController;
  final bool isConnected;
  final bool isConnecting;
  final String? errorMessage;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Card(
        color: const Color(0xFF161624),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'App Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                title: const Text('Dark Mode'),
                subtitle: const Text('Toggle between dark and light theme'),
                value: isDarkMode,
                onChanged: onDarkModeChanged,
                secondary: const Icon(Icons.dark_mode),
              ),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Server Connection',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    isConnected ? Icons.check_circle : Icons.cloud_off,
                    color: isConnected ? Colors.green : Colors.white38,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isConnected ? 'Connected' : 'Not connected',
                    style: TextStyle(
                      color: isConnected ? Colors.green : Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('settings_url_field'),
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Backend Server URL',
                  prefixIcon: Icon(Icons.dns),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('settings_token_field'),
                controller: tokenController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Admin API Token',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                  helperText: 'Not saved between sessions - re-enter each time.',
                ),
              ),
              const SizedBox(height: 16),
              if (errorMessage != null) ...[
                Text(
                  errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFFF3366),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton.icon(
                onPressed: isConnecting ? null : onConnect,
                icon: isConnecting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.link),
                label: Text(
                  isConnecting
                      ? 'Connecting…'
                      : (isConnected ? 'Reconnect' : 'Connect'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A2BE2),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              if (isConnected) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disconnect'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
