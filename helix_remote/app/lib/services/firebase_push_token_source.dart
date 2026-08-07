import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:helix_remote/services/android_call_runtime_service.dart';
import 'package:helix_remote/services/app_logger.dart';
import 'package:helix_remote/services/local_notification_service.dart';
import 'package:helix_remote/services/push_token_source.dart';

/// Handles the server's data-only call wake while the app is backgrounded or
/// terminated. The notification is deliberately generic: the authenticated
/// app fetches the pending call after the user opens it.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final type = _notificationType(message.data);
  final callId = message.data['call_id'] as String?;
  final shortCallId = callId == null || callId.length <= 8
      ? callId
      : callId.substring(0, 8);
  debugPrint(
    '[push] background message received id=${message.messageId} '
    'type=$type call_id=$shortCallId keys=${message.data.keys.join(',')}',
  );
  if (type != 'incoming_call' && type != 'new_message') {
    debugPrint('[push] background message ignored type=$type');
    return;
  }

  if (type == 'incoming_call' && (callId == null || callId.isEmpty)) return;

  try {
    DartPluginRegistrant.ensureInitialized();
    await Firebase.initializeApp();
    debugPrint('[push] background Firebase initialized call_id=$shortCallId');
    await LocalNotificationService.init();
    debugPrint(
      '[push] background local notifications initialized '
      'call_id=$shortCallId',
    );
    if (type == 'incoming_call') {
      final isVideo = _isVideoCall(message.data);
      final fullScreen =
          await AndroidCallRuntimeService.shouldUseFullScreenIncomingCall();
      await LocalNotificationService.showIncomingCall(
        callId: callId!,
        callerDisplayName: _callerLabel(message.data),
        isVideo: isVideo,
        fullScreenIntent: fullScreen,
      );
    } else {
      await LocalNotificationService.showMessage(
        notificationKey:
            message.data['message_id'] as String? ??
            message.messageId ??
            'message',
      );
    }
    debugPrint('[push] background notification shown call_id=$shortCallId');
  } catch (error) {
    // There is no foreground AppLogger instance in this isolate. Keep the
    // failure visible to Android's logcat without exposing the push token.
    debugPrint('[push] background wake failed: ${error.runtimeType}');
  }
}

/// [PushTokenSource] backed by Firebase Cloud Messaging.
///
/// Deliberately tolerant of an unconfigured build. `google-services.json` is
/// not in the repository — it is deployment material, and a developer
/// checkout will not have one — so `Firebase.initializeApp()` throwing is an
/// expected outcome, not a crash. Every failure path answers "push is
/// unavailable" and the app carries on without it.
///
/// Nothing about a message is carried in the push payload: the server sends
/// only a wake hint (see `outbox_worker.dart`, which rejects payloads
/// containing content keys). The notification exists to bring the app far
/// enough forward to open its own authenticated connection and fetch the
/// call over the normal path.
class FirebasePushTokenSource implements PushTokenSource {
  FirebasePushTokenSource();

  final StreamController<String> _refreshes =
      StreamController<String>.broadcast();
  StreamSubscription<String>? _sdkRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  bool _initialized = false;

  @override
  String get tokenType => 'FCM';

  @override
  Future<bool> initialize() async {
    if (_initialized) return true;
    // FCM is Android-only for this product today: there is no iOS target, and
    // the desktop builds have no push transport. Calling into the plugin on
    // Windows throws a MissingPluginException on every launch.
    if (!Platform.isAndroid) {
      AppLogger.instance.info('push', 'FCM unavailable on non-Android build');
      return false;
    }

    try {
      await Firebase.initializeApp();
      AppLogger.instance.info('push', 'Firebase initialized');
    } catch (error) {
      // Almost always a missing or malformed google-services.json. Treated as
      // "push not configured for this build" rather than a fatal error.
      AppLogger.instance.warn(
        'push',
        'Firebase initialization failed: ${error.runtimeType}',
      );
      return false;
    }

    final messaging = FirebaseMessaging.instance;
    try {
      final settings = await messaging.requestPermission();
      // Provisional counts: on Android 13+ a user who has not answered the
      // prompt yet can still receive a token, and denying only suppresses the
      // banner - the data message still wakes the app, which is what a call
      // needs.
      final denied = settings.authorizationStatus == AuthorizationStatus.denied;
      AppLogger.instance.info(
        'push',
        'notification permission status=${settings.authorizationStatus.name}',
      );
      if (denied) {
        AppLogger.instance.warn('push', 'notification permission denied');
        return false;
      }
    } catch (_) {
      // An older embedding without the permission API - carry on and let the
      // token lookup decide.
    }

    _sdkRefreshSub = messaging.onTokenRefresh.listen(
      _refreshes.add,
      onError: _refreshes.addError,
    );
    _foregroundMessageSub = FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showForegroundNotification(message));
    });
    _initialized = true;
    AppLogger.instance.info('push', 'FCM token source ready');
    return true;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final type = _notificationType(message.data);
    final callId = message.data['call_id'] as String?;
    final shortCallId = callId == null || callId.length <= 8
        ? callId
        : callId.substring(0, 8);
    AppLogger.instance.info(
      'push',
      'foreground message received id=${message.messageId} '
          'type=$type call_id=$shortCallId',
    );
    try {
      if (type == 'incoming_call' && callId != null && callId.isNotEmpty) {
        await LocalNotificationService.showIncomingCall(
          callId: callId,
          callerDisplayName: _callerLabel(message.data),
          isVideo: _isVideoCall(message.data),
          fullScreenIntent: false,
        );
      } else if (type == 'new_message') {
        await LocalNotificationService.showMessage(
          notificationKey:
              message.data['message_id'] as String? ??
              message.messageId ??
              'message',
        );
      }
    } catch (error) {
      AppLogger.instance.warn(
        'push',
        'foreground notification failed type=$type call_id=$callId '
            'error=${error.runtimeType}',
      );
    }
  }

  @override
  Future<String?> currentToken() async {
    if (!_initialized) return null;
    return FirebaseMessaging.instance.getToken();
  }

  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;

  @override
  Future<void> dispose() async {
    await _sdkRefreshSub?.cancel();
    _sdkRefreshSub = null;
    await _foregroundMessageSub?.cancel();
    _foregroundMessageSub = null;
    await _refreshes.close();
    _initialized = false;
  }
}

bool _isVideoCall(Map<String, dynamic> data) =>
    data['is_video'] == true || data['is_video']?.toString() == 'true';

String _callerLabel(Map<String, dynamic> data) {
  final displayName = data['caller_display_name']?.toString().trim();
  if (displayName != null && displayName.isNotEmpty) return displayName;
  final phoneLast4 = data['caller_phone_last4']?.toString().trim();
  if (phoneLast4 != null && phoneLast4.isNotEmpty) {
    return 'Phone ending $phoneLast4';
  }
  return 'Unknown caller';
}

String? _notificationType(Map<String, dynamic> data) {
  final explicit = data['notification_type'] as String?;
  if (explicit != null && explicit.isNotEmpty) return explicit;
  if (data['message_id'] is String) return 'new_message';
  return null;
}
