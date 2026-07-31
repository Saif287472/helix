import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote/app/remote_account_validation.dart';
import 'package:helix_remote/app/remote_endpoints.dart';
import 'package:helix_remote_domain/models.dart';

class HelixRemoteRestClientImpl implements HelixRemoteRestClient {
  HelixRemoteRestClientImpl({
    required Uri baseUri,
    required int timeoutMs,
    this._tokenProvider,
    Future<bool> Function()? refreshAuth,
    HttpClient? httpClient,
  }) : _endpoints = RemoteApiEndpoints(baseUri),
       _timeout = Duration(milliseconds: timeoutMs),
       _refreshAuth = refreshAuth,
       _httpClient =
           httpClient ??
           (() {
             final client = HttpClient();
             client.connectionTimeout = Duration(milliseconds: timeoutMs);
             return client;
           })();

  final RemoteApiEndpoints _endpoints;
  final Duration _timeout;
  final String? Function()? _tokenProvider;
  final Future<bool> Function()? _refreshAuth;
  final HttpClient _httpClient;

  String? _accessToken;
  Future<bool>? _refreshInFlight;

  @override
  set accessToken(String? token) => _accessToken = token;

  Map<String, String> get _headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
    };
    if (_accessToken != null) {
      h['Authorization'] = 'Bearer $_accessToken';
    } else {
      final token = _tokenProvider?.call();
      if (token != null) {
        h['Authorization'] = 'Bearer $token';
      }
    }
    return h;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
    String? idempotencyKey,
    Map<String, String>? queryParameters,
    bool skipAuthRefresh = false,
  }) async {
    final canRetry = _isSafeMethod(method) || idempotencyKey != null;
    final maxAttempts = canRetry ? 3 : 1;
    var attempt = 0;
    var retriedAfterRefresh = false;
    while (true) {
      attempt++;
      try {
        return await _sendOnce(
          method,
          path,
          body: body,
          extraHeaders: extraHeaders,
          idempotencyKey: idempotencyKey,
          queryParameters: queryParameters,
        );
      } on RemoteRestException catch (e) {
        if (!skipAuthRefresh &&
            !retriedAfterRefresh &&
            _isAuthFailure(e.statusCode) &&
            await _refreshAuthOnce()) {
          retriedAfterRefresh = true;
          attempt = 0;
          continue;
        }
        if (attempt >= maxAttempts || !_isRetryableStatus(e.statusCode)) {
          rethrow;
        }
        await Future<void>.delayed(e.retryAfter ?? _retryDelay(attempt));
      } on TimeoutException catch (e) {
        if (attempt >= maxAttempts) {
          throw RemoteRestException(
            message: 'REST request timed out: ${e.message ?? method}',
            uri: _endpoints.api(path, queryParameters: queryParameters),
            failureKind: RemoteRestFailureKind.timeout,
          );
        }
        await Future<void>.delayed(_retryDelay(attempt));
      } on SocketException catch (e) {
        if (attempt >= maxAttempts) {
          throw RemoteRestException(
            message: 'REST socket failure: ${e.message}',
            uri: _endpoints.api(path, queryParameters: queryParameters),
            failureKind: _classifySocketFailure(e),
          );
        }
        await Future<void>.delayed(_retryDelay(attempt));
      }
    }
  }

  Future<Map<String, dynamic>> _sendOnce(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
    String? idempotencyKey,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _endpoints.api(path, queryParameters: queryParameters);
    final correlationId = _newCorrelationId();
    final req = await _httpClient.openUrl(method, uri).timeout(_timeout);
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('ngrok-skip-browser-warning', 'true');
    req.headers.set('X-Correlation-Id', correlationId);
    if (idempotencyKey != null) {
      req.headers.set('Idempotency-Key', idempotencyKey);
    }
    final auth = _headers['Authorization'];
    if (auth != null) {
      req.headers.set('Authorization', auth);
    }
    if (extraHeaders != null) {
      extraHeaders.forEach((k, v) => req.headers.set(k, v));
    }

    if (body != null) {
      req.add(utf8.encode(jsonEncode(body)));
    }

    final resp = await req.close().timeout(_timeout);
    final respBody = await resp
        .transform(utf8.decoder)
        .join()
        .timeout(_timeout);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (respBody.isEmpty) return {};
      return jsonDecode(respBody) as Map<String, dynamic>;
    }

    throw RemoteRestException(
      statusCode: resp.statusCode,
      message: respBody.isEmpty ? 'REST ${resp.statusCode}' : respBody,
      uri: uri,
      correlationId:
          resp.headers.value('x-correlation-id') ??
          resp.headers.value('X-Correlation-Id') ??
          correlationId,
      retryAfter: _parseRetryAfter(resp.headers.value('retry-after')),
      failureKind: RemoteRestFailureKind.http,
    );
  }

  bool _isSafeMethod(String method) =>
      method == 'GET' || method == 'HEAD' || method == 'OPTIONS';

  bool _isRetryableStatus(int? statusCode) =>
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  bool _isAuthFailure(int? statusCode) =>
      statusCode == 401 || statusCode == 403;

  Future<bool> _refreshAuthOnce() {
    final refreshAuth = _refreshAuth;
    if (refreshAuth == null) return Future.value(false);
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    late final Future<bool> refresh;
    try {
      refresh = refreshAuth().catchError((_) => false);
    } catch (_) {
      return Future.value(false);
    }
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  Duration _retryDelay(int attempt) {
    final jitterMs = math.Random().nextInt(150);
    return Duration(milliseconds: (200 * (1 << (attempt - 1))) + jitterMs);
  }

  Duration? _parseRetryAfter(String? value) {
    if (value == null || value.isEmpty) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) return Duration(seconds: seconds);
    try {
      final date = HttpDate.parse(value);
      final delta = date.difference(DateTime.now().toUtc());
      return delta.isNegative ? Duration.zero : delta;
    } on FormatException {
      return null;
    }
  }

  String _newCorrelationId() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  RemoteRestFailureKind _classifySocketFailure(SocketException error) {
    final message = error.message.toLowerCase();
    if (message.contains('connection refused')) {
      return RemoteRestFailureKind.serverDown;
    }
    if (message.contains('failed host lookup') ||
        message.contains('network is unreachable') ||
        message.contains('no route to host') ||
        message.contains('network unreachable')) {
      return RemoteRestFailureKind.noInternet;
    }
    if (message.contains('timed out') || message.contains('timeout')) {
      return RemoteRestFailureKind.timeout;
    }
    return RemoteRestFailureKind.serverDown;
  }

  @override
  Future<Map<String, dynamic>> registerAccount({
    required String accountId,
    required String phoneHash,
    required String otpCode,
    required String inviteCode,
    required String displayName,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
    required String deviceName,
  }) => _request(
    'POST',
    'accounts/register',
    body: {
      'registration_version': 3,
      'account_id': accountId,
      'phone_hash': phoneHash,
      'otp_code': otpCode,
      'invite_code': inviteCode,
      'display_name': displayName,
      'account_identity_public_key': accountIdentityPublicKey,
      'device_id': deviceId,
      'device_signing_public_key': deviceSigningPublicKey,
      'device_agreement_public_key': deviceAgreementPublicKey,
      'account_registration_signature': accountRegistrationSignature,
      'device_registration_signature': deviceRegistrationSignature,
      'device_name': deviceName,
    },
    idempotencyKey: 'register:$accountId:$deviceId',
  );

  @override
  Future<Map<String, dynamic>> fetchDiscoverySalt() =>
      _request('GET', 'contacts/discovery-salt');

  @override
  Future<Map<String, dynamic>> requestPhoneOtp({required String phoneHash}) =>
      _request(
        'POST',
        'accounts/phone/otp/request',
        body: {'phone_hash': phoneHash},
      );

  @override
  Future<Map<String, dynamic>> lookupInvite({required String inviteCode}) =>
      _request(
        'GET',
        'accounts/invite/lookup',
        queryParameters: {'invite_code': inviteCode},
      );

  @override
  Future<Map<String, dynamic>> autoIssueGlobalInvite() =>
      _request('POST', 'accounts/invite/auto-issue');

  @override
  Future<Map<String, dynamic>> getChallenge({
    required String accountId,
    required String deviceId,
  }) => _request(
    'GET',
    'accounts/challenge',
    queryParameters: {'account_id': accountId, 'device_id': deviceId},
  );

  @override
  Future<Map<String, dynamic>> loginDevice({
    required String accountId,
    required String deviceId,
    required String signature,
  }) => _request(
    'POST',
    'accounts/login',
    body: {
      'account_id': accountId,
      'device_id': deviceId,
      'signature': signature,
    },
  );

  @override
  Future<Map<String, dynamic>> refreshToken({required String refreshToken}) =>
      _request(
        'POST',
        'accounts/refresh',
        body: {'refresh_token': refreshToken},
        skipAuthRefresh: true,
      );

  @override
  Future<List<RemoteDevice>> listDevices() async {
    final data = await _request('GET', 'accounts/devices');
    final list = data['devices'] as List<dynamic>;
    return list
        .map((e) => RemoteDevice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> requestNewDeviceLink({
    required String accountId,
    required String deviceId,
    required String deviceName,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
  }) => _request(
    'POST',
    'accounts/devices/link/request-new',
    body: {
      'account_id': accountId,
      'device_id': deviceId,
      'device_name': deviceName,
      'device_signing_public_key': deviceSigningPublicKey,
      'device_agreement_public_key': deviceAgreementPublicKey,
    },
    // Unique per invocation: each call carries a freshly generated keypair,
    // so a reused key would replay a cached response with stale keys.
    idempotencyKey:
        'device-link-request:$accountId:$deviceId:${_newCorrelationId()}',
    skipAuthRefresh: true,
  );

  @override
  Future<Map<String, dynamic>> approveDeviceLink({
    required String linkId,
    required String verificationCode,
  }) => _request(
    'POST',
    'accounts/devices/link/verify',
    body: {'link_id': linkId, 'verification_code': verificationCode},
  );

  @override
  Future<Map<String, dynamic>> rejectDeviceLink({
    required String linkId,
    required String verificationCode,
  }) => _request(
    'POST',
    'accounts/devices/link/reject',
    body: {'link_id': linkId, 'verification_code': verificationCode},
  );

  @override
  Future<Map<String, dynamic>> completeNewDeviceLink({
    required String linkId,
    required String signature,
  }) => _request(
    'POST',
    'accounts/devices/link/complete-new',
    body: {'link_id': linkId, 'signature': signature},
    skipAuthRefresh: true,
  );

  @override
  Future<void> renameDevice({
    required String deviceId,
    required String deviceName,
  }) async {
    await _request(
      'POST',
      'accounts/devices/rename',
      body: {'device_id': deviceId, 'device_name': deviceName},
    );
  }

  @override
  Future<void> revokeDevice(String deviceId) async {
    await _request(
      'POST',
      'accounts/devices/revoke',
      body: {'device_id': deviceId},
    );
  }

  @override
  Future<void> reportLostDevice(String deviceId) async {
    await _request(
      'POST',
      'accounts/devices/lost-device',
      body: {'device_id': deviceId},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getDeviceSecurityHistory(
    String deviceId,
  ) async {
    final data = await _request(
      'GET',
      'accounts/devices/security-history',
      queryParameters: {'device_id': deviceId},
    );
    return (data['history'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  @override
  Future<void> uploadPreKeys({
    required int signedPrekeyId,
    required String signedPrekey,
    required String signedPrekeySignature,
    required List<Map<String, dynamic>> oneTimePrekeys,
  }) async {
    await _request(
      'POST',
      'prekeys/publish',
      body: {
        'signed_prekey_id': signedPrekeyId,
        'signed_prekey': signedPrekey,
        'signature': signedPrekeySignature,
        'one_time_prekeys': oneTimePrekeys,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> getPreKeyBundle({required String accountId}) =>
      _request(
        'GET',
        'prekeys/bundle',
        queryParameters: {'account_id': accountId},
      );

  @override
  Future<Map<String, dynamic>> sendContactRequest({
    required String peerAccountId,
  }) => _request(
    'POST',
    'contacts/requests',
    body: {'peer_account_id': peerAccountId},
  );

  @override
  Future<void> acceptContactRequest(String requestId) async {
    await _request(
      'POST',
      'contacts/requests/accept',
      body: {'request_id': requestId},
    );
  }

  @override
  Future<Map<String, dynamic>> requestAttachmentUpload({
    required int fileSize,
    required String fileHash,
  }) => _request(
    'POST',
    'attachments/upload',
    body: {'file_size': fileSize, 'file_hash': fileHash},
  );

  @override
  Future<Map<String, dynamic>> requestAttachmentDownload(String fileId) async {
    final data = await _request('GET', 'attachments/download/$fileId');
    return data;
  }

  @override
  Future<Map<String, dynamic>> sendCallSignal({
    String? targetAccountId,
    String? targetDeviceId,
    required Map<String, dynamic> payload,
    String? requestId,
  }) {
    final body = <String, dynamic>{'payload': payload};
    if (requestId != null) body['request_id'] = requestId;
    if (targetAccountId != null) body['target_account_id'] = targetAccountId;
    if (targetDeviceId != null) body['target_device_id'] = targetDeviceId;
    return _request('POST', 'calls/signal', body: body);
  }

  @override
  Future<Map<String, dynamic>> getPendingCalls() =>
      _request('GET', 'calls/pending');

  @override
  Future<Map<String, dynamic>> acceptPendingCall(String callId) =>
      _request('POST', 'calls/pending/$callId/accept');

  @override
  Future<Map<String, dynamic>> declinePendingCall(String callId) =>
      _request('POST', 'calls/pending/$callId/decline');

  @override
  Future<Map<String, dynamic>> cancelPendingCall(String callId) =>
      _request('POST', 'calls/pending/$callId/cancel');

  @override
  Future<Map<String, dynamic>> getTurnCredentials() =>
      _request('GET', 'calls/turn-credentials');

  @override
  Future<void> requestAccountDeletion({required String confirmation}) async {
    await _request(
      'DELETE',
      'account/delete',
      body: {'confirmation': confirmation},
    );
  }

  @override
  Future<Map<String, dynamic>> exportData() =>
      _request('GET', 'privacy/export');

  @override
  Future<Map<String, dynamic>> uploadBackup({
    required String backupId,
    required String backupData,
    required int version,
    required String kdf,
    required String salt,
    String backupKeyHint = '',
    int deletionWatermark = 0,
  }) => _request(
    'POST',
    'backups/',
    body: {
      'backup_id': backupId,
      'backup_data': backupData,
      'version': version,
      'kdf': kdf,
      'salt': salt,
      'backup_key_hint': backupKeyHint,
      'deletion_watermark': deletionWatermark,
    },
  );

  @override
  Future<Map<String, dynamic>> downloadBackup() => _request('GET', 'backups/');

  @override
  Future<Map<String, dynamic>> requestBackupMediaUpload({
    required String objectId,
    required int byteSize,
    required String sha256,
  }) => _request(
    'POST',
    'backups/media',
    body: {'object_id': objectId, 'byte_size': byteSize, 'sha256': sha256},
    idempotencyKey: 'backup-media:$objectId',
  );

  @override
  Future<Map<String, dynamic>> getBackupMediaStatus(String objectId) =>
      _request('GET', 'backups/media/status/$objectId');

  @override
  Future<List<Map<String, dynamic>>> searchContacts(String query) async {
    final data = await _request(
      'GET',
      'contacts/search',
      queryParameters: {'q': query.trim()},
    );
    return (data['accounts'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>> getMyProfile() =>
      _request('GET', 'accounts/profile');

  @override
  Future<Map<String, dynamic>> updateDisplayName(String displayName) {
    final normalized = RemoteAccountValidation.normalizeDisplayName(
      displayName,
    );
    final error = RemoteAccountValidation.displayNameError(normalized);
    if (error != null) {
      throw ArgumentError.value(displayName, 'displayName', error);
    }
    return _request(
      'POST',
      'accounts/profile',
      body: {'display_name': normalized},
    );
  }

  @override
  Future<void> close() async {
    _httpClient.close(force: true);
  }
}

enum RemoteRestFailureKind { http, serverDown, noInternet, timeout, unknown }

class RemoteRestException extends HttpException {
  const RemoteRestException({
    required String message,
    Uri? uri,
    this.statusCode,
    this.correlationId,
    this.retryAfter,
    this.failureKind = RemoteRestFailureKind.unknown,
  }) : super(message, uri: uri);

  final int? statusCode;
  final String? correlationId;
  final Duration? retryAfter;
  final RemoteRestFailureKind failureKind;

  bool get isTransportFailure => statusCode == null;
}
