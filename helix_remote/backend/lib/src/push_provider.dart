import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/fcm_access_token.dart';

abstract interface class PushProvider {
  bool get isConfigured;

  /// Delivers a push notification to the given FCM/APNs [token].
  /// [data] values must all be strings. Throws on unrecoverable errors.
  Future<void> deliver({
    required String token,
    required Map<String, dynamic> data,
    String? tokenType,
  });
}

/// Used when no push provider is configured. Delivery always fails.
final class NoopPushProvider implements PushProvider {
  const NoopPushProvider();

  @override
  bool get isConfigured => false;

  @override
  Future<void> deliver({
    required String token,
    required Map<String, dynamic> data,
    String? tokenType,
  }) {
    throw UnsupportedError('No push provider configured.');
  }
}

/// Abstract base exception for expired, uninstalled, or invalid push tokens
/// across both FCM and APNs providers.
abstract class PushTokenNotFoundException extends AppError {
  PushTokenNotFoundException(
    super.message, {
    super.statusCode = 502,
    super.code = RemoteErrorCode.pushTokenNotFound,
  });
}

/// FCM returned 404: the device token is no longer registered.
class FcmTokenNotFoundException extends PushTokenNotFoundException {
  FcmTokenNotFoundException(this.body)
    : super('Push token is no longer registered');

  final String body;

  @override
  String toString() => 'FcmTokenNotFoundException: $body';
}

/// FCM returned a non-200 status that is not a missing-token error.
class FcmDeliveryException extends AppError {
  FcmDeliveryException(this.upstreamStatusCode, this.body)
    : super(
        'Push delivery failed',
        statusCode: 502,
        code: RemoteErrorCode.pushDeliveryFailed,
      );

  final int upstreamStatusCode;
  final String body;

  @override
  String toString() => 'FcmDeliveryException($upstreamStatusCode): $body';
}

/// APNs source for obtaining or refreshing authentication bearer tokens (JWTs).
abstract interface class ApnsTokenSource {
  Future<String> bearerToken();
}

/// Fixed static APNs token for tests and local setups.
final class StaticApnsAccessToken implements ApnsTokenSource {
  const StaticApnsAccessToken(this.token);
  final String token;

  @override
  Future<String> bearerToken() async => token;
}

/// APNs returned 410 (Unregistered) or 400 (BadDeviceToken).
class ApnsTokenNotFoundException extends PushTokenNotFoundException {
  ApnsTokenNotFoundException(this.body)
    : super('APNs device token is unregistered or invalid');

  final String body;

  @override
  String toString() => 'ApnsTokenNotFoundException: $body';
}

/// APNs returned a non-200 status that is not a token unregistered error.
class ApnsDeliveryException extends AppError {
  ApnsDeliveryException(this.upstreamStatusCode, this.body)
    : super(
        'APNs push delivery failed',
        statusCode: 502,
        code: RemoteErrorCode.pushDeliveryFailed,
      );

  final int upstreamStatusCode;
  final String body;

  @override
  String toString() => 'ApnsDeliveryException($upstreamStatusCode): $body';
}

/// Native APNs HTTP/2 push provider supporting standard iOS push alerts and
/// PushKit VoIP incoming call wake-ups.
final class ApnsPushProvider implements PushProvider {
  ApnsPushProvider({
    required this.teamId,
    required this.keyId,
    required this.bundleId,
    required this.tokenSource,
    this.isProduction = false,
    Uri? endpoint,
    HttpClient? httpClient,
  }) : endpoint =
           endpoint ??
           Uri.https(
             isProduction
                 ? 'api.push.apple.com'
                 : 'api.development.push.apple.com',
             '',
           ),
       _httpClient = httpClient;

  ApnsPushProvider.staticToken({
    required String teamId,
    required String keyId,
    required String bundleId,
    required String accessToken,
    bool isProduction = false,
    Uri? endpoint,
    HttpClient? httpClient,
  }) : this(
         teamId: teamId,
         keyId: keyId,
         bundleId: bundleId,
         tokenSource: StaticApnsAccessToken(accessToken),
         isProduction: isProduction,
         endpoint: endpoint,
         httpClient: httpClient,
       );

  final String teamId;
  final String keyId;
  final String bundleId;
  final ApnsTokenSource tokenSource;
  final bool isProduction;
  final Uri endpoint;
  final HttpClient? _httpClient;

  @override
  bool get isConfigured =>
      teamId.isNotEmpty && keyId.isNotEmpty && bundleId.isNotEmpty;

