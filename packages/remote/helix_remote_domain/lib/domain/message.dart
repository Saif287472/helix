class RemoteMessage {
  const RemoteMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderAccountId,
    required this.senderDeviceId,
    required this.ciphertext,
  });

  final String messageId;
  final String conversationId;
  final String senderAccountId;
  final int senderDeviceId;
  final String ciphertext;

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'conversation_id': conversationId,
        'sender_account_id': senderAccountId,
        'sender_device_id': senderDeviceId,
        'ciphertext': ciphertext,
      };

  factory RemoteMessage.fromJson(Map<String, dynamic> json) {
    return RemoteMessage(
      messageId: json['message_id'] as String,
      conversationId: json['conversation_id'] as String,
      senderAccountId: json['sender_account_id'] as String,
      senderDeviceId: json['sender_device_id'] as int,
      ciphertext: json['ciphertext'] as String,
    );
  }
}
