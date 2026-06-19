class RemoteSyncCursor {
  const RemoteSyncCursor({
    required this.conversationId,
    required this.lastServerSequence,
  });

  final String conversationId;
  final int lastServerSequence;

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'last_server_sequence': lastServerSequence,
      };

  factory RemoteSyncCursor.fromJson(Map<String, dynamic> json) {
    return RemoteSyncCursor(
      conversationId: json['conversation_id'] as String,
      lastServerSequence: json['last_server_sequence'] as int,
    );
  }
}
