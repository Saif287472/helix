import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:helix_remote/core/notifications/local_notifications.dart';

/// What a person pressed on an incoming-call notification.
enum CallNotificationAction { accept, decline, open }

/// A press on a call notification, for the call it belongs to.
final class CallNotificationResponse {
  const CallNotificationResponse(this.callId, this.action);

  final String callId;
  final CallNotificationAction action;
}

/// The incoming-call notification: the one thing that rings the phone, takes
/// the whole screen over a locked one and carries Answer and Decline.
///
/// It names who is calling and nothing else, and only when the person turned
/// notification previews on: the caller's name is content, so with previews
/// off (the default) the text says that a call is coming and the notification
/// is `private`, which keeps even that off a locked screen. Like every
/// notification here it is built from the local database or from a pending
/// call's caller id; no push payload ever supplies text for it.
///
/// Shared by the running app (`CallRinger`) and the FCM isolate
/// (`push_background.dart`), which is why it lives in `core/`.
abstract final class CallNotifications {
  /// Rings with the phone's ringtone, like the phone app. A channel's sound
  /// cannot change once created, hence the id.
  static final _incoming = AndroidNotificationChannel(
    'helix_incoming_calls_ringtone',
    'Incoming calls',
    description: 'Rings for incoming Helix calls',
    importance: Importance.max,
    playSound: true,
    sound: const UriAndroidNotificationSound(
      'content://settings/system/ringtone',
    ),
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    enableVibration: true,
    vibrationPattern: Int64List.fromList(const [0, 800, 600, 800, 600]),
  );

  static const _missed = AndroidNotificationChannel(
    'helix_missed_calls',
    'Missed calls',
    description: 'A call that was not answered.',
    importance: Importance.defaultImportance,
  );

  static const acceptActionId = 'accept_call';
  static const declineActionId = 'decline_call';
  static const _payloadPrefix = 'call_id=';

  /// How long a call keeps ringing: the engine's ring timeout, and the
  /// server keeps a pending offer no longer.
  static const ringFor = Duration(seconds: 60);

  /// What an incoming-call notification says and who may see it, for the
  /// notification-previews setting: the caller's name and `public` only when
  /// previews are on, else "Helix" and `private`.
  static ({String title, NotificationVisibility visibility})
  incomingPresentation({
    required String callerName,
    required bool showCaller,
  }) => showCaller
      ? (title: callerName, visibility: NotificationVisibility.public)
      : (title: 'Helix', visibility: NotificationVisibility.private);

  /// A stable notification id for a call, so a re-post replaces the first.
  static int idFor(String callId) => callId.hashCode & 0x7fffffff;

  static String payloadFor(String callId) => '$_payloadPrefix$callId';

  /// The call id in a notification payload, or null when it is not a call's.
  static String? callIdOf(String? payload) {
    if (payload == null || !payload.startsWith(_payloadPrefix)) return null;
    final id = payload.substring(_payloadPrefix.length);
    return id.isEmpty ? null : id;
  }

  /// Creates the ringing channel. Called by [LocalNotifications.init]'s owner
  /// once at start-up; safe to repeat.
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    final plugin = LocalNotifications.plugin;
    final android = plugin
        ?.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_incoming);
    await android?.createNotificationChannel(_missed);
  }

  /// "Missed call from X", for a call that rang while the app was not on
  /// screen. Replaced by a later one from the same call.
  static Future<void> showMissed({
    required String callId,
    required String callerName,
    bool showCaller = false,
  }) async {
    if (!Platform.isAndroid) return;
    final plugin = LocalNotifications.plugin;
    if (plugin == null) return;
    await plugin.show(
      id: idFor('missed-$callId'),
      title: 'Missed call',
      body: showCaller ? callerName : 'Open Helix to see who called.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _missed.id,
          _missed.name,
          channelDescription: _missed.description,
          category: AndroidNotificationCategory.missedCall,
          visibility: showCaller
              ? NotificationVisibility.public
              : NotificationVisibility.private,
          autoCancel: true,
        ),
      ),
      payload: payloadFor(callId),
    );
  }

  /// Rings for [callId]. With [fullScreen] the notification takes the screen
  /// over a locked or idle phone (and needs `USE_FULL_SCREEN_INTENT`). [video]
  /// is null for a call whose offer has not been opened yet (a push woke the
  /// app): the notification then just says a call is coming.
  ///
  /// [showCaller] is the notification-previews setting: false puts "Helix" in
  /// place of the caller's name and makes the notification `private`.
  static Future<void> showIncoming({
    required String callId,
    required String callerName,
    bool? video,
    bool fullScreen = false,
    bool showCaller = false,
  }) async {
    if (!Platform.isAndroid) return;
    final plugin = LocalNotifications.plugin;
    if (plugin == null) return;
    final presentation = incomingPresentation(
      callerName: callerName,
      showCaller: showCaller,
    );
    await plugin.show(
      id: idFor(callId),
      title: presentation.title,
      body: switch (video) {
        true => 'Incoming video call',
        false => 'Incoming voice call',
        null => 'Incoming call',
      },
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _incoming.id,
          _incoming.name,
          channelDescription: _incoming.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          visibility: presentation.visibility,
          fullScreenIntent: fullScreen,
          ongoing: true,
          autoCancel: false,
          // Keep ringing until answered, declined or timed out
          // (FLAG_INSISTENT), but a re-post of the same call must not
          // restart the sound.
          additionalFlags: Int32List.fromList(const [4]),
          onlyAlertOnce: true,
          timeoutAfter: ringFor.inMilliseconds,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          subText: switch (video) {
            true => 'Helix video call',
            false => 'Helix voice call',
            null => 'Helix call',
          },
          ticker: 'Incoming call',
          // Both buttons open the app: answering needs the microphone and
          // the engine, and declining reaches the engine only there. A
          // button pressed before the app knew of the call is remembered
          // (`PendingCallDecision`) until the offer is opened.
          actions: const [
            AndroidNotificationAction(
              declineActionId,
              'Decline',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              acceptActionId,
              'Answer',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: payloadFor(callId),
    );
  }

  /// Stops ringing for [callId].
  static Future<void> cancel(String callId) async {
    if (!Platform.isAndroid) return;
    await LocalNotifications.plugin?.cancel(id: idFor(callId));
  }

  /// Presses on call notifications while the app runs; everything else
  /// (message notifications) is ignored.
  static Stream<CallNotificationResponse> get responses => LocalNotifications
      .responses
      .map((response) {
        final callId = callIdOf(response.payload);
        if (callId == null) return null;
        final action = switch (response.actionId) {
          acceptActionId => CallNotificationAction.accept,
          declineActionId => CallNotificationAction.decline,
          _ => CallNotificationAction.open,
        };
        return CallNotificationResponse(callId, action);
      })
      .where((response) => response != null)
      .cast<CallNotificationResponse>();

  /// The press that started the app, if a call notification did.
  static Future<CallNotificationResponse?> launchedBy() async {
    if (!Platform.isAndroid) return null;
    final details = await LocalNotifications.plugin
        ?.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details == null ||
        !details.didNotificationLaunchApp ||
        response == null) {
      return null;
    }
    final callId = callIdOf(response.payload);
    if (callId == null) return null;
    return CallNotificationResponse(callId, switch (response.actionId) {
      acceptActionId => CallNotificationAction.accept,
      declineActionId => CallNotificationAction.decline,
      _ => CallNotificationAction.open,
    });
  }
}
