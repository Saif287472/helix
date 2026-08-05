import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/call_media_policy.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/federation.dart';
import 'package:helix_remote_backend/src/push_provider.dart';
import 'package:helix_remote_backend/src/server_log.dart';
import 'package:helix_remote_backend/src/websocket.dart';

/// Milestone 5.1: federated call signaling has no home-server-authority
/// concept the way groups do (ADR 020) — a call is inherently bilateral
/// (caller/callee), so each server just relays signals to whichever domain
/// the *other* party lives on, mirroring the message-proxy pattern from
/// Milestone 3. See [FederationClient.proxyCallSignal] and
/// `S2SModule._callsSignalHandler`.
part 'calls/federation.dart';
part 'calls/signaling.dart';
part 'calls/pending.dart';
part 'calls/delivery.dart';
part 'calls/push_tokens.dart';
part 'calls/validation.dart';
part 'calls/support.dart';

/// What every part of this module may assume exists.
///
/// The fields are the module's collaborators and its shared counters; the
/// methods are helpers implemented in one part and called from another,
/// which Dart mixins can only see if they are declared on the `on` type.
// Signaling bounds and rate limits, plus the accepted frame types. Top
// level rather than class statics so every part file can read them - a
// mixin's statics are not inherited by the class that mixes it in.
const int _maxCredentialsPerHour = 10;
const int _maxDeviceCredentialsPerHour = 10;
const int _credentialValiditySeconds = 3600;
const int _pendingCallTtlMs = 45000;
const int _maxIdLength = 128;
const int _maxSdpLength = 65536;
const int _maxCandidateLength = 4096;
const int _maxSignalsPerMinute = 120;
const int _maxPendingFetchesPerMinute = 30;
const int _maxOffersPerMinute = 10;
const int _maxConcurrentCallsPerAccount = 1;
int _turnCredentialLogNonce = 0;
const Set<String> _signalTypes = {
  'offer',
  'answer',
  'ice',
  'decline',
  'busy',
  'cancel',
  'end',
};

abstract class CallsModuleBase {
  BackendDatabase get db;
  WebSocketRelay get wsRelay;
  String get turnSecret;
  String get turnUrl;
  FederationClient? get federationClient;
  String? get localDomain;
  PushProvider get pushProvider;

  _WindowCounter get _accountSignalRate;
  _WindowCounter get _deviceSignalRate;
  _WindowCounter get _ipSignalRate;
  _WindowCounter get _pendingFetchRate;

  void _increment(String key);
  Future<Map<String, dynamic>?> _readJson(Request request);
  Response _json(int status, Map<String, dynamic> body);
  String _newId(String prefix);

  // Implemented by CallsFederationHelpers.
  bool _isExternal(String accountId);
  String _qualify(String accountId);
  Future<Map<String, dynamic>?> _proxyCallSignal({
    required String domain,
    required String senderAccountId,
    required String senderDeviceId,
    required Map<String, dynamic> canonicalPayload,
    String? requestId,
  });
  Future<Map<String, dynamic>?> _proxySessionSignal({
    required _ParsedCallSignal signal,
    required Map<String, dynamic> session,
    required String senderAccountId,
    required String senderDeviceId,
    required String targetAccountId,
    required String? targetDeviceId,
    required String? requestId,
    required int now,
  });

  // Implemented by CallsSignalingHandlers.
  Future<Map<String, dynamic>> _routeSignal({
    required String accountId,
    required String deviceId,
    required String? clientIp,
    required Map<String, dynamic> message,
    bool trustedRemote = false,
  });

