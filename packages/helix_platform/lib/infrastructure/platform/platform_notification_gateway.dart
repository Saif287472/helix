import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:helix_domain/core/constants.dart';
import 'package:helix_protocol/application/contracts/gateways.dart';

// Notification IDs — stable so we can cancel by ID
const _kIdForeground = 1;
const _kIdIncomingRequestBase = 100; // +hash of requestId for uniqueness
const _kIdNewMessage = 200;
const _kIdIncomingCallBase = 300; // +hash of callId for uniqueness

// Android notification channel IDs
const _kChannelForeground = 'helix_foreground';
const _kChannelRequests = 'helix_requests';
const _kChannelMessages = 'helix_messages';
const _kChannelMessagesSilent = 'helix_messages_silent';
const _kChannelCalls = 'helix_calls';
const _kActionReply = 'reply';
const _kActionMarkRead = 'mark_read';
const _kActionAcceptCall = 'accept_call';
const _kActionDeclineCall = 'decline_call';
const _kCallPayloadPrefix = 'call:';

class PlatformNotificationGateway implements NotificationGateway {
  final FlutterLocalNotificationsPlugin _plugin;

  PlatformNotificationGateway({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _canUseFullScreenIntent = true;
  final StreamController<NotificationActionIntent> _actionsController =
      StreamController<NotificationActionIntent>.broadcast();
  final StreamController<String> _tapsController =
      StreamController<String>.broadcast();

  @override
  Stream<NotificationActionIntent> get actions => _actionsController.stream;

  @override
  Stream<String> get taps => _tapsController.stream;

  @override
  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'Helix',
      appUserModelId: kWindowsAppUserModelId,
      guid: kWindowsNotificationGuid,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      windows: windowsSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    // Create Android notification channels
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kChannelForeground,
        'Helix Service',
        description: 'Keeps Helix running in the background.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kChannelRequests,
        'Connection Requests',
        description: 'Alerts for incoming connection requests.',
        importance: Importance.high,
        playSound: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kChannelMessages,
        'Messages',
        description: 'Alerts for new encrypted messages.',
        importance: Importance.high,
        playSound: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kChannelMessagesSilent,
        'Messages (silent)',
        description: 'Silent alerts for new encrypted messages.',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kChannelCalls,
        'Incoming Calls',
        description: 'Alerts for incoming voice calls.',
        importance: Importance.max,
        playSound: true,
      ),
    );

    await androidPlugin?.requestNotificationsPermission();

    // Android 14+ gates USE_FULL_SCREEN_INTENT as a runtime permission.
    // Cache it so showIncomingCall can fall back gracefully if not granted.
    if (Platform.isAndroid) {
      try {
        final granted = await const MethodChannel('com.helix.app/foreground')
            .invokeMethod<bool>('canUseFullScreenIntent');
        _canUseFullScreenIntent = granted ?? true;
      } catch (_) {}
    }

    _initialized = true;
  }

  @override
  Future<void> showForegroundServiceNotification() async {
    await _plugin.show(
      id: _kIdForeground,
      title: 'Helix is running',
      body: 'Listening for nearby devices.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelForeground,
          'Helix Service',
          channelDescription: 'Keeps Helix running in the background.',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          enableVibration: false,
          showWhen: false,
        ),
      ),
    );
  }

  @override
  Future<void> showIncomingRequest(
    String requesterName,
    String requestId,
  ) async {
    final notifId = _kIdIncomingRequestBase + (requestId.hashCode & 0x7FFF);

    await _plugin.show(
      id: notifId,
      title: 'Connection request',
      body: '$requesterName wants to connect.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelRequests,
          'Connection Requests',
          channelDescription: 'Alerts for incoming connection requests.',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: true,
        ),
      ),
      payload: 'requests',
    );
  }

  @override
  Future<void> showNewMessage(
    String? senderName,
    bool showSender, {
    String? threadId,
    bool soundEnabled = true,
  }) async {
    const title = 'New secure message';
    final body = (showSender && senderName != null && senderName.isNotEmpty)
        ? 'From $senderName'
        : 'Tap to open Helix.';

    final channelId = soundEnabled
        ? _kChannelMessages
        : _kChannelMessagesSilent;
    final channelName = soundEnabled ? 'Messages' : 'Messages (silent)';

    await _plugin.show(
      id: _kIdNewMessage,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: 'Alerts for new encrypted messages.',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: true,
          groupKey: threadId == null ? null : 'thread:$threadId',
          category: AndroidNotificationCategory.message,
          actions: const [
            AndroidNotificationAction(
              _kActionReply,
              'Reply',
              inputs: [AndroidNotificationActionInput(label: 'Message')],
              allowGeneratedReplies: true,
            ),
            AndroidNotificationAction(_kActionMarkRead, 'Mark as read'),
          ],
        ),
      ),
      payload: threadId,
    );
  }

  @override
  Future<void> showIncomingCall(String callId, String peerDisplayName) async {
    final notifId = _kIdIncomingCallBase + (callId.hashCode & 0x7FFF);

    await _plugin.show(
      id: notifId,
      title: 'Incoming call',
      body: '$peerDisplayName is calling…',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _kChannelCalls,
          'Incoming Calls',
          channelDescription: 'Alerts for incoming voice calls.',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: _canUseFullScreenIntent,
          ongoing: true,
          autoCancel: false,
          actions: const [
            AndroidNotificationAction(
              _kActionDeclineCall,
              'Decline',
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              _kActionAcceptCall,
              'Accept',
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: '$_kCallPayloadPrefix$callId',
    );
  }

  @override
  Future<void> cancelIncomingCall(String callId) async {
    final notifId = _kIdIncomingCallBase + (callId.hashCode & 0x7FFF);
    await _plugin.cancel(id: notifId);
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId == null || actionId.isEmpty) {
      final payload = response.payload;
      if (payload != null && payload.isNotEmpty) {
        _tapsController.add(payload);
      }
      return;
    }
    _actionsController.add(
      NotificationActionIntent(
        actionId: actionId,
        threadId: response.payload,
        input: response.input,
      ),
    );
  }

  @override
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  @override
  void dispose() {
    _actionsController.close();
    _tapsController.close();
  }
}
