import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:helix_remote/core/notifications/alert_count.dart';
import 'package:helix_remote/core/platform/app_storage.dart';

/// The local notifications the app raises.
///
/// What a notification says is read on this phone from its own decrypted
/// database, never from a push payload: a push crosses a third-party provider
/// and every lock screen, so it carries only a wake-up. Message previews are on
/// by default (Settings > Notifications), which names the sender and shows the
/// text on the shade and on a locked phone; with them off the notification says
/// only that something arrived.
abstract final class LocalNotifications {
  /// One channel per sound/vibrate combination, because on Android 8 and later
  /// a channel owns its sound and vibration: a notification cannot override
  /// them. Settings > Notifications picks which channel a message uses.
  ///
  /// High importance, and ids ending in `_2`: Android freezes a channel's
  /// importance when it is created and ignores later changes, so raising it on
  /// 2026-10-25 meant new channels. A message now peeks at the top of the
  /// screen and shows on a locked phone instead of waiting silently in the
  /// shade.
  static const _messages = AndroidNotificationChannel(
    'helix_messages_2',
    'Messages',
    description: 'A new message arrived.',
    importance: Importance.high,
  );
  static const _messagesSilent = AndroidNotificationChannel(
    'helix_messages_2_silent',
    'Messages (silent)',
    description: 'A new message arrived, without sound or vibration.',
    importance: Importance.high,
    playSound: false,
    enableVibration: false,
  );
  static const _messagesSoundOnly = AndroidNotificationChannel(
    'helix_messages_2_sound',
    'Messages (sound only)',
    description: 'A new message arrived, with sound but no vibration.',
    importance: Importance.high,
    enableVibration: false,
  );
  static const _messagesVibrateOnly = AndroidNotificationChannel(
    'helix_messages_2_vibrate',
    'Messages (vibrate only)',
    description: 'A new message arrived, with vibration but no sound.',
    importance: Importance.high,
    playSound: false,
  );

  /// The message channels from before the 2026-10-25 importance change. Removed
  /// at start so Android's own settings show one Messages group, not two.
  static const _retiredChannels = [
    'helix_messages',
    'helix_messages_silent',
    'helix_messages_sound',
    'helix_messages_vibrate',
  ];

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
    for (final retired in _retiredChannels) {
      await android?.deleteNotificationChannel(channelId: retired);
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
  /// does not fill the shade.
  ///
  /// [sender] and [preview] are read from this phone's own decrypted copy,
  /// never from a push, and only when the person turned previews on: the title
  /// is who wrote it and the body is what they said, on the shade and on a
  /// locked phone. Without them the notification says that something arrived,
  /// and a locked phone hides its contents. A photo has a sender but no text,
  /// so it is still named.
  ///
  /// [sound] and [vibrate] pick the channel (Settings > Notifications).
  /// [accountLabel] names the account, on a device with several.
  static Future<void> showMessages({
    required String account,
    required int count,
    bool sound = true,
    bool vibrate = true,
    String? sender,
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
    final presentation = messagesPresentation(
      count: count,
      sender: sender,
      preview: preview,
    );
    await plugin.show(
      // One id per account: a newer run replaces an older one rather than
      // stacking up.
      id: messagesIdFor(account),
      title: presentation.title,
      body: presentation.body,
      notificationDetails: NotificationDetails(
        android: messageDetails(
          channel,
          revealed: presentation.revealed,
          accountLabel: accountLabel,
        ),
      ),
      payload: NotificationPayload.encode({
        NotificationPayload.account: account,
      }),
    );
  }

  /// How a message notification is drawn. No `onlyAlertOnce`: each new
  /// message has to alert again, not quietly rewrite the line above it
  /// (AUD-14g-2).
  @visibleForTesting
  static AndroidNotificationDetails messageDetails(
    AndroidNotificationChannel channel, {
    required bool revealed,
    String? accountLabel,
  }) => AndroidNotificationDetails(
    channel.id,
    channel.name,
    channelDescription: channel.description,
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
    onlyAlertOnce: false,
    // Public is what lets a locked phone show the words; with previews off
    // the notification stays private, so the lock screen reveals that
    // something arrived and nothing more.
    visibility: revealed
        ? NotificationVisibility.public
        : NotificationVisibility.private,
    groupKey: 'helix_messages',
    subText: accountLabel,
  );

  /// What [showMessages] says, apart from the plugin: [revealed] is whether the
  /// title and body may appear on a locked phone.
  static ({String title, String body, bool revealed}) messagesPresentation({
    required int count,
    String? sender,
    String? preview,
  }) {
    // The person turned previews on if there is a name or a text to show: a
    // photo has a name but no text, and is still who wrote, not "New message".
    final revealed = sender != null || preview != null;
    return (
      title: switch ((count, sender)) {
        (1, final name?) => name,
        (1, _) => 'New message',
        _ => '$count new messages',
      },
      body: preview ?? 'Open Orbit to read them.',
      revealed: revealed,
    );
  }

  /// Clears [account]'s message notification, once the app has caught up. The
  /// next one counts from one again.
  static Future<void> clearMessages(String account) async {
    await _plugin?.cancel(id: messagesIdFor(account));
    await const AlertCountStore().reset(account);
  }

  /// What the shade holds, and how to take an entry out of it. Replaced in
  /// tests.
  @visibleForTesting
  static NotificationShade? shadeOverride;

  /// Takes everything [account] has in the shade away: its message
  /// notification, and whatever call entry (incoming or missed) names it in
  /// its payload. Called when the account is removed from this phone, whose
  /// wipe leaves nothing for a leftover notification to open, and which would
  /// otherwise keep showing the last message's words (AUD-14g-3).
  static Future<void> forgetAccount(String account) async {
    final plugin = _plugin;
    final shade =
        shadeOverride ?? (plugin == null ? null : _PluginShade(plugin));
    try {
      if (shade != null) {
        await shade.cancel(messagesIdFor(account));
        for (final entry in await shade.active()) {
          if (NotificationPayload.accountOf(entry.payload) == account) {
            await shade.cancel(entry.id);
          }
        }
      }
    } on Object {
      // No notifications on this platform, or the shade cannot be read: the
      // account is gone either way.
    }
    await const AlertCountStore().reset(account);
  }

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

/// A notification in the shade: its id and payload.
typedef ShadeEntry = ({int id, String? payload});

/// The part of the plugin that [LocalNotifications.forgetAccount] needs.
abstract interface class NotificationShade {
  Future<List<ShadeEntry>> active();
  Future<void> cancel(int id);
}

final class _PluginShade implements NotificationShade {
  _PluginShade(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<List<ShadeEntry>> active() async => [
    for (final n in await _plugin.getActiveNotifications())
      if (n.id != null) (id: n.id!, payload: n.payload),
  ];

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
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
