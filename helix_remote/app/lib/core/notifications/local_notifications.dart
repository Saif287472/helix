import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:helix_remote/core/platform/app_storage.dart';

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

  /// The plugin once [init] has run, for the other notification families
  /// (incoming calls) that share its one initialisation.
  static FlutterLocalNotificationsPlugin? get plugin => _plugin;

  static final StreamController<NotificationResponse> _responses =
      StreamController<NotificationResponse>.broadcast();

  /// A notification, or one of its action buttons, was tapped while the app
  /// was running (an incoming call's Answer and Decline arrive here).
  static Stream<NotificationResponse> get responses => _responses.stream;

  /// Must run before the first frame. Safe to call more than once.
  static Future<void> init() async {
    if (_plugin != null) return;
    // Notifications are Android-only here. The plugin refuses to start on
    // Windows without Windows settings (an ArgumentError that would end
    // `main` before the first frame), and every user of [plugin] already
    // treats null as "no notifications on this platform".
    if (!Platform.isAndroid) return;
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _responses.add,
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

  /// The message notification's id for [account]: one per account, so one
  /// account's run never replaces another's. The first account keeps 0, the
  /// id from before there were several.
  static int messagesIdFor(String account) => account == AppPaths.firstAccount
      ? 0
      : ('messages-$account'.hashCode & 0x7fffffff) | 1;

  /// One notification for a run of new messages of [account], so a busy chat
  /// does not fill the shade. It carries no sender and no text.
  ///
  /// [sound] and [vibrate] pick the channel (Settings > Notifications).
  /// [preview] is the text of a single new message, passed only when the
  /// person turned message previews on; otherwise the body says nothing about
  /// what arrived. [accountLabel] names the account, on a device with
  /// several.
  static Future<void> showMessages({
    required String account,
    required int count,
    bool sound = true,
    bool vibrate = true,
    String? preview,
    String? accountLabel,
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
      // One id per account: a newer run replaces an older one rather than
      // stacking up.
      id: messagesIdFor(account),
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
          subText: accountLabel,
        ),
      ),
      payload: NotificationPayload.encode({
        NotificationPayload.account: account,
      }),
    );
  }

  /// Clears [account]'s message notification, once the app has caught up.
  static Future<void> clearMessages(String account) async =>
      _plugin?.cancel(id: messagesIdFor(account));

  /// The payload of the notification that started the app, if one did.
  static Future<String?> launchPayload() async {
    final details = await _plugin?.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  static AndroidFlutterLocalNotificationsPlugin? _android() => _plugin
      ?.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
}

/// What a notification's payload carries: `key=value` fields joined by `;`.
/// Ids only (a call id, an account id), never content.
abstract final class NotificationPayload {
  static const account = 'account';
  static const callId = 'call_id';

  static String encode(Map<String, String> fields) =>
      [for (final e in fields.entries) '${e.key}=${e.value}'].join(';');

  static Map<String, String> decode(String? payload) {
    final fields = <String, String>{};
    if (payload == null) return fields;
    for (final part in payload.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final value = part.substring(eq + 1);
      if (value.isNotEmpty) fields[part.substring(0, eq)] = value;
    }
    return fields;
  }

  /// The account a notification belongs to; null for one from before there
  /// were several.
  static String? accountOf(String? payload) => decode(payload)[account];
}
