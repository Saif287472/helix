import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/settings_group_card.dart';

/// App-level preferences and server status card for Helix Admin.
class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.isDarkMode,
    required this.onDarkModeChanged,
    required this.serverUrl,
    required this.onSignOut,
    required this.onOpenConnectGuide,
    this.appLockEnabled = false,
    this.onAppLockChanged,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final String serverUrl;
  final VoidCallback onSignOut;
  final VoidCallback onOpenConnectGuide;

  /// Whether a device unlock (biometrics or PIN/pattern/password) is
  /// required to open the app. Optional toggle, defaults off.
  final bool appLockEnabled;
  final ValueChanged<bool>? onAppLockChanged;

  String get _connectedHost {
    final trimmed = serverUrl.trim();
    if (trimmed.isEmpty) return 'Connected Server';
    return Uri.tryParse(trimmed)?.host ?? trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: HelixInsets.all(24),
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
            host: _connectedHost,
            onSignOut: onSignOut,
          ),
          const SizedBox(height: 20),
          SettingsSectionCard(
            title: 'Preferences',
            rows: [
              SettingsRow(
                icon: Icons.dark_mode,
                iconColor: HelixColorTokens.cFF6D6AAE,
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
                iconColor: HelixColorTokens.cFF11A37F,
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
                iconColor: HelixColorTokens.cFF4F46E5,
                title: 'Self-Hosting Guide',
                subtitle: 'Setup walkthrough and server help',
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
    required this.host,
    required this.onSignOut,
  });

  final String host;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: HelixInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: HelixColorTokens.cFF2FA84F,
              ),
              child: const Icon(
                Icons.cloud_done,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connected',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const Key('settings_sign_out_button'),
              onPressed: onSignOut,
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Sign Out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: HelixColorTokens.cFFFF3366,
                side: BorderSide(
                  color: HelixColorTokens.cFFFF3366.withValues(alpha: 0.5),
                ),
                padding: HelixInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
