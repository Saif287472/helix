import 'package:flutter/material.dart';
import 'connect_server_screen.dart';
import '../widgets/settings_group_card.dart';

/// App-level preferences plus a status card that hands off to
/// [ConnectServerScreen] for the actual connection flow. Kept deliberately
/// short and grouped - the connection mechanics (scan/pairing/manual entry,
/// URL, token) live on their own screen so a first-time self-hoster isn't
/// handed a wall of buttons and fields the moment they open Settings.
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

  void _openConnectServer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => ConnectServerScreen(
          urlController: urlController,
          tokenController: tokenController,
          isConnected: isConnected,
          isConnecting: isConnecting,
          errorMessage: errorMessage,
          onConnect: onConnect,
          onDisconnect: onDisconnect,
          // Pop this pushed screen first so the guide tab it switches to
          // underneath is actually visible, instead of staying hidden
          // behind this route.
          onOpenConnectGuide: () {
            Navigator.of(routeContext).pop();
            onOpenConnectGuide();
          },
        ),
      ),
    );
  }

  String get _connectedHost {
    final url = urlController.text.trim();
    if (url.isEmpty) return '';
    return Uri.tryParse(url)?.host ?? url;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _ConnectionStatusCard(
            key: const Key('settings_connection_status_card'),
            isConnected: isConnected,
            host: _connectedHost,
            onTap: () => _openConnectServer(context),
            onDisconnect: onDisconnect,
          ),
          const SizedBox(height: 20),
          SettingsSectionCard(
            title: 'Preferences',
            rows: [
              SettingsRow(
                icon: Icons.dark_mode,
                iconColor: const Color(0xFF6D6AAE),
                title: 'Dark Mode',
                subtitle: 'Toggle between dark and light theme',
                onTap: () => onDarkModeChanged(!isDarkMode),
                trailing: Switch(
                  value: isDarkMode,
                  onChanged: onDarkModeChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SettingsSectionCard(
            title: 'Security',
            rows: [
              SettingsRow(
                key: const Key('settings_app_lock_row'),
                icon: Icons.fingerprint,
                iconColor: const Color(0xFF11A37F),
                title: 'App Lock',
                subtitle:
                    'Require your device unlock to open Helix Admin. '
                    'Optional - recommended if this device is shared.',
                onTap: onAppLockChanged == null
                    ? null
                    : () => onAppLockChanged!(!appLockEnabled),
                trailing: Switch(
                  key: const Key('settings_app_lock_switch'),
                  value: appLockEnabled,
                  onChanged: onAppLockChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SettingsSectionCard(
            title: 'Help',
            rows: [
              SettingsRow(
                icon: Icons.menu_book,
                iconColor: const Color(0xFF4F46E5),
                title: 'Self-Hosting Guide',
                subtitle: 'Setup walkthrough and connection help',
                onTap: onOpenConnectGuide,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({
    super.key,
    required this.isConnected,
    required this.host,
    required this.onTap,
    required this.onDisconnect,
  });

  final bool isConnected;
  final String host;
  final VoidCallback onTap;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    // The Disconnect button is a sibling of the navigate-to-connect-screen
    // InkWell below, not nested inside it - nesting two tappables invites
    // ambiguous gesture-arena resolution where a tap on the inner button
    // could also fire the outer card's onTap.
    return Material(
      color: const Color(0xFF161624),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected
                            ? const Color(0xFF2FA84F)
                            : const Color(0xFF3A3A46),
                      ),
                      child: Icon(
                        isConnected ? Icons.cloud_done : Icons.cloud_off,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnected ? 'Connected' : 'Not connected',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isConnected
                                ? host.isEmpty
                                      ? 'Tap to manage this connection'
                                      : host
                                : 'Connect your self-hosted Helix server to '
                                      'get started',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: Colors.white38),
                  ],
                ),
              ),
            ),
          ),
          if (isConnected)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Disconnect',
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off, color: Colors.white54),
              ),
            ),
        ],
      ),
    );
  }
}
