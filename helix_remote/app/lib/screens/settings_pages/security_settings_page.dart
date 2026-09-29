import 'package:flutter/material.dart';
import 'package:helix_remote/app/app_lock.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/settings_pages/settings_page_kit.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// App lock and locked chats.
class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key, required this.messagingService});

  final RemoteMessagingService messagingService;

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  bool _busy = false;

  static const _relockOptions = [
    SettingsOption(0, 'Immediately'),
    SettingsOption(60, 'After 1 minute'),
    SettingsOption(300, 'After 5 minutes'),
    SettingsOption(900, 'After 15 minutes'),
  ];

  static String relockLabel(int seconds) => _relockOptions
      .firstWhere(
        (o) => o.value == seconds,
        orElse: () => SettingsOption(seconds, 'After $seconds seconds'),
      )
      .label;

  RemoteAppLockSettings get _lock =>
      widget.messagingService.db.getAppLockSettings();

  void _save({bool? enabled, int? relockAfterSeconds}) {
    final current = _lock;
    widget.messagingService.db.setAppLockSettings(
      RemoteAppLockSettings(
        enabled: enabled ?? current.enabled,
        relockAfterSeconds: relockAfterSeconds ?? current.relockAfterSeconds,
        useBiometric: true,
        pinVerifier: current.pinVerifier,
        recoveryBehavior: current.recoveryBehavior,
      ),
    );
  }

  /// Turning the lock on or off both require proving it is you: on, so a
  /// phone without a screen lock can't lock itself out; off, so someone
  /// holding an unlocked phone can't simply switch it off.
  Future<void> _toggleLock(bool enable) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (enable && !await AppLock.deviceSupportsLock()) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              "Set up a screen lock (PIN, pattern, fingerprint or face) in your phone's settings first.",
            ),
          ),
        );
        return;
      }
      final reason = 'Unlock Helix Remote';
      if (!await AppLock.authenticate(reason)) return;
      _save(enabled: enable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickRelock() async {
    final current = _lock.relockAfterSeconds;
    final picked = await pickSettingsOption(
      context,
      title: 'Lock the app',
      current: current,
      options: _relockOptions,
    );
    if (picked == null || picked == current) return;
    _save(relockAfterSeconds: picked);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final lock = _lock;
    final db = widget.messagingService.db;
    final lockedChats = db.getLockedConversations();
    return SettingsPage(
      title: 'Security',
      children: [
        SettingsSection(
          title: 'App lock',
          footer:
              'Uses your phone\'s own fingerprint, face or PIN. Incoming calls '
              'still ring while the app is locked, and it never locks in the '
              'middle of a call.',
          children: [
            SettingsSwitchTile(
              icon: Icons.lock_outline,
              color: HelixColorTokens.cFF7C3AED,
              title: 'Lock Helix Remote',
              subtitle: lock.enabled
                  ? 'Unlock needed to open the app'
                  : 'Anyone with your phone can open the app',
              value: lock.enabled,
              onChanged: _busy ? null : _toggleLock,
            ),
            if (lock.enabled)
              SettingsTile(
                icon: Icons.timer_outlined,
                color: HelixColorTokens.cFF5B6EE1,
                title: 'Lock the app',
                value: relockLabel(lock.relockAfterSeconds),
                onTap: _busy ? null : _pickRelock,
              ),
          ],
        ),
        SettingsSection(
          title: 'Locked chats',
          footer:
              'Lock a chat from its own menu. Locked chats never show message '
              'previews in notifications.',
          children: [
            if (lockedChats.isEmpty)
              const SettingsTile(
                icon: Icons.lock_open_outlined,
                color: HelixColorTokens.cFF14B8A6,
                title: 'No locked chats',
              )
            else
              for (final chat in lockedChats)
                SettingsTile(
                  icon: Icons.lock_person_outlined,
                  color: HelixColorTokens.cFF7C3AED,
                  title: chat.title.isEmpty ? chat.conversationId : chat.title,
                  trailing: TextButton(
                    onPressed: () {
                      db.setConversationLocked(
                        chat.conversationId,
                        locked: false,
                        hidden: false,
                      );
                      setState(() {});
                    },
                    child: const Text('Unlock'),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
