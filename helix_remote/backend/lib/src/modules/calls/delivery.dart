part of '../calls.dart';

/// Getting a signal onto the right sockets: fan-out to a callee's devices,
/// the answered-elsewhere notice its siblings get, and the push wake-up for
/// a device with no live socket.
mixin CallsDeliveryHelpers on CallsModuleBase {
  @override
  Future<Map<String, dynamic>> _sendToCaller({
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

  @override
  Future<Map<String, dynamic>> _sendToCalleeDevices({
    required _ParsedCallSignal signal,
    required Map<String, dynamic> session,
    required String senderDeviceId,
    required String? requestId,
    required int now,
  }) async {
    final calleeAccountId = session['callee_account_id'] as String;
    final targetDeviceIds = db.getPendingCallTargetDevices(signal.callId);
    if (targetDeviceIds.isEmpty && _isExternal(calleeAccountId)) {
      // Callee's devices are delegated entirely to their home server (see
      // _routeOffer) -- a single proxy call lets that server fan out to
      // whichever of its own local devices are still relevant.
      final proxied = await _proxySessionSignal(
        signal: signal,
        session: session,
        senderAccountId: session['caller_account_id'] as String,
        senderDeviceId: senderDeviceId,
        targetAccountId: calleeAccountId,
        targetDeviceId: null,
        requestId: requestId,
        now: now,
      );
      if (proxied != null) return proxied;
      return {
        'status': 'queued',
        'delivered': false,
        'call_id': signal.callId,
        'delivered_count': 0,
        'queued_count': 0,
      };
    }
    var delivered = 0;
    for (final targetDeviceId in targetDeviceIds) {
      final result = await _sendToDevice(
        targetDeviceId: targetDeviceId,
        signal: signal,
        session: session,
        senderAccountId: session['caller_account_id'] as String,
        senderDeviceId: senderDeviceId,
        targetAccountId: calleeAccountId,
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

  @override
  Future<Map<String, dynamic>> _sendToDevice({
    required String targetDeviceId,
    required _ParsedCallSignal signal,
    required Map<String, dynamic> session,
    required String senderAccountId,
    required String senderDeviceId,
    required String targetAccountId,
    required String? requestId,
    required int now,
  }) async {
    if (_isExternal(targetAccountId)) {
      final proxied = await _proxySessionSignal(
        signal: signal,
        session: session,
        senderAccountId: senderAccountId,
        senderDeviceId: senderDeviceId,
        targetAccountId: targetAccountId,
        targetDeviceId: targetDeviceId,
        requestId: requestId,
        now: now,
      );
      return proxied ??
          {
            'status': 'queued',
            'delivered': false,
            'call_id': signal.callId,
            'target_device_id': targetDeviceId,
          };
    }
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

  @override
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

  @override
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

  @override
  void _enqueueCallWake(String targetDeviceId, String callId) {
    final eventId =
        '${targetDeviceId}_call_${DateTime.now().millisecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
    db.enqueueOutbox(
      eventId,
      'PUSH_NOTIFICATION',
      jsonEncode({
        'notification_type': 'incoming_call',
        'call_id': callId,
        'target_device_id': targetDeviceId,
      }),
    );
    final tokenRow = db.getPushTokenForDevice(targetDeviceId);
    final tokenPresent =
        tokenRow != null &&
        (tokenRow['push_token'] as String?)?.isNotEmpty == true;
    logServerInfo(
      '[CALL_PUSH] wake_enqueued call_id=$callId device=$targetDeviceId '
      'event=$eventId provider_configured=${pushProvider.isConfigured} '
      'token_present=$tokenPresent',
    );
    // F7: attempt immediate push delivery via stored token when configured.
    if (pushProvider.isConfigured && tokenPresent) {
      final token = tokenRow['push_token'] as String;
      logServerInfo(
        '[CALL_PUSH] immediate_attempt call_id=$callId device=$targetDeviceId '
        'event=$eventId',
      );
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
            db.updateOutboxStatus(eventId, 'COMPLETED', 0);
            logServerInfo(
              '[CALL_PUSH] immediate_delivered call_id=$callId '
              'device=$targetDeviceId event=$eventId',
            );
          })
          .catchError((Object e) {
            if (e is FcmTokenNotFoundException) {
              // Token is stale — prune it so we stop wasting FCM quota.
              db.deletePushToken(deviceId: targetDeviceId);
              db.updateOutboxStatus(eventId, 'COMPLETED', 0);
              logServerWarning(
                '[CALL_PUSH] token_pruned device=$targetDeviceId '
                'reason=expired event=$eventId',
              );
            } else {
              logServerError(
                '[CALL_PUSH] immediate_failed call_id=$callId '
                'device=$targetDeviceId event=$eventId error=$e',
              );
            }
          });
    } else {
      logServerWarning(
        '[CALL_PUSH] immediate_skipped call_id=$callId device=$targetDeviceId '
        'event=$eventId reason=${!pushProvider.isConfigured ? 'provider_unconfigured' : 'token_missing'}',
      );
    }
  }

  @override
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

  @override
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
}
