import 'dart:convert';
import 'dart:io' show stderr;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/push_provider.dart';
import 'package:helix_remote_backend/src/websocket.dart';

class CallsModule {
  CallsModule(
    this.db,
    this.wsRelay, {
    required this.turnSecret,
    required this.turnUrl,
  }) {
    wsRelay.setCallSignalHandler(_handleWebSocketSignal);
  }

  final BackendDatabase db;
  final WebSocketRelay wsRelay;
  final String turnSecret;
  final String turnUrl;

  static const int _maxCredentialsPerHour = 10;
  static const int _maxDeviceCredentialsPerHour = 10;
  static const int _credentialValiditySeconds = 3600;
  static const int _pendingCallTtlMs = 45000;
  static const int _maxIdLength = 128;
  static const int _maxSdpLength = 65536;
  static const int _maxCandidateLength = 4096;
  static const int _maxSignalsPerMinute = 120;
  static const int _maxPendingFetchesPerMinute = 30;
  static const int _maxOffersPerMinute = 10;
  static const int _maxConcurrentCallsPerAccount = 1;
  static int _turnCredentialLogNonce = 0;

  final _accountSignalRate = _WindowCounter(const Duration(minutes: 1));
  final _deviceSignalRate = _WindowCounter(const Duration(minutes: 1));
  final _ipSignalRate = _WindowCounter(const Duration(minutes: 1));
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
  };

  static const Set<String> _signalTypes = {
    'offer',
    'answer',
    'ice',
    'decline',
    'busy',
    'cancel',
    'end',
  };

  // F7: push provider for offline call wake (optional; noop when unconfigured).
  late PushProvider pushProvider = const NoopPushProvider();

  Router get router {
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
    return r;
  }

  Map<String, int> metrics() => Map.unmodifiable(_metrics);

  Future<Response> _handleTurnCredentials(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      return _json(403, {'error': 'Unauthorized'});
    }
    final accountId = auth['account_id'] as String;
    final deviceId = auth['device_id'] as String;
    final urls = resolveTurnUrls(turnUrl);
    if (turnSecret.trim().isEmpty || urls.isEmpty) {
      _increment('turn_credentials_error');
      return _json(503, {
        'error': 'TURN is not configured',
        'turn_configured': false,
      });
    }

    final issuedAt = DateTime.now().millisecondsSinceEpoch;
    db.purgeExpiredTurnCredentialLogs(issuedAt);
    final count = db.getTurnCredentialCountLastHour(accountId);
    final deviceCount = db.getTurnCredentialCountLastHourForDevice(deviceId);
    if (count >= _maxCredentialsPerHour ||
        deviceCount >= _maxDeviceCredentialsPerHour) {
      _increment('turn_credentials_error');
      return _json(429, {
        'error': 'TURN credential quota exceeded. Try again later.',
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

  Future<Response> _handleSignal(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _json(403, {'error': 'Unauthorized'});
    final body = await _readJson(request);
    if (body == null) return _json(400, {'error': 'Invalid JSON body'});
    try {
      final result = await _routeSignal(
        accountId: auth['account_id'] as String,
        deviceId: auth['device_id'] as String,
        clientIp: request.context['client_ip'] as String?,
        message: body,
      );
      return _json(_httpStatusFor(result), result);
    } catch (e, st) {
      stderr.writeln('[CALL_SIGNAL_ERROR] $e\n$st');
      return _json(500, {'status': 'error', 'reason': 'signal handler: $e'});
    }
  }

  Future<Map<String, dynamic>> _handleWebSocketSignal({
    required String accountId,
    required String deviceId,
    required Map<String, dynamic> message,
  }) {
    return _routeSignal(
      accountId: accountId,
      deviceId: deviceId,
      clientIp: 'websocket',
      message: message,
    );
  }

  Future<Map<String, dynamic>> _routeSignal({
    required String accountId,
    required String deviceId,
    required String? clientIp,
    required Map<String, dynamic> message,
  }) async {
    final rateLimit = _checkSignalRateLimit(
      accountId: accountId,
      deviceId: deviceId,
      clientIp: clientIp,
    );
    if (rateLimit != null) return rateLimit;

    final requestId = _string(message['request_id']);
    final payloadValue = message['payload'] ?? message;
    if (payloadValue is! Map<String, dynamic>) {
      return {'status': 'rejected', 'reason': 'payload must be an object'};
    }

    final payload = Map<String, dynamic>.of(payloadValue);
    payload.putIfAbsent(
      'callee_account_id',
      () => message['target_account_id'],
    );
    payload.putIfAbsent('target_device_id', () => message['target_device_id']);
    final parsed = _parseSignal(payload);
    if (parsed.error != null) {
      _increment('rejected');
      return {'status': 'rejected', 'reason': parsed.error};
    }
    final signal = parsed.signal!;
    final now = DateTime.now().millisecondsSinceEpoch;
    db.expirePendingCalls(now);
    db.purgeOldCallSignalRequests(
      now - const Duration(hours: 1).inMilliseconds,
    );

    if (requestId != null &&
        !db.rememberCallSignalRequest(
          callId: signal.callId,
          senderDeviceId: deviceId,
          requestId: requestId,
          createdAt: now,
        )) {
      return {'status': 'duplicate', 'request_id': requestId};
    }

    if (signal.signalType == 'offer') {
      _increment('attempts');
      return _routeOffer(
        accountId: accountId,
        deviceId: deviceId,
        signal: signal,
        requestId: requestId,
        now: now,
      );
    }
    return _routeSessionSignal(
      accountId: accountId,
      deviceId: deviceId,
      signal: signal,
      requestId: requestId,
      now: now,
    );
  }

  Map<String, dynamic> _routeOffer({
    required String accountId,
    required String deviceId,
    required _ParsedCallSignal signal,
    required String? requestId,
    required int now,
  }) {
    final calleeAccountId = signal.calleeAccountId;
    if (calleeAccountId == null) {
      return {'status': 'rejected', 'reason': 'callee_account_id is required'};
    }
    if (calleeAccountId == accountId) {
      return {'status': 'rejected', 'reason': 'self-calls are not supported'};
    }
    if (!db.areContacts(accountId, calleeAccountId) ||
        !db.areContacts(calleeAccountId, accountId)) {
      _increment('rejected');
      return {
        'status': 'rejected',
        'reason': 'callee is not an accepted contact',
      };
    }
    if (_accountSignalRate.count('offer:$accountId') > _maxOffersPerMinute) {
      _increment('rate_limited');
      return {'status': 'rate_limited', 'reason': 'call creation rate limit'};
    }
    if (db.countActivePendingCallsForAccount(accountId: accountId, now: now) >=
            _maxConcurrentCallsPerAccount ||
        db.countActivePendingCallsForAccount(
              accountId: calleeAccountId,
              now: now,
            ) >=
            _maxConcurrentCallsPerAccount) {
      _increment('rejected');
      return {'status': 'rejected', 'reason': 'concurrent call limit reached'};
    }
    final devices = db.getDevices(calleeAccountId);
    if (devices.isEmpty) {
      return {'status': 'no_active_devices', 'call_id': signal.callId};
    }

    final targetDeviceIds = devices
        .map((device) => device['device_id'] as String)
        .toList();
    final expiresAt = now + _pendingCallTtlMs;
    db.createPendingCall(
      callId: signal.callId,
      callerAccountId: accountId,
      callerDeviceId: deviceId,
      calleeAccountId: calleeAccountId,
      isVideo: signal.isVideo,
      offerSdp: signal.sdp,
      createdAt: now,
      expiresAt: expiresAt,
      targetDeviceIds: targetDeviceIds,
    );
    stderr.writeln(
      '[CALL] offer_received call_id=${signal.callId} '
      'caller=$accountId callee=$calleeAccountId '
      'devices=${targetDeviceIds.length} video=${signal.isVideo}',
    );

    final canonical = signal.toCanonicalPayload(
      callerAccountId: accountId,
      callerDeviceId: deviceId,
      calleeAccountId: calleeAccountId,
      targetDeviceId: null,
      createdAt: now,
      expiresAt: expiresAt,
    );

    var delivered = 0;
    for (final targetDeviceId in targetDeviceIds) {
      final targetPayload = {...canonical, 'target_device_id': targetDeviceId};
      if (_deliverSignal(targetDeviceId, targetPayload, requestId: requestId)) {
        delivered++;
      } else {
        _enqueueCallWake(targetDeviceId, signal.callId);
      }
    }
    if (delivered > 0) {
      _increment('offers_delivered');
    } else {
      _increment('offers_queued');
    }

    return {
      'status': delivered == targetDeviceIds.length
          ? 'delivered'
          : delivered == 0
          ? 'queued'
          : 'partial',
      'delivered': delivered > 0,
      'call_id': signal.callId,
      'delivered_count': delivered,
      'queued_count': targetDeviceIds.length - delivered,
      'target_device_ids': targetDeviceIds,
      'expires_at': expiresAt,
    };
  }

  Map<String, dynamic> _routeSessionSignal({
    required String accountId,
    required String deviceId,
    required _ParsedCallSignal signal,
    required String? requestId,
    required int now,
  }) {
    final session = db.getPendingCall(signal.callId);
    if (session == null) {
      return {'status': 'expired', 'reason': 'unknown or ended call'};
    }
    final sessionStatus = session['status'] as String;
    if (sessionStatus != 'RINGING' && sessionStatus != 'ANSWERED') {
      return {'status': 'expired', 'reason': 'call is no longer pending'};
    }
    if ((session['expires_at'] as int) <= now) {
      db.markPendingCallTerminal(
        callId: signal.callId,
        status: 'EXPIRED',
        now: now,
      );
      return {'status': 'expired', 'reason': 'call expired'};
    }

    final callerAccountId = session['caller_account_id'] as String;
    final callerDeviceId = session['caller_device_id'] as String;
    final calleeAccountId = session['callee_account_id'] as String;
    final isCaller = accountId == callerAccountId && deviceId == callerDeviceId;
    final isCallee = accountId == calleeAccountId;
    final targetDeviceIds = db.getPendingCallTargetDevices(signal.callId);
    if (!isCaller && !isCallee) {
      return {'status': 'rejected', 'reason': 'not a call participant'};
    }
    if (isCallee && !db.isDeviceActive(calleeAccountId, deviceId)) {
      return {'status': 'rejected', 'reason': 'callee device is not active'};
    }
    if (isCallee && !targetDeviceIds.contains(deviceId)) {
      return {'status': 'rejected', 'reason': 'callee device was not targeted'};
    }

    final terminal = {'decline', 'busy', 'cancel', 'end'};
    if (signal.signalType == 'answer') {
      _increment('answers');
      if (!isCallee) {
        return {
          'status': 'rejected',
          'reason': 'only callee devices can answer',
        };
      }
      final accepted = db.markPendingCallAnswered(
        callId: signal.callId,
        targetDeviceId: deviceId,
        now: now,
      );
      if (!accepted) {
        return {'status': 'answered_elsewhere', 'call_id': signal.callId};
      }
      _notifyAnsweredElsewhere(
        callId: signal.callId,
        answeredDeviceId: deviceId,
        requestId: requestId,
        session: session,
        now: now,
      );
      return _sendToCaller(
        signal: signal,
        session: session,
        senderDeviceId: deviceId,
        requestId: requestId,
        now: now,
      );
    }

    if (terminal.contains(signal.signalType)) {
      if (signal.signalType == 'decline') _increment('declines');
      if (signal.signalType == 'busy') _increment('busy');
      if (signal.signalType == 'end') _increment('completed');
      if (signal.signalType == 'cancel' && !isCaller) {
        return {'status': 'rejected', 'reason': 'only caller can cancel'};
      }
      final result = isCaller
          ? _sendToCalleeDevices(
              signal: signal,
              session: session,
              senderDeviceId: deviceId,
              requestId: requestId,
              now: now,
            )
          : _sendToCaller(
              signal: signal,
              session: session,
              senderDeviceId: deviceId,
              requestId: requestId,
              now: now,
            );
      db.markPendingCallTerminal(
        callId: signal.callId,
        status: signal.signalType.toUpperCase(),
        now: now,
      );
      return result;
    }

    if (isCaller) {
      final targetDeviceId =
          signal.targetDeviceId ??
          session['answered_by_device_id'] as String? ??
          (db.getPendingCallTargetDevices(signal.callId).length == 1
              ? db.getPendingCallTargetDevices(signal.callId).first
              : null);
      if (targetDeviceId == null) {
        return _sendToCalleeDevices(
          signal: signal,
          session: session,
          senderDeviceId: deviceId,
          requestId: requestId,
          now: now,
        );
      }
      return _sendToDevice(
        targetDeviceId: targetDeviceId,
        signal: signal,
        session: session,
        senderAccountId: callerAccountId,
        senderDeviceId: deviceId,
        targetAccountId: calleeAccountId,
        requestId: requestId,
        now: now,
      );
    }

    return _sendToCaller(
      signal: signal,
      session: session,
      senderDeviceId: deviceId,
      requestId: requestId,
      now: now,
    );
  }

  Future<Response> _handlePendingCalls(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _json(403, {'error': 'Unauthorized'});
    final key = '${auth['account_id']}:${auth['device_id']}';
    if (_pendingFetchRate.count(key) > _maxPendingFetchesPerMinute) {
      _increment('rate_limited');
      return _json(429, {'error': 'pending call fetch rate limit exceeded'});
    }
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      db.expirePendingCalls(now);
      final calls = db
          .getPendingCallsForDevice(
            accountId: auth['account_id'] as String,
            deviceId: auth['device_id'] as String,
            now: now,
          )
          .map((call) => _pendingCallResponse(call))
          .toList(growable: false);
      return _json(200, {'calls': calls});
    } catch (e, st) {
      stderr.writeln('[CALL_PENDING_ERROR] $e\n$st');
      return _json(500, {'status': 'error', 'reason': 'pending handler: $e'});
    }
  }

  Future<Response> _handleAcceptPending(Request request, String callId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _json(403, {'error': 'Unauthorized'});
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = db.getPendingCall(callId);
    if (session == null ||
        !_isPendingCalleeDevice(
          session: session,
          accountId: auth['account_id'] as String,
          deviceId: auth['device_id'] as String,
          now: now,
        )) {
      return _json(404, {'error': 'pending call not found'});
    }
    return _json(200, {
      'status': 'accepted',
      'call_id': callId,
      'call': _pendingCallResponse(session),
    });
  }

  Future<Response> _handleDeclinePending(Request request, String callId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _json(403, {'error': 'Unauthorized'});
    final session = db.getPendingCall(callId);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (session == null ||
        !_isPendingCalleeDevice(
          session: session,
          accountId: auth['account_id'] as String,
          deviceId: auth['device_id'] as String,
          now: now,
        )) {
      return _json(404, {'error': 'pending call not found'});
    }
    _sendToCaller(
      signal: _ParsedCallSignal(
        callId: callId,
        signalType: 'decline',
        isVideo: (session['is_video'] as int) != 0,
      ),
      session: session,
      senderDeviceId: auth['device_id'] as String,
      requestId: null,
      now: now,
    );
    db.markPendingCallTerminal(callId: callId, status: 'DECLINED', now: now);
    stderr.writeln('[CALL] declined call_id=$callId device=${auth['device_id']}');
    return _json(200, {'status': 'declined', 'call_id': callId});
  }

  Future<Response> _handleCancelPending(Request request, String callId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _json(403, {'error': 'Unauthorized'});
    final session = db.getPendingCall(callId);
    if (session == null ||
        session['caller_account_id'] != auth['account_id'] ||
        session['caller_device_id'] != auth['device_id']) {
      return _json(404, {'error': 'pending call not found'});
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _sendToCalleeDevices(
      signal: _ParsedCallSignal(
        callId: callId,
        signalType: 'cancel',
        isVideo: (session['is_video'] as int) != 0,
      ),
      session: session,
      senderDeviceId: auth['device_id'] as String,
      requestId: null,
      now: now,
    );
    db.markPendingCallTerminal(callId: callId, status: 'CANCELLED', now: now);
    stderr.writeln('[CALL] cancelled call_id=$callId device=${auth['device_id']}');
    return _json(200, {'status': 'cancelled', 'call_id': callId});
  }

  Future<Response> _handleExpirePending(Request request, String callId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _json(403, {'error': 'Unauthorized'});
    final session = db.getPendingCall(callId);
    if (session == null) return _json(404, {'error': 'pending call not found'});
    final accountId = auth['account_id'] as String;
    final deviceId = auth['device_id'] as String;
    final isCaller =
        session['caller_account_id'] == accountId &&
        session['caller_device_id'] == deviceId;
    final isTarget = _isPendingCalleeDevice(
      session: session,
      accountId: accountId,
      deviceId: deviceId,
      now: DateTime.now().millisecondsSinceEpoch,
      allowExpired: true,
    );
    if (!isCaller && !isTarget) {
      return _json(404, {'error': 'pending call not found'});
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    db.markPendingCallTerminal(callId: callId, status: 'EXPIRED', now: now);
    db.purgeTerminalPendingCalls(
      now - const Duration(minutes: 5).inMilliseconds,
    );
    return _json(200, {'status': 'expired', 'call_id': callId});
  }

  // ---------------------------------------------------------------------------
  // F7: Push token registration
  // ---------------------------------------------------------------------------

  static const int _maxPushTokenLength = 4096;

  Future<Response> _handleRegisterPushToken(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _json(401, {'error': 'Unauthorized'});
    final body = await _readJson(request);
    if (body == null) return _json(400, {'error': 'Invalid JSON'});
    final pushToken = body['push_token'] as String?;
    final tokenType = (body['token_type'] as String?) ?? 'FCM';
    if (pushToken == null ||
        pushToken.isEmpty ||
        pushToken.length > _maxPushTokenLength) {
      return _json(400, {'error': 'push_token is required (max 4096 chars)'});
    }
    if (tokenType != 'FCM' && tokenType != 'APNS') {
      return _json(400, {'error': 'token_type must be FCM or APNS'});
    }
    final accountId = auth['account_id'] as String;
    final deviceId = auth['device_id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tokenId =
        '${accountId}_${deviceId}_${now}_${_turnCredentialLogNonce++}';
    db.upsertPushToken(
      tokenId: tokenId,
      accountId: accountId,
      deviceId: deviceId,
      pushToken: pushToken,
      tokenType: tokenType,
      now: now,
    );
    return _json(200, {
      'status': 'registered',
      'device_id': deviceId,
      'token_type': tokenType,
    });
  }

  Future<Response> _handleDeregisterPushToken(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _json(401, {'error': 'Unauthorized'});
    db.deletePushToken(deviceId: auth['device_id'] as String);
    return _json(200, {'status': 'deregistered'});
  }

  // ---------------------------------------------------------------------------
  // F7: Privacy-safe call metrics upload
  // ---------------------------------------------------------------------------

  Future<Response> _handleCallMetrics(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _json(401, {'error': 'Unauthorized'});
    final body = await _readJson(request);
    if (body == null) return _json(400, {'error': 'Invalid JSON'});
    final callId = body['call_id'] as String?;
    if (callId == null || callId.isEmpty || callId.length > _maxIdLength) {
      return _json(400, {'error': 'call_id is required'});
    }
    final accountId = auth['account_id'] as String;
    final deviceId = auth['device_id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;
    final metricId = _newId('cm');
    db.saveCallMetrics(
      metricId: metricId,
      callId: callId,
      accountId: accountId,
      deviceId: deviceId,
      connectionType: body['connection_type'] as String?,
      setupTimeMs: body['setup_time_ms'] as int?,
      reconnectCount: (body['reconnect_count'] as int?) ?? 0,
      packetLossPercent: (body['packet_loss_percent'] as num?)?.toDouble(),
      peerRttMs: (body['peer_rtt_ms'] as num?)?.toDouble(),
      callOutcome: body['call_outcome'] as String?,
      durationSeconds: (body['duration_seconds'] as int?) ?? 0,
      recordedAt: now,
    );
    return _json(200, {'status': 'recorded', 'metric_id': metricId});
  }

  Map<String, dynamic> _sendToCaller({
    required _ParsedCallSignal signal,
    required Map<String, dynamic> session,
    required String senderDeviceId,
    required String? requestId,
    required int now,
  }) {
    return _sendToDevice(
      targetDeviceId: session['caller_device_id'] as String,
      signal: signal,
      session: session,
      senderAccountId: session['callee_account_id'] as String,
      senderDeviceId: senderDeviceId,
      targetAccountId: session['caller_account_id'] as String,
      requestId: requestId,
      now: now,
    );
  }

  Map<String, dynamic> _sendToCalleeDevices({
    required _ParsedCallSignal signal,
    required Map<String, dynamic> session,
    required String senderDeviceId,
    required String? requestId,
    required int now,
  }) {
    var delivered = 0;
    final targetDeviceIds = db.getPendingCallTargetDevices(signal.callId);
    for (final targetDeviceId in targetDeviceIds) {
      final result = _sendToDevice(
        targetDeviceId: targetDeviceId,
        signal: signal,
        session: session,
        senderAccountId: session['caller_account_id'] as String,
        senderDeviceId: senderDeviceId,
        targetAccountId: session['callee_account_id'] as String,
        requestId: requestId,
        now: now,
      );
      if (result['status'] == 'delivered') delivered++;
    }
    return {
      'status': delivered == targetDeviceIds.length
          ? 'delivered'
          : delivered == 0
          ? 'queued'
          : 'partial',
      'delivered': delivered > 0,
      'call_id': signal.callId,
      'delivered_count': delivered,
      'queued_count': targetDeviceIds.length - delivered,
    };
  }

  Map<String, dynamic> _sendToDevice({
    required String targetDeviceId,
    required _ParsedCallSignal signal,
    required Map<String, dynamic> session,
    required String senderAccountId,
    required String senderDeviceId,
    required String targetAccountId,
    required String? requestId,
    required int now,
  }) {
    if (!db.isDeviceActive(targetAccountId, targetDeviceId)) {
      return {'status': 'rejected', 'reason': 'target device is not active'};
    }
    final payload = signal.toCanonicalPayload(
      callerAccountId: senderAccountId,
      callerDeviceId: senderDeviceId,
      calleeAccountId: targetAccountId,
      targetDeviceId: targetDeviceId,
      createdAt: now,
      expiresAt: session['expires_at'] as int,
    );
    final delivered = _deliverSignal(
      targetDeviceId,
      payload,
      requestId: requestId,
    );
    if (!delivered) _enqueueCallWake(targetDeviceId, signal.callId);
    return {
      'status': delivered ? 'delivered' : 'queued',
      'delivered': delivered,
      'call_id': signal.callId,
      'target_device_id': targetDeviceId,
    };
  }

  void _notifyAnsweredElsewhere({
    required String callId,
    required String answeredDeviceId,
    required String? requestId,
    required Map<String, dynamic> session,
    required int now,
  }) {
    for (final sibling in db.getPendingCallTargetDevices(callId)) {
      if (sibling == answeredDeviceId) continue;
      final payload = {
        'call_id': callId,
        'caller_account_id': session['caller_account_id'],
        'caller_device_id': session['caller_device_id'],
        'callee_account_id': session['callee_account_id'],
        'target_device_id': sibling,
        'signal_type': 'answered_elsewhere',
        'is_video': (session['is_video'] as int) != 0,
        'created_at': now,
        'expires_at': session['expires_at'],
      };
      _deliverSignal(sibling, payload, requestId: requestId);
    }
  }

  bool _deliverSignal(
    String targetDeviceId,
    Map<String, dynamic> payload, {
    String? requestId,
  }) {
    final envelope = {
      'event_id': _newId('call_evt'),
      'schema_version': 1,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'type': 'call_signal',
      'payload': payload,
    };
    if (requestId != null) envelope['request_id'] = requestId;
    return wsRelay.trySendToDevice(targetDeviceId, envelope);
  }

  void _enqueueCallWake(String targetDeviceId, String callId) {
    final notifId =
        '${targetDeviceId}_call_${DateTime.now().millisecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
    db.enqueueOutbox(
      notifId,
      'PUSH_NOTIFICATION',
      jsonEncode({
        'notification_type': 'incoming_call',
        'call_id': callId,
        'target_device_id': targetDeviceId,
      }),
    );
    stderr.writeln(
      '[CALL] push_wake_enqueued call_id=$callId device=$targetDeviceId',
    );
    // F7: attempt immediate push delivery via stored token when configured.
    if (pushProvider.isConfigured) {
      final tokenRow = db.getPushTokenForDevice(targetDeviceId);
      if (tokenRow != null) {
        final token = tokenRow['push_token'] as String;
        pushProvider
            .deliver(
              token: token,
              data: {
                'notification_type': 'incoming_call',
                'call_id': callId,
                'target_device_id': targetDeviceId,
              },
            )
            .then((_) {
              stderr.writeln(
                '[CALL] push_delivered call_id=$callId device=$targetDeviceId',
              );
            })
            .catchError((Object e) {
              if (e is FcmTokenNotFoundException) {
                // Token is stale — prune it so we stop wasting FCM quota.
                db.deletePushToken(deviceId: targetDeviceId);
                stderr.writeln(
                  '[CALL] push_token_pruned device=$targetDeviceId reason=expired',
                );
              } else {
                stderr.writeln(
                  '[CALL] push_failed device=$targetDeviceId error=$e',
                );
              }
            });
      }
    }
  }

  bool _isPendingCalleeDevice({
    required Map<String, dynamic> session,
    required String accountId,
    required String deviceId,
    required int now,
    bool allowExpired = false,
  }) {
    if (session['callee_account_id'] != accountId) return false;
    if (!allowExpired && session['status'] != 'RINGING') return false;
    if (!allowExpired && (session['expires_at'] as int) <= now) return false;
    if (!db.isDeviceActive(accountId, deviceId)) return false;
    return db
        .getPendingCallTargetDevices(session['call_id'] as String)
        .contains(deviceId);
  }

  Map<String, dynamic> _pendingCallResponse(Map<String, dynamic> call) {
    return {
      'call_id': call['call_id'],
      'caller_account_id': call['caller_account_id'],
      'caller_device_id': call['caller_device_id'],
      'callee_account_id': call['callee_account_id'],
      'is_video': call['is_video'],
      'status': call['status'],
      'created_at': call['created_at'],
      'expires_at': call['expires_at'],
      'answered_by_device_id': call['answered_by_device_id'],
      if (call['offer_sdp'] != null) 'sdp': call['offer_sdp'],
    };
  }

  _ParseResult _parseSignal(Map<String, dynamic> payload) {
    final callId = _string(payload['call_id']);
    final signalType = _string(payload['signal_type']);
    if (!_validId(callId)) return const _ParseResult(error: 'invalid call_id');
    if (signalType == null || !_signalTypes.contains(signalType)) {
      return const _ParseResult(error: 'unknown signal_type');
    }
    final sdp = _string(payload['sdp']);
    if (sdp != null && sdp.length > _maxSdpLength) {
      return const _ParseResult(error: 'sdp too large');
    }
    final candidate = _string(payload['candidate']);
    if (candidate != null && candidate.length > _maxCandidateLength) {
      return const _ParseResult(error: 'candidate too large');
    }
    if (candidate != null &&
        candidate.isNotEmpty &&
        !candidate.startsWith('candidate:')) {
      return const _ParseResult(error: 'invalid candidate');
    }
    final calleeAccountId = _string(payload['callee_account_id']);
    final targetDeviceId = _string(payload['target_device_id']);
    if (calleeAccountId != null && !_validId(calleeAccountId)) {
      return const _ParseResult(error: 'invalid callee_account_id');
    }
    if (targetDeviceId != null && !_validId(targetDeviceId)) {
      return const _ParseResult(error: 'invalid target_device_id');
    }
    final mline = payload['mline_index'];
    if (mline != null && (mline is! int || mline < 0 || mline > 64)) {
      return const _ParseResult(error: 'invalid mline_index');
    }
    return _ParseResult(
      signal: _ParsedCallSignal(
        callId: callId!,
        signalType: signalType,
        calleeAccountId: calleeAccountId,
        targetDeviceId: targetDeviceId,
        isVideo: payload['is_video'] == true,
        sdp: sdp,
        candidate: candidate,
        sdpMid: _string(payload['sdp_mid']),
        mlineIndex: mline as int?,
      ),
    );
  }

  bool _validId(String? value) =>
      value != null &&
      value.isNotEmpty &&
      value.length <= _maxIdLength &&
      RegExp(r'^[A-Za-z0-9._:@-]+$').hasMatch(value);

  String? _string(Object? value) => value is String ? value : null;

  Map<String, dynamic>? _checkSignalRateLimit({
    required String accountId,
    required String deviceId,
    required String? clientIp,
  }) {
    final accountCount = _accountSignalRate.count(accountId);
    final deviceCount = _deviceSignalRate.count(deviceId);
    final ipCount = _ipSignalRate.count(clientIp ?? 'unknown');
    if (accountCount > _maxSignalsPerMinute ||
        deviceCount > _maxSignalsPerMinute ||
        ipCount > _maxSignalsPerMinute) {
      _increment('rate_limited');
      return {
        'status': 'rate_limited',
        'reason': 'call signaling rate limit exceeded',
        'account_quota_exceeded': accountCount > _maxSignalsPerMinute,
        'device_quota_exceeded': deviceCount > _maxSignalsPerMinute,
        'ip_quota_exceeded': ipCount > _maxSignalsPerMinute,
      };
    }
    return null;
  }

  void _increment(String key) {
    _metrics[key] = (_metrics[key] ?? 0) + 1;
  }

  Future<Map<String, dynamic>?> _readJson(Request request) async {
    try {
      final raw = await request.readAsString();
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  int _httpStatusFor(Map<String, dynamic> result) {
    return switch (result['status']) {
      'delivered' || 'queued' || 'partial' || 'duplicate' => 200,
      'no_active_devices' => 409,
      'answered_elsewhere' => 409,
      'rate_limited' => 429,
      'expired' => 410,
      _ => 400,
    };
  }

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

class _WindowCounter {
  _WindowCounter(this.window);

  final Duration window;
  final Map<String, List<int>> _hits = {};

  int count(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - window.inMilliseconds;
    final hits = _hits.putIfAbsent(key, () => []);
    hits.removeWhere((hit) => hit < cutoff);
    hits.add(now);
    return hits.length;
  }
}

class _ParseResult {
  const _ParseResult({this.signal, this.error});

  final _ParsedCallSignal? signal;
  final String? error;
}

class _ParsedCallSignal {
  const _ParsedCallSignal({
    required this.callId,
    required this.signalType,
    required this.isVideo,
    this.calleeAccountId,
    this.targetDeviceId,
    this.sdp,
    this.candidate,
    this.sdpMid,
    this.mlineIndex,
  });

  final String callId;
  final String signalType;
  final String? calleeAccountId;
  final String? targetDeviceId;
  final bool isVideo;
  final String? sdp;
  final String? candidate;
  final String? sdpMid;
  final int? mlineIndex;

  Map<String, dynamic> toCanonicalPayload({
    required String callerAccountId,
    required String callerDeviceId,
    required String calleeAccountId,
    required String? targetDeviceId,
    required int createdAt,
    required int expiresAt,
  }) {
    final payload = {
      'call_id': callId,
      'caller_account_id': callerAccountId,
      'caller_device_id': callerDeviceId,
      'callee_account_id': calleeAccountId,
      'signal_type': signalType,
      'is_video': isVideo,
      if (sdp != null) 'sdp': sdp,
      if (candidate != null) 'candidate': candidate,
      if (sdpMid != null) 'sdp_mid': sdpMid,
      if (mlineIndex != null) 'mline_index': mlineIndex,
      'created_at': createdAt,
      'expires_at': expiresAt,
    };
    if (targetDeviceId != null) payload['target_device_id'] = targetDeviceId;
    return payload;
  }
}
