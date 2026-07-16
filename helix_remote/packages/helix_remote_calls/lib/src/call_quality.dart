/// Call quality metrics sampled from the WebRTC stats API.
///
/// Contains transport-level indicators only - no content, no media bytes.
class CallQualityMetrics {
  const CallQualityMetrics({
    required this.callId,
    required this.packetLossPercent,
    required this.jitterMs,
    required this.roundTripMs,
    required this.audioBitrateKbps,
    this.videoBitrateKbps,
    this.selectedCandidateType,
    this.isRelay = false,
    this.framesSent,
    this.framesReceived,
    this.framesDropped,
    this.isWeak = false,
    this.isReconnecting = false,
  });

  final String callId;
  final double packetLossPercent;
  final double jitterMs;
  final double roundTripMs;
  final double audioBitrateKbps;
  final double? videoBitrateKbps;
  final String? selectedCandidateType;
  final bool isRelay;
  final int? framesSent;
  final int? framesReceived;
  final int? framesDropped;
  final bool isWeak;
  final bool isReconnecting;

  Map<String, dynamic> toMap() => {
    'call_id': callId,
    'packet_loss_percent': packetLossPercent,
    'jitter_ms': jitterMs,
    'round_trip_ms': roundTripMs,
    'audio_bitrate_kbps': audioBitrateKbps,
    if (videoBitrateKbps != null) 'video_bitrate_kbps': videoBitrateKbps,
    if (selectedCandidateType != null)
      'selected_candidate_type': selectedCandidateType,
    'is_relay': isRelay,
    if (framesSent != null) 'frames_sent': framesSent,
    if (framesReceived != null) 'frames_received': framesReceived,
    if (framesDropped != null) 'frames_dropped': framesDropped,
    'is_weak': isWeak,
    'is_reconnecting': isReconnecting,
  };
}
