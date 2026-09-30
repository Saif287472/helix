import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

enum LocalNotificationCallAction { accept, decline, end }

/// Where a notification button pressed outside the app's main isolate is
/// forwarded to the running app (see [LocalNotificationService.init]).
const _callActionPortName = 'helix_remote_call_actions';

/// Runs in a background isolate when Decline or End is pressed on a call
/// notification, which Android delivers without opening the app.
///
/// When the app is running its main isolate owns the call, so the press is
/// forwarded there. When it is not (the call only rang through a push), a
/// Decline is sent to the server directly, so the caller stops ringing.
@pragma('vm:entry-point')
void helixNotificationBackgroundHandler(NotificationResponse response) {
  final action = response.actionId;
  final callId = _callIdFromPayload(response.payload);
  if (callId == null) return;
  final port = IsolateNameServer.lookupPortByName(_callActionPortName);
  if (port != null) {
    port.send(<String>[action ?? '', callId]);
    return;
  }
  if (action == 'decline_call' || action == 'end_call') {
    unawaited(_declineWithoutTheApp(callId));
  }
}

String? _callIdFromPayload(String? payload) {
  if (payload == null || !payload.startsWith('call_id=')) return null;
  final id = payload.substring('call_id='.length);
  return id.isEmpty ? null : id;
}

