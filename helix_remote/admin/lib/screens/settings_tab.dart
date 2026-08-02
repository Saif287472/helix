import 'package:flutter/material.dart';
import 'pairing_code_screen.dart';
import 'scan_token_screen.dart';

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
    required this.onOpenConnectGuide,
    this.appLockEnabled = false,
    this.onAppLockChanged,
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
  final VoidCallback onOpenConnectGuide;

  /// Whether a device unlock (biometrics or PIN/pattern/password) is
  /// required to open the app. Optional toggle, defaults off.
  final bool appLockEnabled;
  final ValueChanged<bool>? onAppLockChanged;

  Future<void> _scanToken(BuildContext context) async {
    final scanned = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanTokenScreen()));
    if (scanned == null || scanned.isEmpty) return;
    final cleaned = scanned.trim();
    tokenController.value = TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Token scanned. Enter your server URL below, then tap Connect.',
        ),
      ),
    );
  }

  Future<void> _redeemViaPairingCode(BuildContext context) async {
    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PairingCodeScreen(baseUrl: urlController.text.trim()),
      ),
    );
    if (token == null || token.isEmpty) return;
    tokenController.value = TextEditingValue(
      text: token,
      selection: TextSelection.collapsed(offset: token.length),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Token filled in. Tap Connect below.')),
    );
  }

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
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const Key('settings_scan_token_button'),
                onPressed: () => _scanToken(context),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan Token from Server Terminal'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your server prints a QR code in its terminal the moment '
                'the admin token is generated - scanning it fills the '
                'field below automatically, no typing required.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('settings_pairing_code_button'),
                onPressed: () => _redeemViaPairingCode(context),
                icon: const Icon(Icons.terminal),
                label: const Text('Get a Pairing Code from the Server'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Need a token without the original QR (e.g. the server is '
                'already running)? Run a command on the server to get a '
                'short one-time code instead, no restart required.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR ENTER MANUALLY',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 20),
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
                decoration: InputDecoration(
                  labelText: 'Admin API Token',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.help_outline),
                    tooltip: 'Where do I find this?',
                    onPressed: onOpenConnectGuide,
                  ),
                  border: const OutlineInputBorder(),
                  helperText:
                      'Saved securely on this device once connected - no '
                      'need to re-enter it next time.',
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
                const SizedBox(height: 6),
                const Text(
                  'Disconnecting forgets the saved token on this device too.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Security',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                key: const Key('settings_app_lock_switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('App Lock'),
                subtitle: const Text(
                  'Require your device unlock (biometrics or PIN/pattern) to '
                  'open Helix Admin. Optional - recommended if this device '
                  'is shared.',
                ),
                value: appLockEnabled,
                onChanged: onAppLockChanged,
                secondary: const Icon(Icons.fingerprint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
