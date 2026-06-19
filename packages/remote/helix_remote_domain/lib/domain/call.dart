class RemoteCallHistoryEntry {
  const RemoteCallHistoryEntry({
    required this.callId,
    required this.conversationId,
    required this.direction, // Incoming, Outgoing, Missed
    required this.startTime,
    required this.durationSeconds,
  });

  final String callId;
  final String conversationId;
  final String direction;
  final DateTime startTime;
  final int durationSeconds;

  Map<String, dynamic> toJson() => {
        'call_id': callId,
        'conversation_id': conversationId,
        'direction': direction,
        'start_time': startTime.toIso8601String(),
        'duration_seconds': durationSeconds,
      };

  factory RemoteCallHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RemoteCallHistoryEntry(
      callId: json['call_id'] as String,
      conversationId: json['conversation_id'] as String,
      direction: json['direction'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      durationSeconds: json['duration_seconds'] as int,
    );
  }
}
