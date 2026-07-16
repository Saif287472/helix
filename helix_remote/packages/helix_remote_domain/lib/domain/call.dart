class RemoteCallHistoryEntry {
  const RemoteCallHistoryEntry({
    required this.callId,
    required this.conversationId,
    required this.peerAccountId,
    required this.direction, // Incoming, Outgoing, Missed
    required this.startTime,
    required this.durationSeconds,
    this.peerDeviceId,
  });

  final String callId;
  final String conversationId;
  final String peerAccountId;
  final String? peerDeviceId;
  final String direction;
  final DateTime startTime;
  final int durationSeconds;

  Map<String, dynamic> toJson() => {
    'call_id': callId,
    'conversation_id': conversationId,
    'peer_account_id': peerAccountId,
    if (peerDeviceId != null) 'peer_device_id': peerDeviceId,
    'direction': direction,
    'start_time': startTime.toIso8601String(),
    'duration_seconds': durationSeconds,
  };

  factory RemoteCallHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RemoteCallHistoryEntry(
      callId: json['call_id'] as String,
      conversationId: json['conversation_id'] as String,
      peerAccountId:
          json['peer_account_id'] as String? ??
          json['peer_id'] as String? ??
          '',
      peerDeviceId: json['peer_device_id'] as String?,
      direction: json['direction'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      durationSeconds: json['duration_seconds'] as int,
    );
  }
}
