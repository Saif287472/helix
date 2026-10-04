import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The local notifications the app raises.
///
/// Only ever a *wake-up*: what a notification says is that something arrived,
/// never what it said. The message text is read from the local database by the
/// conversation screen, because a push payload crosses a third-party provider
/// and every lock screen.
abstract final class LocalNotifications {
  /// One channel per sound/vibrate combination, because on Android 8 and later
  /// a channel owns its sound and vibration: a notification cannot override
  /// them. Settings > Notifications picks which channel a message uses.
  static const _messages = AndroidNotificationChannel(
    'helix_messages',
    'Messages',
    description: 'A new message arrived.',
    importance: Importance.defaultImportance,
  );
  static const _messagesSilent = AndroidNotificationChannel(
    'helix_messages_silent',
    'Messages (silent)',
    description: 'A new message arrived, without sound or vibration.',
    importance: Importance.defaultImportance,
    playSound: false,
    enableVibration: false,
  );
  static const _messagesSoundOnly = AndroidNotificationChannel(
    'helix_messages_sound',
    'Messages (sound only)',
    description: 'A new message arrived, with sound but no vibration.',
    importance: Importance.defaultImportance,
    enableVibration: false,
  );
  static const _messagesVibrateOnly = AndroidNotificationChannel(
    'helix_messages_vibrate',
    'Messages (vibrate only)',
    description: 'A new message arrived, with vibration but no sound.',
    importance: Importance.defaultImportance,
    playSound: false,
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
    for (final channel in const [
      _messages,
      _messagesSilent,
      _messagesSoundOnly,
      _messagesVibrateOnly,
    ]) {
      await android?.createNotificationChannel(channel);
    }
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
  ///
  /// [sound] and [vibrate] pick the channel (Settings > Notifications).
  /// [preview] is the text of a single new message, passed only when the
  /// person turned message previews on; otherwise the body says nothing about
  /// what arrived.
  static Future<void> showMessages({
    required int count,
    bool sound = true,
    bool vibrate = true,
    String? preview,
  }) async {
    final plugin = _plugin;
    if (plugin == null || count <= 0) return;
    final channel = switch ((sound, vibrate)) {
      (true, true) => _messages,
      (false, false) => _messagesSilent,
      (true, false) => _messagesSoundOnly,
      (false, true) => _messagesVibrateOnly,
    };
    await plugin.show(
      // One id for the whole group: a newer run replaces an older one rather
      // than stacking up.
      id: 0,
      title: count == 1 ? 'New message' : '$count new messages',
      body: preview ?? 'Open Helix to read them.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
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
