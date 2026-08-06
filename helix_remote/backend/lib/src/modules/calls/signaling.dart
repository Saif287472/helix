part of '../calls.dart';

/// The signaling path proper: one REST endpoint and one WebSocket entry
/// point that both funnel into [_routeSignal], which splits an opening
/// offer from every subsequent in-session frame.
///
/// This is also where a call's IP-privacy policy is agreed and enforced.
/// The offer declares the caller's policy and the answer the callee's; the
/// server stores the stricter of the two and applies it to every frame it
/// relays, including the ICE candidates that arrive long after the
/// negotiation. See `call_media_policy.dart` for why the client cannot be
/// the one enforcing this.
mixin CallsSignalingHandlers on CallsModuleBase {
  Future<Response> _handleSignal(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) {
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    }
    final body = await _readJson(request);
    if (body == null) throw AppError.badRequest('Invalid JSON body');
    try {
      final result = await _routeSignal(
        accountId: auth['account_id'] as String,
        deviceId: auth['device_id'] as String,
        clientIp: request.context['client_ip'] as String?,
        message: body,
      );
      return _json(_httpStatusFor(result), result);
    } on AppError {
      rethrow;
    } catch (e, st) {
      logServerError('[CALL_SIGNAL_ERROR] $e\n$st');
      throw AppError.internal();
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

  /// Applies [policy] to one frame.
  ///
  /// Returns the frame to forward, or null when it must not be forwarded at
  /// all. Null is only ever a non-relay trickle candidate: stripping its
  /// address would leave an `ice` signal with nothing in it, and forwarding
  /// that would just confuse the far side.
  _ParsedCallSignal? _applyPolicyToSignal({
    required CallMediaPolicy policy,
    required _ParsedCallSignal signal,
  }) {
    final decision = applyMediaPolicy(
      policy: policy,
      sdp: signal.sdp,
      candidate: signal.candidate,
    );
    if (!decision.allowed) {
      _increment('policy_candidates_dropped');
      return null;
    }
    if (decision.strippedSdpCandidates > 0) {
      _increment('policy_sdp_candidates_stripped');
      // Worth a line in the log: under an honest client this never fires,
      // because a peer that agreed to relay-only does not gather host
      // candidates in the first place. A steady stream of these means a
      // client is not honouring what it negotiated.
      logServerError(
        '[CALL] policy_stripped_sdp_candidates call_id=${signal.callId} '
        'signal=${signal.signalType} policy=${policy.wireName} '
        'removed=${decision.strippedSdpCandidates}',
      );
    }
    return decision.sdp == signal.sdp ? signal : signal.withSdp(decision.sdp);
  }

  Map<String, dynamic> _policyDroppedResponse(_ParsedCallSignal signal) {
    logServerError(
      '[CALL] policy_dropped_candidate call_id=${signal.callId} '
      'signal=${signal.signalType}',
    );
    return {
      'status': 'dropped',
      'reason': 'candidate violates the call media policy',
      'call_id': signal.callId,
    };
  }

  @override
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
    // The offer opens the negotiation, so the caller's declared policy is
    // all there is to go on until the answer arrives. Enforced from this
    // frame onward rather than from the answer: the offer's own SDP can
    // carry inline candidates, and the window between offer and answer is
    // exactly when a callee's device is ringing and most exposed.
    final callerPolicy = signal.declaredPolicy;
    final enforced = _applyPolicyToSignal(policy: callerPolicy, signal: signal);
    if (enforced == null) {
      _increment('rejected');
      return _policyDroppedResponse(signal);
    }
    // Rebinding rather than shadowing: leaving the unfiltered frame in scope
    // under a second name is a trap, since using it below would silently
    // undo the enforcement.
    signal = enforced;

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
        ipPrivacy: callerPolicy.wireName,
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
        effectivePolicy: callerPolicy,
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
      ipPrivacy: callerPolicy.wireName,
      createdAt: now,
      expiresAt: expiresAt,
      targetDeviceIds: targetDeviceIds,
    );
    logServerError(
      '[CALL] offer_received call_id=${signal.callId} '
      'caller=$accountId callee=$calleeAccountId '
      'devices=${targetDeviceIds.length} video=${signal.isVideo} '
      'privacy=${callerPolicy.wireName}',
    );

    final canonical = signal.toCanonicalPayload(
      callerAccountId: accountId,
      callerDeviceId: deviceId,
      calleeAccountId: calleeAccountId,
      targetDeviceId: null,
      createdAt: now,
      expiresAt: expiresAt,
      effectivePolicy: callerPolicy,
    );

    var delivered = 0;
    for (final targetDeviceId in targetDeviceIds) {
      final targetPayload = {...canonical, 'target_device_id': targetDeviceId};
      final socketDelivered = _deliverSignal(
        targetDeviceId,
        targetPayload,
        requestId: requestId,
      );
      if (socketDelivered) {
        delivered++;
      }
      // A live socket does not prove that the app can process the event: the
      // OS may have suspended its Dart isolate while the connection remains
      // registered. The data-only wake is harmless in the foreground because
      // the app handles the call through the socket there.
      _enqueueCallWake(targetDeviceId, signal.callId);
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
    // The deadline is a *ring* timeout, not a limit on how long a call may
    // last. Applying it to an ANSWERED call made every conversation longer
    // than `_pendingCallTtlMs` unable to signal: hanging up was answered
    // with `expired`, so the other end was never told and sat there until
    // its own ICE gave up.
    //
    //   [CALL_SIGNAL] send begin end cid=41717041
    //   [CALL_SIGNAL] end WS rejected status=expired reason=call expired
    //
    // `expirePendingCalls` already scopes itself to RINGING; this check was
    // the one place that did not, so the two disagreed about what an
    // expired call even was.
    //
    // `expires_at` is deliberately left alone rather than pushed out on
    // answer. `countActivePendingCallsForAccount` counts rows with
    // `expires_at > now`, so the deadline passing is also what frees the
    // account's concurrent-call slot - extending it would mean a call whose
    // client died mid-conversation blocked every later call until the new
    // deadline, instead of for the ring timeout.
    if (sessionStatus == 'RINGING' && (session['expires_at'] as int) <= now) {
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

    // The policy agreed for this call, recovered from storage rather than
    // from the frame in hand - a peer does not get to restate (and so
    // loosen) the policy on every candidate it sends.
    var effectivePolicy = CallMediaPolicy.fromWire(session['ip_privacy']);
    if (signal.signalType == 'answer' && isCallee) {
      // The answer is the callee's half of the negotiation, and the only
      // frame allowed to change the policy. Gated on isCallee so a caller
      // cannot rewrite the record by sending a frame labelled 'answer';
      // that frame is rejected a few lines below anyway, and a rejected
      // frame should not leave anything behind.
      //
      // `strictest` means the change can only ever tighten: a callee asking
      // for relay-only gets it even against a caller who asked for direct,
      // and vice versa.
      final agreed = CallMediaPolicy.strictest(
        effectivePolicy,
        signal.declaredPolicy,
      );
      if (agreed != effectivePolicy) {
        db.updatePendingCallIpPrivacy(
          callId: signal.callId,
          ipPrivacy: agreed.wireName,
        );
        effectivePolicy = agreed;
      }
    }
    final enforced = _applyPolicyToSignal(
      policy: effectivePolicy,
      signal: signal,
    );
    if (enforced == null) return _policyDroppedResponse(signal);
    // See the note in _routeOffer: rebound, not shadowed, so the unfiltered
    // frame cannot be reached by anything below.
    signal = enforced;

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
