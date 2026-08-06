import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum LocalNotificationCallAction { accept, decline }

/// Thin wrapper around flutter_local_notifications for in-process system
/// notifications and FCM-triggered offline/background alerts.
class LocalNotificationService {
  LocalNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static void Function(LocalNotificationCallAction action, String callId)?
  _callActionHandler;

  static const _contactChannel = AndroidNotificationChannel(
    'helix_contact_requests',
    'Contact Requests',
    description: 'Incoming contact request notifications',
    importance: Importance.high,
  );

  static const _incomingCallChannel = AndroidNotificationChannel(
    'helix_incoming_calls',
    'Incoming Calls',
    description: 'Incoming Helix Remote call alerts',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const _messageChannel = AndroidNotificationChannel(
    'helix_messages',
    'Messages',
    description: 'New Helix Remote messages',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const _verificationChannel = AndroidNotificationChannel(
    'helix_verification_codes',
    'Verification Codes',
    description: 'One-time codes for signup and invites',
    importance: Importance.high,
  );

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    // Create channel (no-op on < Android 8; required on >= 8).
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_contactChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_incomingCallChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_messageChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_verificationChannel);

    // Request runtime permission on Android 13+.
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    _ready = true;
  }

  static void setCallActionHandler(
    void Function(LocalNotificationCallAction action, String callId)? handler,
  ) {
    _callActionHandler = handler;
  }

  static Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  static Future<void> showContactRequest(String peerAccountId) async {
    if (!_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _contactChannel.id,
      _contactChannel.name,
      channelDescription: _contactChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    await _plugin.show(
      peerAccountId.hashCode & 0x7fffffff,
      'New contact request',
      'Someone wants to connect with you',
      NotificationDetails(android: androidDetails),
    );
  }

  /// Self-fired the moment the app receives a phone-verification code
  /// directly in the OTP-request response, which only happens when the
  /// server has no real SMS provider configured (see the backend's phone
  /// OTP module) - this simulates "you got a text" rather than being a
  /// genuine out-of-band channel. Not called when the server did send a
  /// real SMS (see `RemoteCompositionRegistration.requestOtp`).
  static Future<void> showVerificationCode({required String code}) async {
    if (!_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _verificationChannel.id,
      _verificationChannel.name,
      channelDescription: _verificationChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    await _plugin.show(
      'verification_code'.hashCode & 0x7fffffff,
      'Your Helix verification code',
      code,
      NotificationDetails(android: androidDetails),
    );
  }

  /// Self-fired for Helix Global's auto-issued signup invite.
  static Future<void> showInviteCode({required String code}) async {
    if (!_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _verificationChannel.id,
      _verificationChannel.name,
      channelDescription: _verificationChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    await _plugin.show(
      'invite_code'.hashCode & 0x7fffffff,
      'Your Helix Global invite code',
      code,
      NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> showIncomingCall({
    required String callId,
    required String callerDisplayName,
    required bool isVideo,
  }) async {
    if (!_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _incomingCallChannel.id,
      _incomingCallChannel.name,
      channelDescription: _incomingCallChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      actions: const [
        AndroidNotificationAction(
          'accept_call',
          'Accept',
          showsUserInterface: true,
        ),
        AndroidNotificationAction('decline_call', 'Decline'),
      ],
    );
    await _plugin.show(
      callId.hashCode & 0x7fffffff,
      isVideo ? 'Incoming video call' : 'Incoming audio call',
      callerDisplayName,
      NotificationDetails(android: androidDetails),
      payload: 'call_id=$callId',
    );
  }

  static Future<void> showMessage({
    required String notificationKey,
    String title = 'Helix Remote',
    String body = 'You have a new message',
  }) async {
    if (!_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _messageChannel.id,
      _messageChannel.name,
      channelDescription: _messageChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    await _plugin.show(
      notificationKey.hashCode & 0x7fffffff,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> cancelIncomingCall(String callId) async {
    if (!_ready) return;
    await _plugin.cancel(callId.hashCode & 0x7fffffff);
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || !payload.startsWith('call_id=')) return;
    final callId = payload.substring('call_id='.length);
    if (callId.isEmpty) return;
    final action = switch (response.actionId) {
      'accept_call' => LocalNotificationCallAction.accept,
      'decline_call' => LocalNotificationCallAction.decline,
      _ => null,
    };
    if (action != null) _callActionHandler?.call(action, callId);
  }
}
