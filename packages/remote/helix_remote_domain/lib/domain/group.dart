class RemoteGroup {
  const RemoteGroup({
    required this.conversationId,
    required this.groupName,
    this.avatarUri,
    required this.groupPublicKey,
  });

  final String conversationId;
  final String groupName;
  final String? avatarUri;
  final String groupPublicKey;

  Map<String, dynamic> toJson() => {
    'conversation_id': conversationId,
    'group_name': groupName,
    'avatar_uri': avatarUri,
    'group_public_key': groupPublicKey,
  };

  factory RemoteGroup.fromJson(Map<String, dynamic> json) {
    return RemoteGroup(
      conversationId: json['conversation_id'] as String,
      groupName: json['group_name'] as String,
      avatarUri: json['avatar_uri'] as String?,
      groupPublicKey: json['group_public_key'] as String,
    );
  }
}
