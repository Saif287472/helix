import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'pairing_code_screen.dart';
import 'scan_token_screen.dart';

/// Full connection flow, reached from the Settings tab's status card
/// instead of being shown inline. Splitting this out is what keeps the
/// Settings tab itself a short, scannable menu - the three ways to get a
/// token (scan / pairing code / manual) plus the URL and token fields are a
/// lot to land on at once for someone self-hosting for the first time.
class ConnectServerScreen extends StatelessWidget {
  const ConnectServerScreen({
    super.key,
    required this.urlController,
    required this.tokenController,
    required this.isConnected,
    required this.isConnecting,
    required this.errorMessage,
    required this.onConnect,
    required this.onDisconnect,
    required this.onOpenConnectGuide,
    required this.onBack,
  });

  final TextEditingController urlController;
  final TextEditingController tokenController;
  final bool isConnected;
  final bool isConnecting;
  final String? errorMessage;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onOpenConnectGuide;

  /// Shown as-is by the caller (not pushed via Navigator, so there's no
  /// automatic back button) rather than as a route, so the caller's other
  /// live state changes are reflected here as they happen. See
  /// SettingsTab's doc comment on onOpenConnectServer for why.
  final VoidCallback onBack;

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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: onBack,
        ),
        title: const Text('SERVER CONNECTION'),
      ),
      body: SingleChildScrollView(
        padding: HelixInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isConnected ? Icons.check_circle : Icons.cloud_off,
                  color: isConnected ? Colors.green : context.textFaint,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isConnected ? 'Connected' : 'Not connected',
                  style: TextStyle(
                    color: isConnected ? Colors.green : context.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Get connected',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('settings_scan_token_button'),
              onPressed: () => _scanToken(context),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Token from Server Terminal'),
              style: OutlinedButton.styleFrom(
                padding: HelixInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your server prints a QR code in its terminal the moment '
              'the admin token is generated - scanning it fills the '
              'field below automatically, no typing required.',
              style: TextStyle(color: context.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('settings_pairing_code_button'),
              onPressed: () => _redeemViaPairingCode(context),
              icon: const Icon(Icons.terminal),
              label: const Text('Get a Pairing Code from the Server'),
              style: OutlinedButton.styleFrom(
                padding: HelixInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Need a token without the original QR (e.g. the server is '
              'already running)? Run a command on the server to get a '
              'short one-time code instead, no restart required.',
              style: TextStyle(color: context.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: HelixInsets.symmetric(horizontal: 12),
                  child: Text(
                    'OR ENTER MANUALLY',
                    style: TextStyle(color: context.textFaint, fontSize: 11),
                  ),
                ),
                const Expanded(child: Divider()),
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
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
                backgroundColor: HelixColorTokens.cFF8A2BE2,
                foregroundColor: Colors.white,
                padding: HelixInsets.symmetric(vertical: 16),
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
              Text(
                'Disconnecting forgets the saved token on this device too.',
                style: TextStyle(color: context.textTertiary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
