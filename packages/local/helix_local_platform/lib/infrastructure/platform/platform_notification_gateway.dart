import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:helix_local_protocol/application/contracts/gateways.dart';

// Notification IDs — stable so we can cancel by ID
const _kIdForeground = 1;
const _kIdIncomingRequestBase = 100; // +hash of requestId for uniqueness
const _kIdNewMessage = 200;
const _kIdIncomingCallBase = 300; // +hash of callId for uniqueness

const _kActionReply = 'reply';
const _kActionMarkRead = 'mark_read';
const _kActionAcceptCall = 'accept_call';
const _kActionDeclineCall = 'decline_call';
const _kCallPayloadPrefix = 'call:';

class PlatformNotificationGateway implements NotificationGateway {
  final FlutterLocalNotificationsPlugin _plugin;
  final String _appName;
  final String _appUserModelId;
  final String _windowsNotificationGuid;
  final String _channelPrefix;
  final String _methodChannelNamespace;

  PlatformNotificationGateway({
    FlutterLocalNotificationsPlugin? plugin,
    required String appName,
    required String appUserModelId,
    required String windowsNotificationGuid,
    required String channelPrefix,
    required String methodChannelNamespace,
  })  : _appName = appName, // ignore: prefer_initializing_formals
        _appUserModelId = appUserModelId, // ignore: prefer_initializing_formals
        _windowsNotificationGuid = windowsNotificationGuid, // ignore: prefer_initializing_formals
        _channelPrefix = channelPrefix, // ignore: prefer_initializing_formals
        _methodChannelNamespace = methodChannelNamespace, // ignore: prefer_initializing_formals
        _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  String get _channelForeground => '${_channelPrefix}_foreground';
  String get _channelRequests => '${_channelPrefix}_requests';
  String get _channelMessages => '${_channelPrefix}_messages';
  String get _channelMessagesSilent => '${_channelPrefix}_messages_silent';
  String get _channelCalls => '${_channelPrefix}_calls';

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
    final windowsSettings = WindowsInitializationSettings(
      appName: _appName,
      appUserModelId: _appUserModelId,
      guid: _windowsNotificationGuid,
    );
    final initSettings = InitializationSettings(
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
      AndroidNotificationChannel(
        _channelForeground,
        '$_appName Service',
        description: 'Keeps $_appName running in the background.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelRequests,
        'Connection Requests',
        description: 'Alerts for incoming connection requests.',
        importance: Importance.high,
        playSound: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelMessages,
        'Messages',
        description: 'Alerts for new encrypted messages.',
        importance: Importance.high,
        playSound: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelMessagesSilent,
        'Messages (silent)',
        description: 'Silent alerts for new encrypted messages.',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelCalls,
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
        final granted = await MethodChannel('$_methodChannelNamespace/foreground')
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
      title: '$_appName is running',
      body: 'Listening for nearby devices.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelForeground,
          '$_appName Service',
          channelDescription: 'Keeps $_appName running in the background.',
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
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelRequests,
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
        : 'Tap to open $_appName.';

    final channelId = soundEnabled
        ? _channelMessages
        : _channelMessagesSilent;
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
          _channelCalls,
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
