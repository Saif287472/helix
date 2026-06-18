import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';

class GroupSignalingGatewayAdapter implements GroupSignalingGateway {
  GroupSignalingGatewayAdapter(this._getChannel);

  final SecureChannel? Function(String peerFingerprint) _getChannel;

  @override
  Future<void> sendControl(
    String peerFingerprint,
    GroupControlFrame frame,
  ) async {
    final channel = _getChannel(peerFingerprint);
    if (channel == null) {
      throw StateError('No active channel for peer');
    }
    await channel.sendGroupControl(frame);
  }

  @override
  Future<void> sendMessage(
    String peerFingerprint,
    GroupMessageFrame frame,
  ) async {
    final channel = _getChannel(peerFingerprint);
    if (channel == null) {
      throw StateError('No active channel for peer');
    }
    await channel.sendGroupMessage(frame);
  }
}
