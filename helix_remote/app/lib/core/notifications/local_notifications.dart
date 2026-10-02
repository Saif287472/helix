import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The local notifications the app raises.
///
/// Only ever a *wake-up*: what a notification says is that something arrived,
/// never what it said. The message text is read from the local database by the
/// conversation screen, because a push payload crosses a third-party provider
/// and every lock screen.
abstract final class LocalNotifications {
  static const _messages = AndroidNotificationChannel(
    'helix_messages',
    'Messages',
    description: 'A new message arrived.',
    importance: Importance.defaultImportance,
  );

  static FlutterLocalNotificationsPlugin? _plugin;

  /// Must run before the first frame. Safe to call more than once.
  static Future<void> init() async {
    if (_plugin != null) return;
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_messages);
    _plugin = plugin;
  }

  /// Whether the person allows notifications. False is a normal answer, not an
  /// error: the app works without them, it just does not wake up.
  static Future<bool> allowed() async {
    final android = _android();
    if (android == null) return false;
    return await android.areNotificationsEnabled() ?? false;
  }

  /// Asks for the notification permission. Android 13 and later need it;
  /// earlier versions report the existing answer.
  static Future<bool> request() async {
    final android = _android();
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  /// One notification for a run of new messages, so a busy chat does not fill
  /// the shade. It carries no sender and no text.
  static Future<void> showMessages({required int count}) async {
    final plugin = _plugin;
    if (plugin == null || count <= 0) return;
    await plugin.show(
      // One id for the whole group: a newer run replaces an older one rather
      // than stacking up.
      id: 0,
      title: count == 1 ? 'New message' : '$count new messages',
      body: 'Open Helix to read them.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'helix_messages',
          'Messages',
          channelDescription: 'A new message arrived.',
          // Silent: the shade says something arrived, and nothing more.
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          groupKey: 'helix_messages',
          onlyAlertOnce: true,
        ),
      ),
    );
  }

  /// Clears the message notification, once the app has caught up.
  static Future<void> clearMessages() async => _plugin?.cancel(id: 0);

  static AndroidFlutterLocalNotificationsPlugin? _android() => _plugin
      ?.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
}
