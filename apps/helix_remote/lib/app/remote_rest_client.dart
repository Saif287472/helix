import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';

class HelixRemoteRestClientImpl implements HelixRemoteRestClient {
  HelixRemoteRestClientImpl({
    required Uri baseUri,
    required int timeoutMs,
    this._tokenProvider,
    HttpClient? httpClient,
  }) : _baseUri = baseUri,
       _timeout = Duration(milliseconds: timeoutMs),
       _httpClient =
           httpClient ??
           (() {
             final client = HttpClient();
             client.connectionTimeout = Duration(milliseconds: timeoutMs);
             return client;
           })();

  final Uri _baseUri;
  final Duration _timeout;
  final String? Function()? _tokenProvider;
  final HttpClient _httpClient;

  String? _accessToken;

  @override
  set accessToken(String? token) => _accessToken = token;

  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
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
  }) async {
    final canRetry = _isSafeMethod(method) || idempotencyKey != null;
    final maxAttempts = canRetry ? 3 : 1;
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await _sendOnce(
          method,
          path,
          body: body,
          extraHeaders: extraHeaders,
          idempotencyKey: idempotencyKey,
        );
      } on RemoteRestException catch (e) {
        if (attempt >= maxAttempts || !_isRetryableStatus(e.statusCode)) {
          rethrow;
        }
        await Future<void>.delayed(e.retryAfter ?? _retryDelay(attempt));
      } on TimeoutException catch (e) {
        if (attempt >= maxAttempts) {
          throw RemoteRestException(
            message: 'REST request timed out: ${e.message ?? method}',
            uri: _baseUri.resolve(path),
          );
        }
        await Future<void>.delayed(_retryDelay(attempt));
      } on SocketException catch (e) {
        if (attempt >= maxAttempts) {
          throw RemoteRestException(
            message: 'REST socket failure: ${e.message}',
            uri: _baseUri.resolve(path),
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
  }) async {
    final uri = _baseUri.resolve(path);
    final correlationId = _newCorrelationId();
    final req = await _httpClient.openUrl(method, uri).timeout(_timeout);
    req.headers.set('Content-Type', 'application/json');
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

  @override
  Future<Map<String, dynamic>> registerAccount({
    required String accountId,
    required String username,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
    required String deviceName,
  }) => _request(
    'POST',
    '/api/v1/accounts/register',
    body: {
      'registration_version': 2,
      'account_id': accountId,
      'username': username,
      'account_identity_public_key': accountIdentityPublicKey,
      'device_id': deviceId,
      'device_signing_public_key': deviceSigningPublicKey,
      'device_agreement_public_key': deviceAgreementPublicKey,
      'account_registration_signature': accountRegistrationSignature,
      'device_registration_signature': deviceRegistrationSignature,
      'device_name': deviceName,
    },
  );

  @override
  Future<Map<String, dynamic>> getChallenge({
    required String accountId,
    required String deviceId,
  }) => _request(
    'GET',
    '/api/v1/accounts/challenge?account_id=$accountId&device_id=$deviceId',
  );

  @override
  Future<Map<String, dynamic>> loginDevice({
    required String accountId,
    required String deviceId,
    required String signature,
  }) => _request(
    'POST',
    '/api/v1/accounts/login',
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
        '/api/v1/accounts/refresh',
        body: {'refresh_token': refreshToken},
      );

  @override
  Future<List<RemoteDevice>> listDevices() async {
    final data = await _request('GET', '/api/v1/accounts/devices');
    final list = data['devices'] as List<dynamic>;
    return list
        .map((e) => RemoteDevice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> revokeDevice(String deviceId) async {
    await _request(
      'POST',
      '/api/v1/accounts/devices/revoke',
      body: {'device_id': deviceId},
    );
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
      '/api/v1/prekeys/publish',
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
      _request('GET', '/api/v1/prekeys/bundle?account_id=$accountId');

  @override
  Future<Map<String, dynamic>> sendContactRequest({
    required String peerAccountId,
  }) => _request(
    'POST',
    '/api/v1/contacts/requests',
    body: {'peer_account_id': peerAccountId},
  );

  @override
  Future<void> acceptContactRequest(String requestId) async {
    await _request(
      'POST',
      '/api/v1/contacts/requests/accept',
      body: {'request_id': requestId},
    );
  }

  @override
  Future<Map<String, dynamic>> requestAttachmentUpload({
    required int fileSize,
    required String fileHash,
  }) => _request(
    'POST',
    '/api/v1/attachments/upload',
    body: {'file_size': fileSize, 'file_hash': fileHash},
  );

  @override
  Future<Map<String, dynamic>> requestAttachmentDownload(String fileId) async {
    final data = await _request('GET', '/api/v1/attachments/download/$fileId');
    return data;
  }

  @override
  Future<Map<String, dynamic>> sendCallSignal({
    required String targetDeviceId,
    required Map<String, dynamic> payload,
  }) => _request(
    'POST',
    '/api/v1/calls/signal',
    body: {'target_device_id': targetDeviceId, 'payload': payload},
  );

  @override
  Future<void> requestAccountDeletion({required String confirmation}) async {
    await _request(
      'DELETE',
      '/api/v1/account/delete',
      body: {'confirmation': confirmation},
    );
  }

  @override
  Future<Map<String, dynamic>> exportData() =>
      _request('GET', '/api/v1/privacy/export');

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
    '/api/v1/backups/',
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
  Future<Map<String, dynamic>> downloadBackup() =>
      _request('GET', '/api/v1/backups/');

  @override
  Future<void> close() async {
    _httpClient.close(force: true);
  }
}

class RemoteRestException extends HttpException {
  const RemoteRestException({
    required String message,
    Uri? uri,
    this.statusCode,
    this.correlationId,
    this.retryAfter,
  }) : super(message, uri: uri);

  final int? statusCode;
  final String? correlationId;
  final Duration? retryAfter;
}
