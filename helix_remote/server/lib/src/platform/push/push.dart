import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
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
  callEnded('call_ended'),

  /// A plan request was decided or the plan changed (ADR-035). The device
  /// reads the plan itself; the wake-up says nothing about it.
  plan('plan');

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

/// What happened when a device was woken. Every wake-up ends in exactly one of
/// these, including the ones that send nothing: an operator asking "why did
/// this phone not ring" cannot otherwise tell a device with no token from a
/// provider that was never configured, and both from a send Google accepted
/// and the phone never showed.
enum PushOutcome {
  /// The provider accepted it (Google answered 200).
  sent('sent'),

  /// The device's socket is up: the server delivers over it instead.
  online('online'),

  /// The device has no stored token (never registered, or removed).
  noToken('no_token'),

  /// No provider is configured (`HELIX_PUSH_PROVIDER=none`): nothing can be
  /// sent, and this is what a phone that never rings on a fresh install means.
  providerOff('provider_off'),

  /// The provider refused or was unreachable; the job retries with backoff.
  failed('failed'),

  /// The token is no longer valid (the app was uninstalled); it is dropped.
  tokenGone('token_gone');

  const PushOutcome(this.wire);

  final String wire;
}

/// One log line and one count per wake-up attempt.
///
/// A module creates one (`helix_push_total` is the same family whatever asks
/// for it, so messaging and calls share their labels) and records the outcome
/// with the device id, which is the only identifier a wake-up has. The token is
/// never part of it.
final class PushTrail {
  PushTrail(Log log, Metrics metrics)
    : _log = log.child({'component': 'push'}),
      _total = metrics.counter(
        'helix_push_total',
        'Device wake-ups, by reason and outcome',
      );

  final Log _log;
  final Counter _total;

  void record(
    PushOutcome outcome,
    PushReason reason,
    String deviceId, {
    String? error,
  }) {
    _total.inc({'reason': reason.wire, 'outcome': outcome.wire});
    _log.info('push', {
      'device_id': deviceId,
      'reason': reason.wire,
      'outcome': outcome.wire,
      'error': ?error,
    });
  }
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

/// Firebase Cloud Messaging HTTP v1 with a service-account key (ported
/// from v1, which was proven in production). Access tokens are cached and
/// refreshed five minutes early; one refresh runs at a time.
final class FcmPushProvider implements PushProvider {
  FcmPushProvider({
    required this.projectId,
    required this._serviceAccount,
    http.Client? client,
    this.tokenTimeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final String projectId;
  final Map<String, Object?> _serviceAccount;
  final http.Client _client;

  /// How long Google's token endpoint may take before the refresh is given up
  /// on (tests use a short one).
  final Duration tokenTimeout;

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

  /// Exchanges the service account for an access token.
  ///
  /// Bounded: Google's token endpoint is awaited *before* the `.timeout` that
  /// guards the POST, so a provider that accepts the connection and then stops
  /// answering used to leave this future pending forever. That future is the
  /// push job, and a job that never finishes holds the whole job runner (the
  /// drain awaits every job of a batch, and later ticks join the pass in
  /// flight) - no pushes, no purges, no relays until the node restarts.
  Future<String> _refresh() async {
    final credentials = gauth.ServiceAccountCredentials.fromJson(
      _serviceAccount,
    );
    final obtained = await gauth
        .obtainAccessCredentialsViaServiceAccount(credentials, const [
          _scope,
        ], _client)
        .timeout(tokenTimeout);
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
    final call = reason == PushReason.call || reason == PushReason.callEnded;
    // A plan update is not urgent: normal priority, and worth a day on the
    // provider's queue for a phone that is off.
    final plan = reason == PushReason.plan;
    final body = jsonEncode({
      'message': {
        'token': token,
        'android': {
          'priority': plan ? 'NORMAL' : 'HIGH',
          if (call) 'ttl': '45s',
          if (plan) 'ttl': '86400s',
        },
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
