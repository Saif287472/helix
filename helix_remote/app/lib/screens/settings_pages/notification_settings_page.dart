import 'package:flutter/material.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote/screens/settings_pages/settings_page_kit.dart';
import 'package:helix_remote/services/local_notification_service.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Whether notifications can reach you at all, and which calls ring.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, required this.messagingService});

  final RemoteMessagingService messagingService;

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  /// Null while checking, or off Android.
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The user may flip the permission in system settings and come back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _checkPermission() async {
    final allowed = await LocalNotificationService.notificationsAllowed();
    if (mounted) setState(() => _allowed = allowed);
  }

  Future<void> _requestPermission() async {
    await LocalNotificationService.ensureNotificationPermission();
    await _checkPermission();
  }

  @override
  Widget build(BuildContext context) {
    final db = widget.messagingService.db;
    final allowed = _allowed;
    return SettingsPage(
      title: 'Notifications and calls',
      children: [
        if (allowed != null)
          SettingsSection(
            title: 'Notifications',
            footer: allowed
                ? 'Message notifications only say "New message": message '
                      'content is end-to-end encrypted and never sent through '
                      'the notification service.'
                : 'Android is blocking Helix notifications, so you won\'t be '
                      'told about new messages or calls while the app is '
                      'closed.',
            children: [
              SettingsTile(
                icon: allowed
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                color: allowed
                    ? HelixColorTokens.cFF2FA84F
                    : HelixColorTokens.cFFDC2626,
                title: allowed ? 'Notifications allowed' : 'Notifications off',
                subtitle: allowed ? null : 'Tap to allow notifications',
                onTap: allowed ? null : _requestPermission,
              ),
            ],
          ),
        SettingsSection(
          title: 'Calls',
          children: [
            SettingsSwitchTile(
              icon: Icons.phone_missed_outlined,
              color: HelixColorTokens.cFFF24E1E,
              title: 'Silence unknown callers',
              subtitle:
                  'Calls from people who aren\'t your contacts don\'t ring. '
                  'They still appear in your call history.',
              value: db.getSilenceUnknownCallers(),
              onChanged: (v) {
                db.setSilenceUnknownCallers(enabled: v);
                setState(() {});
              },
            ),
          ],
        ),
      ],
    );
  }
}
