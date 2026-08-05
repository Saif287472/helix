part of '../calls.dart';

/// Device push-token registration, which is what makes a call able to
/// wake a closed app at all.
mixin CallsPushTokenHandlers on CallsModuleBase {
  static const int _maxPushTokenLength = 4096;

  Future<Response> _handleRegisterPushToken(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) throw AppError.unauthorized('Unauthorized');
    final body = await _readJson(request);
    if (body == null) throw AppError.badRequest('Invalid JSON');
    final pushToken = body['push_token'] as String?;
    final tokenType = (body['token_type'] as String?) ?? 'FCM';
    if (pushToken == null ||
        pushToken.isEmpty ||
        pushToken.length > _maxPushTokenLength) {
      throw AppError.badRequest('push_token is required (max 4096 chars)');
    }
    if (tokenType != 'FCM' && tokenType != 'APNS') {
      throw AppError.badRequest('token_type must be FCM or APNS');
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
    if (auth == null) throw AppError.unauthorized('Unauthorized');
    db.deletePushToken(deviceId: auth['device_id'] as String);
    return _json(200, {'status': 'deregistered'});
  }

  // ---------------------------------------------------------------------------
  // F7: Privacy-safe call metrics upload
  // ---------------------------------------------------------------------------

  Future<Response> _handleCallMetrics(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) throw AppError.unauthorized('Unauthorized');
    final body = await _readJson(request);
    if (body == null) throw AppError.badRequest('Invalid JSON');
    final callId = body['call_id'] as String?;
    if (callId == null || callId.isEmpty || callId.length > _maxIdLength) {
      throw AppError.badRequest('call_id is required');
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
}