Future<void> _declineWithoutTheApp(String callId) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    const storage = FlutterSecureStorage();
    final server = await storage.read(key: 'helix_remote_server_url');
    final token = await storage.read(key: 'helix_remote_v1_access_token');
    if (server == null || token == null) return;
    final base = server.endsWith('/')
        ? server.substring(0, server.length - 1)
        : server;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse(
          '$base/api/v1/calls/pending/${Uri.encodeComponent(callId)}/decline',
        ),
      );
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
        ..contentType = ContentType.json;
      request.write('{}');
      await (await request.close()).drain<void>();
    } finally {
      client.close(force: true);
    }
  } catch (_) {
    // The call times out on its own; nothing else can be done from here.
  }
}

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

  /// Rings with the phone's ringtone, like the phone app. A channel's sound
  /// cannot change once created, hence the new id; the old channel (default
  /// notification beep) is deleted in [init].
  static final _incomingCallChannel = AndroidNotificationChannel(
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
  static const _legacyIncomingCallChannelId = 'helix_incoming_calls';

  /// A call's Answer pressed before the app knew about that call (a cold
  /// start from the notification, or the offer still on its way).
  static ({String callId, DateTime at})? pendingAccept;
  static ReceivePort? _actionPort;

  static const _activeCallChannel = AndroidNotificationChannel(
    'helix_active_calls',
    'Active Calls',
    description: 'Ongoing Helix Remote call controls',
    importance: Importance.low,
  );

  static const _messageChannel = AndroidNotificationChannel(
    'helix_messages',
    'Messages',
    description: 'New Helix Remote messages',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const _securityChannel = AndroidNotificationChannel(
    'helix_security',
    'Security alerts',
    description: 'New sign-ins to your account',
    importance: Importance.high,
  );

  static const _verificationChannel = AndroidNotificationChannel(
    'helix_verification_codes',
    'Verification Codes',
    description: 'One-time codes for signup and invites',
    importance: Importance.high,
  );

  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          helixNotificationBackgroundHandler,
    );
    _listenForForwardedActions();
    // The app was opened by pressing Answer (or tapping the call
    // notification): remember it until the call itself arrives.
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _handleNotificationResponse(response);
      }
    } catch (_) {}
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.deleteNotificationChannel(channelId: _legacyIncomingCallChannelId);
    } catch (_) {}

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
        ?.createNotificationChannel(_activeCallChannel);
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
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_securityChannel);

    // Request runtime permission on Android 13+.
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    _ready = true;
  }

  /// Ensures that notification permission is granted. If the user previously
  /// did not allow notifications, prompts them again.
  static Future<bool> ensureNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return true;
      final enabled = await android.areNotificationsEnabled();
      if (enabled != true) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Whether the system currently lets this app post notifications, without
  /// prompting. Null off Android, where there is nothing to report.
  static Future<bool?> notificationsAllowed() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    } catch (_) {
      return null;
    }
  }

  static void setCallActionHandler(
    void Function(LocalNotificationCallAction action, String callId)? handler,
  ) {
    _callActionHandler = handler;
  }

  /// Receives the buttons pressed in the background isolate
  /// ([helixNotificationBackgroundHandler]) while this isolate is running.
  static void _listenForForwardedActions() {
    if (_actionPort != null) return;
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(_callActionPortName);
    if (!IsolateNameServer.registerPortWithName(
      port.sendPort,
      _callActionPortName,
    )) {
      port.close();
      return;
    }
    _actionPort = port;
    port.listen((message) {
      if (message is! List || message.length != 2) return;
      _dispatchCallAction(message[0] as String, message[1] as String);
    });
  }

  static void _dispatchCallAction(String actionId, String callId) {
    final action = switch (actionId) {
      'accept_call' => LocalNotificationCallAction.accept,
      'decline_call' => LocalNotificationCallAction.decline,
      'end_call' => LocalNotificationCallAction.end,
      _ => null,
    };
    if (action == null) return;
    if (action == LocalNotificationCallAction.accept) {
      pendingAccept = (callId: callId, at: DateTime.now());
    }
    _callActionHandler?.call(action, callId);
  }

  static Future<void> cancelAll() async {
    if (!Platform.isAndroid || !_ready) return;
    await _plugin.cancelAll();
  }

  static Future<void> showContactRequest(String peerAccountId) async {
    if (!Platform.isAndroid || !_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _contactChannel.id,
      _contactChannel.name,
      channelDescription: _contactChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    await _plugin.show(
      id: peerAccountId.hashCode & 0x7fffffff,
      title: 'New contact request',
      body: 'Someone wants to connect with you',
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  /// Self-fired the moment the app receives a phone-verification code
  /// directly in the OTP-request response, which only happens when the
  /// server has no real SMS provider configured (see the backend's phone
  /// OTP module) - this simulates "you got a text" rather than being a
  /// genuine out-of-band channel. Not called when the server did send a
  /// real SMS (see `RemoteCompositionRegistration.requestOtp`).
  static Future<void> showVerificationCode({required String code}) async {
    if (!Platform.isAndroid || !_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _verificationChannel.id,
      _verificationChannel.name,
      channelDescription: _verificationChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    await _plugin.show(
      id: 'verification_code'.hashCode & 0x7fffffff,
      title: 'Your Helix verification code',
      body: code,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  /// Self-fired for Helix Global's auto-issued signup invite.
  static Future<void> showInviteCode({required String code}) async {
    if (!Platform.isAndroid || !_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _verificationChannel.id,
      _verificationChannel.name,
      channelDescription: _verificationChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    await _plugin.show(
      id: 'invite_code'.hashCode & 0x7fffffff,
      title: 'Your Helix Global invite code',
      body: code,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> showIncomingCall({
    required String callId,
    required String callerDisplayName,
    required bool isVideo,
    bool fullScreenIntent = false,
  }) async {
    if (!Platform.isAndroid || !_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _incomingCallChannel.id,
      _incomingCallChannel.name,
      channelDescription: _incomingCallChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: fullScreenIntent,
      ongoing: true,
      autoCancel: false,
      // Keep ringing until answered, declined or timed out (FLAG_INSISTENT),
      // but a re-post of the same call must not restart the sound.
      additionalFlags: Int32List.fromList(const [4]),
      onlyAlertOnce: true,
      timeoutAfter: 45000,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      color: HelixCallColors.answerCall,
      colorized: true,
      subText: isVideo ? 'Helix video call' : 'Helix voice call',
      ticker: 'Incoming call from $callerDisplayName',
      actions: const [
        AndroidNotificationAction(
          'decline_call',
          'Decline',
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'accept_call',
          'Answer',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );
    await _plugin.show(
      id: callId.hashCode & 0x7fffffff,
      title: callerDisplayName,
      body: isVideo ? 'Incoming video call' : 'Incoming voice call',
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: 'call_id=$callId',
    );
  }

  static Future<void> showOngoingCall({
    required String callId,
    required String callerDisplayName,
    required bool isVideo,
  }) async {
    if (!Platform.isAndroid || !_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _activeCallChannel.id,
      _activeCallChannel.name,
      channelDescription: _activeCallChannel.description,
      importance: Importance.low,
      priority: Priority.low,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      usesChronometer: true,
      color: HelixCallColors.answerCall,
      actions: const [
        AndroidNotificationAction(
          'end_call',
          'Hang up',
          cancelNotification: false,
        ),
      ],
    );
    await _plugin.show(
      id: _ongoingCallNotificationId,
      title: callerDisplayName,
      body: isVideo ? 'Ongoing video call' : 'Ongoing voice call',
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: 'call_id=$callId',
    );
  }

  static Future<void> showMessage({
    required String notificationKey,
    String title = 'Helix Remote',
    String body = 'You have a new message',
  }) async {
    if (!Platform.isAndroid || !_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _messageChannel.id,
      _messageChannel.name,
      channelDescription: _messageChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    await _plugin.show(
      id: notificationKey.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  /// Another device just signed in to this account. One notification per
  /// device, so a repeat of the same event replaces rather than stacks.
  static Future<void> showNewSignIn({
    required String deviceId,
    required String deviceName,
  }) async {
    if (!Platform.isAndroid || !_ready) return;
    final androidDetails = AndroidNotificationDetails(
      _securityChannel.id,
      _securityChannel.name,
      channelDescription: _securityChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    final name = deviceName.trim().isEmpty ? 'A new device' : deviceName.trim();
    await _plugin.show(
      id: 'sign_in_$deviceId'.hashCode & 0x7fffffff,
      title: 'New sign-in to your account',
      body:
          '$name signed in with your password. Not you? Sign it out in '
          'Settings > Devices and change your password.',
      notificationDetails: NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> cancelIncomingCall(String callId) async {
    if (!Platform.isAndroid || !_ready) return;
    await _plugin.cancel(id: callId.hashCode & 0x7fffffff);
  }

  static Future<void> cancelOngoingCall() async {
    if (!Platform.isAndroid || !_ready) return;
    await _plugin.cancel(id: _ongoingCallNotificationId);
  }

  static void _handleNotificationResponse(NotificationResponse response) {
    final callId = _callIdFromPayload(response.payload);
    if (callId == null) return;
    // A tap on the notification itself just opens the app, which shows the
    // ringing or ongoing call; only the buttons act on it.
    _dispatchCallAction(response.actionId ?? '', callId);
  }

  static const _ongoingCallNotificationId = 0x48434c4c;
}
