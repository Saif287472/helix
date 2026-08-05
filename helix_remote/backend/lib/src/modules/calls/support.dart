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
