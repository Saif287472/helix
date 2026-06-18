import 'package:helix_protocol/application/contracts/gateways.dart';
import 'package:helix_protocol/protocol/protocol_messages.dart';

class MessageCodecAdapter implements MessageCodec {
  @override
  ChatMessageFrame encodeMessage({
    required String messageId,
    required String threadId,
    required String text,
    required int timestamp,
    String? replyToMessageId,
  }) {
    return ChatMessageFrame(
      messageId: messageId,
      text: text,
      timestamp: timestamp,
      replyToMessageId: replyToMessageId,
    );
  }
}