  // Implemented by CallsDeliveryHelpers.
  Future<Map<String, dynamic>> _sendToCaller({
    required _ParsedCallSignal signal,
    required Map<String, dynamic> session,
    required String senderDeviceId,
    required String? requestId,
    required int now,
  });
  Future<Map<String, dynamic>> _sendToCalleeDevices({
    required _ParsedCallSignal signal,
    required Map<String, dynamic> session,
    required String senderDeviceId,
    required String? requestId,
    required int now,
  });
  Future<Map<String, dynamic>> _sendToDevice({
    required String targetDeviceId,
    required _ParsedCallSignal signal,
    required Map<String, dynamic> session,
    required String senderAccountId,
    required String senderDeviceId,
    required String targetAccountId,
    required String? requestId,
    required int now,
  });
  void _notifyAnsweredElsewhere({
    required String callId,
    required String answeredDeviceId,
    required String? requestId,
    required Map<String, dynamic> session,
    required int now,
  });
  bool _deliverSignal(
    String targetDeviceId,
    Map<String, dynamic> payload, {
    String? requestId,
  });
  void _enqueueCallWake(String targetDeviceId, String callId);
  bool _isPendingCalleeDevice({
    required Map<String, dynamic> session,
    required String accountId,
    required String deviceId,
    required int now,
    bool allowExpired = false,
  });
  Map<String, dynamic> _pendingCallResponse(Map<String, dynamic> call);

  // Implemented by CallsValidation.
  _ParseResult _parseSignal(Map<String, dynamic> payload);
  String? _string(Object? value);
  Map<String, dynamic>? _checkSignalRateLimit({
    required String accountId,
    required String deviceId,
    required String? clientIp,
  });
  int _httpStatusFor(Map<String, dynamic> result);
}

