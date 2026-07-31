import 'dart:convert';
import 'dart:io';

abstract interface class PushProvider {
  bool get isConfigured;

  /// Delivers a push notification to the given FCM/APNs [token].
  /// [data] values must all be strings. Throws on unrecoverable errors.
  Future<void> deliver({
    required String token,
    required Map<String, dynamic> data,
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
  }) {
    throw UnsupportedError('No push provider configured.');
  }
}

/// FCM HTTP v1 push provider. Requires a GCP project ID and a pre-obtained
/// OAuth2 access token (HELIX_REMOTE_FCM_PROJECT_ID + HELIX_REMOTE_FCM_ACCESS_TOKEN).
///
/// Callers are responsible for refreshing the access token before it expires.
/// The minimal payload (notification_type, call_id, target_device_id) is sent
/// as FCM data-only message with high Android priority so the app can handle
/// it without displaying a system notification.
final class FcmPushProvider implements PushProvider {
  FcmPushProvider({required this.projectId, required this.accessToken});

  final String projectId;
  final String accessToken;

  @override
  bool get isConfigured => projectId.isNotEmpty && accessToken.isNotEmpty;

  @override
  Future<void> deliver({
    required String token,
    required Map<String, dynamic> data,
  }) async {
    final stringData = {for (final e in data.entries) e.key: '${e.value}'};

    final body = jsonEncode({
      'message': {
        'token': token,
        'android': {'priority': 'HIGH'},
        'data': stringData,
      },
    });

    final url = Uri.https(
      'fcm.googleapis.com',
      '/v1/projects/$projectId/messages:send',
    );

    final http = HttpClient();
    try {
      final req = await http.postUrl(url);
      req.headers
        ..set('Authorization', 'Bearer $accessToken')
        ..set('Content-Type', 'application/json; charset=utf-8');
      req.write(body);

      final res = await req.close();
      final resBody = await res.transform(utf8.decoder).join();
      await res.drain<void>();

      if (res.statusCode == 200) return;

      // 401/403 = auth issue (caller should rotate token); 404 = bad FCM token
      // (device unregistered — caller should complete-and-drop the notification)
      if (res.statusCode == 404) {
        throw FcmTokenNotFoundException(resBody);
      }
      throw FcmDeliveryException(res.statusCode, resBody);
    } finally {
      http.close(force: true);
    }
  }
}

/// FCM returned 404: the device token is no longer registered.
class FcmTokenNotFoundException implements Exception {
  const FcmTokenNotFoundException(this.body);
  final String body;
  @override
  String toString() => 'FcmTokenNotFoundException: $body';
}

/// FCM returned a non-200 status that is not a missing-token error.
class FcmDeliveryException implements Exception {
  const FcmDeliveryException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'FcmDeliveryException($statusCode): $body';
}
