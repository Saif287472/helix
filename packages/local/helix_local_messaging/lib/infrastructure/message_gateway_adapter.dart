import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';

class MessageGatewayAdapter implements MessageGateway {
  MessageGatewayAdapter(this._getChannel);

  final SecureChannel? Function(String threadId) _getChannel;

  @override
  Future<void> sendMessage(String threadId, ChatMessageFrame frame) async {
    final channel = _getChannel(threadId);
    if (channel == null || channel.state != ChannelState.active) {
      throw StateError('No active channel for threadId=$threadId');
    }
    await channel.sendMessage(frame);
  }

  @override
  Future<void> sendAck(String threadId, ChatAckFrame frame) async {
    // secure_channel handles sending acks automatically in its read loop.
  }
}
