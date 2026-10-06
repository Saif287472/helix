import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:http/http.dart' as http;

/// Why a device is being woken. Pushes carry only this — never content,
/// names or ids beyond the call id — and the app fetches and decrypts
/// (PRIVACY_CLAIM_MATRIX: no plaintext push payloads).
enum PushReason {
  /// New mailbox envelopes.
  message('message'),

  /// An incoming call offer (high priority, short TTL).
  call('call'),

  /// A call this device was ringing for ended.
  callEnded('call_ended');

  const PushReason(this.wire);

  final String wire;
}

/// The device's token is gone (uninstalled app): drop it.
final class PushTokenGone implements Exception {
  const PushTokenGone();
}

final class PushFailed implements Exception {
  const PushFailed(this.reason);

  final String reason;

  @override
  String toString() => 'PushFailed($reason)';
}

abstract interface class PushProvider {
  bool get isConfigured;

  /// Sends a data-only wake-up. [kind] is the token kind (`fcm`, `apns`, …).
  Future<void> send({
    required String token,
    required String kind,
    required PushReason reason,
    String? callId,
  });
}

final class NoPushProvider implements PushProvider {
  const NoPushProvider();

  @override
  bool get isConfigured => false;

  @override
  Future<void> send({
    required String token,
    required String kind,
    required PushReason reason,
    String? callId,
  }) async {}
}

/// Records pushes (tests).
final class RecordingPushProvider implements PushProvider {
  final List<({String token, PushReason reason, String? callId})> sent = [];

  /// Tokens that answer "unregistered".
  final Set<String> gone = {};

  @override
  bool get isConfigured => true;

  @override
  Future<void> send({
    required String token,
    required String kind,
    required PushReason reason,
    String? callId,
  }) async {
    if (gone.contains(token)) throw const PushTokenGone();
    sent.add((token: token, reason: reason, callId: callId));
  }
}

/// Firebase Cloud Messaging HTTP v1 with a service-account key (ported
/// from v1, which was proven in production). Access tokens are cached and
/// refreshed five minutes early; one refresh runs at a time.
final class FcmPushProvider implements PushProvider {
  FcmPushProvider({
    required this.projectId,
    required this._serviceAccount,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String projectId;
  final Map<String, Object?> _serviceAccount;
  final http.Client _client;
  String? _token;
  DateTime? _tokenExpires;
  Future<String>? _refreshing;

  static const _scope = 'https://www.googleapis.com/auth/firebase.messaging';

  @override
  bool get isConfigured => projectId.isNotEmpty;

  Future<String> _accessToken() {
    final token = _token;
    final expires = _tokenExpires;
    if (token != null &&
        expires != null &&
        DateTime.now().toUtc().isBefore(
          expires.subtract(const Duration(minutes: 5)),
        )) {
      return Future.value(token);
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _refresh() async {
    final credentials = gauth.ServiceAccountCredentials.fromJson(
      _serviceAccount,
    );
    final obtained = await gauth.obtainAccessCredentialsViaServiceAccount(
      credentials,
      const [_scope],
      _client,
    );
    _token = obtained.accessToken.data;
    _tokenExpires = obtained.accessToken.expiry;
    return _token!;
  }

  @override
  Future<void> send({
    required String token,
    required String kind,
    required PushReason reason,
    String? callId,
  }) async {
    if (kind != 'fcm') return; // APNs arrives with iOS (ADR-023).
    final call = reason != PushReason.message;
    final body = jsonEncode({
      'message': {
        'token': token,
        'android': {'priority': 'HIGH', if (call) 'ttl': '45s'},
        'data': {'t': reason.wire, 'call_id': ?callId},
      },
    });
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.https(
              'fcm.googleapis.com',
              '/v1/projects/$projectId/messages:send',
            ),
            headers: {
              'authorization': 'Bearer ${await _accessToken()}',
              'content-type': 'application/json; charset=utf-8',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));
    } on Object {
      throw const PushFailed('unreachable');
    }
    if (response.statusCode == 200) return;
    if (response.statusCode == 404) throw const PushTokenGone();
    throw PushFailed('http_${response.statusCode}');
  }
}

/// Reads `HELIX_PUSH_PROVIDER` (`none` or `fcm`), `HELIX_FCM_PROJECT_ID` and
/// `HELIX_FCM_SERVICE_ACCOUNT` (a path to the key file, or the JSON itself).
PushProvider pushProviderFrom(ServerConfig config) {
  final env = config.env;
  final kind = env['HELIX_PUSH_PROVIDER']?.trim() ?? 'none';
  switch (kind) {
    case 'none':
      return const NoPushProvider();
    case 'fcm':
      final project = env['HELIX_FCM_PROJECT_ID']?.trim() ?? '';
      final raw = env['HELIX_FCM_SERVICE_ACCOUNT']?.trim() ?? '';
      if (project.isEmpty || raw.isEmpty) {
        throw ConfigError([
          'HELIX_PUSH_PROVIDER=fcm needs HELIX_FCM_PROJECT_ID and HELIX_FCM_SERVICE_ACCOUNT',
        ]);
      }
      final Map<String, Object?> account;
      try {
        final text = raw.startsWith('{') ? raw : File(raw).readAsStringSync();
        account = (jsonDecode(text) as Map).cast<String, Object?>();
      } on Object {
        throw ConfigError([
          'HELIX_FCM_SERVICE_ACCOUNT must be a key file path or its JSON',
        ]);
      }
      return FcmPushProvider(projectId: project, serviceAccount: account);
    default:
      throw ConfigError(['HELIX_PUSH_PROVIDER must be none or fcm']);
  }
}
