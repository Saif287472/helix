part of '../calls.dart';

/// The pending-call queue a callee's device works through after being
/// woken by push: list them, then accept, decline, cancel or expire one.
mixin CallsPendingHandlers on CallsModuleBase {
  Future<Response> _handlePendingCalls(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null)
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    final key = '${auth['account_id']}:${auth['device_id']}';
    if (_pendingFetchRate.count(key) > _maxPendingFetchesPerMinute) {
      _increment('rate_limited');
      throw AppError.tooManyRequests('pending call fetch rate limit exceeded');
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
    } on AppError {
      rethrow;
    } catch (e, st) {
      logServerError('[CALL_PENDING_ERROR] $e\n$st');
      throw AppError.internal();
    }
  }

  Future<Response> _handleAcceptPending(Request request, String callId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null)
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = db.getPendingCall(callId);
    if (session == null ||
        !_isPendingCalleeDevice(
          session: session,
          accountId: auth['account_id'] as String,
          deviceId: auth['device_id'] as String,
          now: now,
        )) {
      throw AppError.notFound('pending call not found');
    }
    final deviceId = auth['device_id'] as String;
    final accepted = db.markPendingCallAnswered(
      callId: callId,
      targetDeviceId: deviceId,
      now: now,
    );
    if (accepted) {
      _notifyAnsweredElsewhere(
        callId: callId,
        answeredDeviceId: deviceId,
        requestId: null,
        session: session,
        now: now,
      );
    }
    final updatedSession = db.getPendingCall(callId) ?? session;
    return _json(200, {
      'status': 'accepted',
      'call_id': callId,
      'call': _pendingCallResponse(updatedSession),
    });
  }

  Future<Response> _handleDeclinePending(Request request, String callId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null)
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    final session = db.getPendingCall(callId);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (session == null ||
        !_isPendingCalleeDevice(
          session: session,
          accountId: auth['account_id'] as String,
          deviceId: auth['device_id'] as String,
          now: now,
        )) {
      throw AppError.notFound('pending call not found');
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
    logServerError(
      '[CALL] declined call_id=$callId device=${auth['device_id']}',
    );
    return _json(200, {'status': 'declined', 'call_id': callId});
  }

  Future<Response> _handleCancelPending(Request request, String callId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null)
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    final session = db.getPendingCall(callId);
    if (session == null ||
        session['caller_account_id'] != auth['account_id'] ||
        session['caller_device_id'] != auth['device_id']) {
      throw AppError.notFound('pending call not found');
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
    logServerError(
      '[CALL] cancelled call_id=$callId device=${auth['device_id']}',
    );
    return _json(200, {'status': 'cancelled', 'call_id': callId});
  }

  Future<Response> _handleExpirePending(Request request, String callId) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null)
      throw AppError.forbidden(
        'Unauthorized',
        code: RemoteErrorCode.unauthorized,
      );
    final session = db.getPendingCall(callId);
    if (session == null) throw AppError.notFound('pending call not found');
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
      throw AppError.notFound('pending call not found');
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
}
