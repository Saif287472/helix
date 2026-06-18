// lib/infrastructure/call/call_signaling_gateway_adapter.dart

import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';

/// Routes outbound call signal frames through the active [SecureChannel] for
/// a given peer.  The channel lookup function is injected so this adapter
/// has no compile-time dependency on [MessagingService].
class CallSignalingGatewayAdapter implements CallSignalingGateway {
  CallSignalingGatewayAdapter(this._channelLookup);

  final SecureChannel? Function(String peerId) _channelLookup;

  @override
  Future<void> sendCallSignal(String peerId, CallSignalFrame frame) async {
    final channel = _channelLookup(peerId);
    await channel?.sendCallSignal(frame);
  }
}
