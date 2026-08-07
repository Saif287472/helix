part of '../calls.dart';

/// Small value types used across the signaling parts. Top-level rather
/// than nested so a part file can name them without reaching through the
/// module.
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
    required this.declaredPolicy,
    this.calleeAccountId,
    this.targetDeviceId,
    this.sdp,
    this.candidate,
    this.sdpMid,
    this.mlineIndex,
    this.callerDisplayName,
    this.callerPhoneLast4,
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
  final String? callerDisplayName;
  final String? callerPhoneLast4;

  /// The IP-privacy policy this frame's sender declared.
  ///
  /// Never null: an absent or unparseable `ip_privacy` resolves to
  /// [CallMediaPolicy.relayOnly] at parse time, so "the sender said nothing"
  /// and "the sender asked for relay-only" are deliberately the same case.
  final CallMediaPolicy declaredPolicy;

  /// This frame with policy enforcement applied.
  ///
  /// Only the SDP can change - a dropped candidate stops the frame from
  /// being forwarded at all, so there is nothing to rewrite in that case.
  _ParsedCallSignal withSdp(String? filteredSdp) => _ParsedCallSignal(
    callId: callId,
    signalType: signalType,
    isVideo: isVideo,
    declaredPolicy: declaredPolicy,
    calleeAccountId: calleeAccountId,
    targetDeviceId: targetDeviceId,
    sdp: filteredSdp,
    candidate: candidate,
    sdpMid: sdpMid,
    mlineIndex: mlineIndex,
    callerDisplayName: callerDisplayName,
    callerPhoneLast4: callerPhoneLast4,
  );

  Map<String, dynamic> toCanonicalPayload({
    required String callerAccountId,
    required String callerDeviceId,
    required String calleeAccountId,
    required String? targetDeviceId,
    required int createdAt,
    required int expiresAt,
    CallMediaPolicy? effectivePolicy,
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
      if (callerDisplayName != null) 'caller_display_name': callerDisplayName,
      if (callerPhoneLast4 != null) 'caller_phone_last4': callerPhoneLast4,
      // Carried across the hop so the far server enforces the same policy
      // this one just agreed. Without it a federated call would arrive with
      // no policy, resolve to relay-only there, and diverge from what the
      // two clients negotiated.
      'ip_privacy': (effectivePolicy ?? declaredPolicy).wireName,
      'created_at': createdAt,
      'expires_at': expiresAt,
    };
    if (targetDeviceId != null) payload['target_device_id'] = targetDeviceId;
    return payload;
  }
}
