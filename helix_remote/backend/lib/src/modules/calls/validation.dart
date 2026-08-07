part of '../calls.dart';

/// Input validation and rate limiting for the signaling path - the part
/// that decides whether a frame is well-formed and allowed, separately from
/// what routing then does with it.
///
/// Every bound here is a real abuse limit, not a tidiness check: SDP and
/// candidate sizes cap what an unauthenticated-ish peer can push through a
/// relay, and the per-account/device/IP windows cap how fast.
mixin CallsValidation on CallsModuleBase {
  @override
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
    final callerDisplayName = _boundedDisplay(
      payload['caller_display_name'],
      maxLength: 80,
    );
    final callerPhoneLast4 = _boundedDisplay(
      payload['caller_phone_last4'],
      maxLength: 4,
    );
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
        callerDisplayName: callerDisplayName,
        callerPhoneLast4: callerPhoneLast4,
        // Deliberately not rejected when unrecognised. An unknown policy is
        // not a malformed frame, it is a client this server is older than,
        // and `fromWire` already resolves anything it does not recognise to
        // the strictest option. Rejecting instead would turn a forward-
        // compatible client into a broken one.
        declaredPolicy: CallMediaPolicy.fromWire(payload['ip_privacy']),
      ),
    );
  }

  bool _validId(String? value) =>
      value != null &&
      value.isNotEmpty &&
      value.length <= _maxIdLength &&
      RegExp(r'^[A-Za-z0-9._:@-]+$').hasMatch(value);

  String? _boundedDisplay(Object? value, {required int maxLength}) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    return trimmed;
  }

  @override
  String? _string(Object? value) => value is String ? value : null;

  @override
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

  @override
  int _httpStatusFor(Map<String, dynamic> result) {
    return switch (result['status']) {
      // 'dropped' is a 200: the frame was well-formed and accepted, and the
      // server chose not to relay it. Reporting a client error would tell a
      // caller to retry something that will always be dropped.
      'delivered' || 'queued' || 'partial' || 'duplicate' || 'dropped' => 200,
      'no_active_devices' => 409,
      'answered_elsewhere' => 409,
      'rate_limited' => 429,
      'expired' => 410,
      _ => 400,
    };
  }
}
