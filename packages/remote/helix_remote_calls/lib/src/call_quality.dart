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
  });

  final String callId;
  final double packetLossPercent;
  final double jitterMs;
  final double roundTripMs;
  final double audioBitrateKbps;
  final double? videoBitrateKbps;

  Map<String, dynamic> toMap() => {
    'call_id': callId,
    'packet_loss_percent': packetLossPercent,
    'jitter_ms': jitterMs,
    'round_trip_ms': roundTripMs,
    'audio_bitrate_kbps': audioBitrateKbps,
    if (videoBitrateKbps != null) 'video_bitrate_kbps': videoBitrateKbps,
  };
}