class CallsModule extends CallsModuleBase
    with
        CallsFederationHelpers,
        CallsSignalingHandlers,
        CallsPendingHandlers,
        CallsDeliveryHelpers,
        CallsPushTokenHandlers,
        CallsValidation {
  CallsModule(
    this.db,
    this.wsRelay, {
    required this.turnSecret,
    required this.turnUrl,
    this.federationClient,
    this.localDomain,
  }) {
    wsRelay.setCallSignalHandler(_handleWebSocketSignal);
  }

  @override
  final BackendDatabase db;
  @override
  final WebSocketRelay wsRelay;
  @override
  final String turnSecret;
  @override
  final String turnUrl;
  @override
  final FederationClient? federationClient;
  @override
  final String? localDomain;

  @override
  final _accountSignalRate = _WindowCounter(const Duration(minutes: 1));
  @override
  final _deviceSignalRate = _WindowCounter(const Duration(minutes: 1));
  @override
  final _ipSignalRate = _WindowCounter(const Duration(minutes: 1));
  @override
  final _pendingFetchRate = _WindowCounter(const Duration(minutes: 1));
  final _metrics = <String, int>{
    'attempts': 0,
    'offers_delivered': 0,
    'offers_queued': 0,
    'answers': 0,
    'declines': 0,
    'busy': 0,
    'failures': 0,
    'completed': 0,
    'rate_limited': 0,
    'rejected': 0,
    'turn_credentials_success': 0,
    'turn_credentials_error': 0,
    // Declared up front rather than created on first use, so "no client has
    // ever violated its policy" reads as 0 instead of as a missing key.
    'policy_candidates_dropped': 0,
    'policy_sdp_candidates_stripped': 0,
  };

  @override
  // F7: push provider for offline call wake (optional; noop when unconfigured).
  late PushProvider pushProvider = const NoopPushProvider();

  Handler get router {
    final r = Router();
    r.get('/turn-credentials', _handleTurnCredentials);
    r.post('/signal', _handleSignal);
    r.get('/pending', _handlePendingCalls);
    r.post('/pending/<callId>/accept', _handleAcceptPending);
    r.post('/pending/<callId>/decline', _handleDeclinePending);
    r.post('/pending/<callId>/cancel', _handleCancelPending);
    r.post('/pending/<callId>/expire', _handleExpirePending);
    // F7 endpoints
    r.post('/push-token', _handleRegisterPushToken);
    r.delete('/push-token', _handleDeregisterPushToken);
    r.post('/metrics', _handleCallMetrics);
    return withAppErrorHandling(r.call);
  }

  Map<String, int> metrics() => Map.unmodifiable(_metrics);

  @override
  void _increment(String key) {
    _metrics[key] = (_metrics[key] ?? 0) + 1;
  }

  // ---------------------------------------------------------------------
  // Milestone 5.1: federation helpers
  // ---------------------------------------------------------------------

  Future<Response> _handleTurnCredentials(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }
    final accountId = auth['account_id'] as String;
    final deviceId = auth['device_id'] as String;
    final urls = resolveTurnUrls(turnUrl);
    if (turnSecret.trim().isEmpty || urls.isEmpty) {
      _increment('turn_credentials_error');
      throw AppError.serviceUnavailable(
        'TURN is not configured',
      ).withDetails({'turn_configured': false});
    }

    final issuedAt = DateTime.now().millisecondsSinceEpoch;
    db.purgeExpiredTurnCredentialLogs(issuedAt);
    final count = db.getTurnCredentialCountLastHour(accountId);
    final deviceCount = db.getTurnCredentialCountLastHourForDevice(deviceId);
    if (count >= _maxCredentialsPerHour ||
        deviceCount >= _maxDeviceCredentialsPerHour) {
      _increment('turn_credentials_error');
      throw AppError.tooManyRequests(
        'TURN credential quota exceeded. Try again later.',
      ).withDetails({
        'account_quota_exceeded': count >= _maxCredentialsPerHour,
        'device_quota_exceeded': deviceCount >= _maxDeviceCredentialsPerHour,
      });
    }

    final expiresAtSeconds = issuedAt ~/ 1000 + _credentialValiditySeconds;

    final username = '$expiresAtSeconds:$accountId:$deviceId';
    final credential = _hmacSha1Base64(turnSecret, username);

    final logId =
        '${accountId}_${DateTime.now().microsecondsSinceEpoch}_${_turnCredentialLogNonce++}';
    db.logTurnCredential(
      logId: logId,
      accountId: accountId,
      deviceId: deviceId,
      issuedAt: issuedAt,
      expiresAt: expiresAtSeconds * 1000,
    );

    _increment('turn_credentials_success');
    // F7: refresh hint — tell clients to renew 5 minutes before expiry.
    final refreshInSeconds = _credentialValiditySeconds - 300;
    return Response.ok(
      jsonEncode({
        'url': urls.first,
        'urls': urls,
        'username': username,
        'credential': credential,
        'expires_at': expiresAtSeconds,
        'clock_skew_tolerance_ms': 30000,
      }),
      headers: {
        'Content-Type': 'application/json',
        'X-Helix-Turn-Refresh-In': '$refreshInSeconds',
      },
    );
  }

  @override
  Future<Map<String, dynamic>?> _readJson(Request request) async {
    try {
      final raw = await request.readAsString();
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Response _json(int status, Map<String, dynamic> body) {
    final responseBody = jsonEncode(body);
    if (status == 200) {
      return Response.ok(
        responseBody,
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response(
      status,
      body: responseBody,
      headers: {'Content-Type': 'application/json'},
    );
  }

  @override
  String _newId(String prefix) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return '${prefix}_${base64Url.encode(bytes).replaceAll('=', '')}';
  }

  static String _hmacSha1Base64(String secret, String message) {
    final hmac = Hmac(sha1, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(message));
    return base64Encode(digest.bytes);
  }

  static List<String> resolveTurnUrls(String configured) {
    final explicit = configured
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (explicit.isEmpty) return const [];
    return explicit.where(_isUsableTurnUrl).toList(growable: false);
  }

  static bool _isUsableTurnUrl(String url) {
    if (!url.startsWith('turn:') && !url.startsWith('turns:')) return false;
    if (!url.contains(':')) return false;
    return true;
  }
}
