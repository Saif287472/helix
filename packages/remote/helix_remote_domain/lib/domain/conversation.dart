class RemoteConversation {
  const RemoteConversation({
    required this.conversationId,
    required this.type, // OneToOne, Group
    required this.title,
    required this.createdAt,
    required this.lastActivitySequence,
  });

  final String conversationId;
  final String type;
  final String title;
  final DateTime createdAt;
  final int lastActivitySequence;

  Map<String, dynamic> toJson() => {
    'conversation_id': conversationId,
    'type': type,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'last_activity_sequence': lastActivitySequence,
  };

  factory RemoteConversation.fromJson(Map<String, dynamic> json) {
    return RemoteConversation(
      conversationId: json['conversation_id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastActivitySequence: json['last_activity_sequence'] as int,
    );
  }
}
