part of '../calls.dart';

/// The signaling path proper: one REST endpoint and one WebSocket entry
/// point that both funnel into [_routeSignal], which splits an opening
/// offer from every subsequent in-session frame.
mixin CallsSignalingHandlers on CallsModuleBase {
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
      logServerError('[CALL_SIGNAL_ERROR] $e\n$st');
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
    bool trustedRemote = false,
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
        trustedRemote: trustedRemote,
      );
    }
    return _routeSessionSignal(
      accountId: accountId,
      deviceId: deviceId,
      signal: signal,
      requestId: requestId,
      now: now,
      trustedRemote: trustedRemote,
    );
  }

  Future<Map<String, dynamic>> _routeOffer({
    required String accountId,
    required String deviceId,
    required _ParsedCallSignal signal,
    required String? requestId,
    required int now,
    bool trustedRemote = false,
  }) async {
    final calleeAccountId = signal.calleeAccountId;
    if (calleeAccountId == null) {
      return {'status': 'rejected', 'reason': 'callee_account_id is required'};
    }
    if (calleeAccountId == accountId) {
      return {'status': 'rejected', 'reason': 'self-calls are not supported'};
    }
    final calleeExternal = _isExternal(calleeAccountId);
    if (!trustedRemote) {
      // A signal arriving via trusted S2S already had its trust gate
      // enforced by the sending server before it proxied the offer here
      // (same posture as /s2s/messages/proxy) -- only re-check for
      // locally-originated offers.
      if (_isExternal(accountId) || calleeExternal) {
        if (!db.hasSharedDirectConversation(accountId, calleeAccountId)) {
          _increment('rejected');
          return {
            'status': 'rejected',
            'reason': 'callee is not reachable (no federated conversation)',
          };
        }
      } else if (!db.areContacts(accountId, calleeAccountId) ||
          !db.areContacts(calleeAccountId, accountId)) {
        _increment('rejected');
        return {
          'status': 'rejected',
          'reason': 'callee is not an accepted contact',
        };
      }
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

    if (calleeExternal) {
      if (federationClient == null) {
        return {'status': 'rejected', 'reason': 'Federation is not configured'};
      }
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
        targetDeviceIds: const [],
      );
      final canonical = signal.toCanonicalPayload(
        callerAccountId: _qualify(accountId),
        callerDeviceId: deviceId,
        calleeAccountId: calleeAccountId,
        targetDeviceId: null,
        createdAt: now,
        expiresAt: expiresAt,
      );
      final result = await _proxyCallSignal(
        domain: FederationClient.domainOf(calleeAccountId)!,
        senderAccountId: _qualify(accountId),
        senderDeviceId: deviceId,
        canonicalPayload: canonical,
        requestId: requestId,
      );
      if (result == null) {
        db.markPendingCallTerminal(
          callId: signal.callId,
          status: 'FAILED',
          now: now,
        );
        _increment('rejected');
        return {
          'status': 'rejected',
          'reason': 'failed to reach callee server',
          'call_id': signal.callId,
        };
      }
      _increment(
        result['delivered'] == true ? 'offers_delivered' : 'offers_queued',
      );
      return result;
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
    logServerError(
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

  Future<Map<String, dynamic>> _routeSessionSignal({
    required String accountId,
    required String deviceId,
    required _ParsedCallSignal signal,
    required String? requestId,
    required int now,
    bool trustedRemote = false,
  }) async {
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
    // These two checks are local-device-table lookups that can't be
    // verified for a party whose devices live on another server -- a
    // trusted S2S signal has already been vetted by the sending server.
    if (!trustedRemote) {
      if (isCallee && !db.isDeviceActive(calleeAccountId, deviceId)) {
        return {'status': 'rejected', 'reason': 'callee device is not active'};
      }
      if (isCallee &&
          targetDeviceIds.isNotEmpty &&
          !targetDeviceIds.contains(deviceId)) {
        return {
          'status': 'rejected',
          'reason': 'callee device was not targeted',
        };
      }
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
          ? await _sendToCalleeDevices(
              signal: signal,
              session: session,
              senderDeviceId: deviceId,
              requestId: requestId,
              now: now,
            )
          : await _sendToCaller(
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
}