  @override
  Future<void> deliver({
    required String token,
    required Map<String, dynamic> data,
    String? tokenType,
  }) async {
    final isVoip =
        tokenType == 'APNS_VOIP' ||
        data['notification_type'] == 'incoming_call';
    final topic = isVoip ? '$bundleId.voip' : bundleId;
    final pushType = isVoip ? 'voip' : 'alert';
    final priority = '10'; // High priority for calls and alerts

    final String payloadJson;
    if (isVoip) {
      // VoIP PushKit payload: dictionary passed to PKPushRegistry
      payloadJson = jsonEncode({
        'aps': <String, dynamic>{},
        for (final e in data.entries) e.key: '${e.value}',
      });
    } else {
      final notificationType = data['notification_type']?.toString();
      final title = 'Helix Remote';
      final body = switch (notificationType) {
        'new_message' => 'You have a new message',
        'group_invite' => 'You have a new group invitation',
        _ => 'You have a new notification',
      };
      payloadJson = jsonEncode({
        'aps': {
          'alert': {'title': title, 'body': body},
          'sound': 'default',
          'badge': 1,
        },
        for (final e in data.entries) e.key: '${e.value}',
      });
    }

    final bearer = await tokenSource.bearerToken();
    final url = endpoint.resolve('/3/device/$token');
    final http = _httpClient ?? HttpClient();
    try {
      final req = await http.postUrl(url);
      req.headers
        ..set('authorization', 'bearer $bearer')
        ..set('apns-topic', topic)
        ..set('apns-push-type', pushType)
        ..set('apns-priority', priority)
        ..set(
          'apns-expiration',
          isVoip
              ? '0'
              : '${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400}',
        )
        ..set('content-type', 'application/json; charset=utf-8');
      req.write(payloadJson);

      final res = await req.close();
      final resBody = await res.transform(utf8.decoder).join();

      if (res.statusCode == 200) return;

      if (res.statusCode == 410 ||
          (res.statusCode == 400 && resBody.contains('BadDeviceToken'))) {
        throw ApnsTokenNotFoundException(resBody);
      }
      throw ApnsDeliveryException(res.statusCode, resBody);
    } finally {
      if (_httpClient == null) {
        http.close(force: true);
      }
    }
  }
}

/// Composite push provider that routes notifications to FCM or APNs based on
/// token type or token pattern.
final class CompositePushProvider implements PushProvider {
  CompositePushProvider({required this.fcm, required this.apns});

  final PushProvider fcm;
  final PushProvider apns;

  @override
  bool get isConfigured => fcm.isConfigured || apns.isConfigured;

  @override
  Future<void> deliver({
    required String token,
    required Map<String, dynamic> data,
    String? tokenType,
  }) async {
    final isApns =
        tokenType == 'APNS' ||
        tokenType == 'APNS_VOIP' ||
        _looksLikeApnsToken(token);
    if (isApns) {
      if (!apns.isConfigured) {
        throw UnsupportedError('APNs push provider is not configured.');
      }
      return apns.deliver(token: token, data: data, tokenType: tokenType);
    } else {
      if (!fcm.isConfigured) {
        throw UnsupportedError('FCM push provider is not configured.');
      }
      return fcm.deliver(token: token, data: data, tokenType: tokenType);
    }
  }

  static bool _looksLikeApnsToken(String token) {
    // APNs device tokens are standard 64 hex characters (32 bytes).
    return token.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(token);
  }
}

/// FCM HTTP v1 push provider. Requires a GCP project ID
/// (HELIX_REMOTE_FCM_PROJECT_ID) and a token source.
final class FcmPushProvider implements PushProvider {
  FcmPushProvider({
    required this.projectId,
    required this.tokenSource,
    Uri? endpoint,
  }) : endpoint =
           endpoint ??
           Uri.https(
             'fcm.googleapis.com',
             '/v1/projects/$projectId/messages:send',
           );

  FcmPushProvider.staticToken({
    required String projectId,
    required String accessToken,
  }) : this(
         projectId: projectId,
         tokenSource: StaticFcmAccessToken(accessToken),
       );

  final String projectId;
  final FcmAccessTokenSource tokenSource;
  final Uri endpoint;

  @override
  bool get isConfigured => projectId.isNotEmpty;

  @override
  Future<void> deliver({
    required String token,
    required Map<String, dynamic> data,
    String? tokenType,
  }) async {
    final stringData = {for (final e in data.entries) e.key: '${e.value}'};
    final notificationType = data['notification_type']?.toString();
    final isCall = notificationType == 'incoming_call';
    final callIsVideo = data['is_video']?.toString() == 'true';
    final callerLabel = _callerLabel(data);
    final notificationTitle = isCall
        ? (callIsVideo ? 'Incoming video call' : 'Incoming audio call')
        : 'Helix Remote';
    final notificationBody = switch (notificationType) {
      'incoming_call' => callerLabel,
      'new_message' => 'You have a new message',
      'group_invite' => 'You have a new group invitation',
      _ => 'You have a new notification',
    };
    final channelId = isCall ? 'helix_incoming_calls' : 'helix_messages';

    final body = jsonEncode({
      'message': {
        'token': token,
        'notification': {'title': notificationTitle, 'body': notificationBody},
        'android': {
          'priority': 'HIGH',
          'notification': {'channel_id': channelId, 'sound': 'default'},
        },
        'data': stringData,
      },
    });

    final accessToken = await tokenSource.bearerToken();

    final http = HttpClient();
    try {
      final req = await http.postUrl(endpoint);
      req.headers
        ..set('Authorization', 'Bearer $accessToken')
        ..set('Content-Type', 'application/json; charset=utf-8');
      req.write(body);

      final res = await req.close();
      final resBody = await res.transform(utf8.decoder).join();

      if (res.statusCode == 200) return;

      if (res.statusCode == 404) {
        throw FcmTokenNotFoundException(resBody);
      }
      throw FcmDeliveryException(res.statusCode, resBody);
    } finally {
      http.close(force: true);
    }
  }

  String _callerLabel(Map<String, dynamic> data) {
    final displayName = data['caller_display_name']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final phoneLast4 = data['caller_phone_last4']?.toString().trim();
    if (phoneLast4 != null && phoneLast4.isNotEmpty) {
      return 'Phone ending $phoneLast4';
    }
    return 'Unknown caller';
  }
}
