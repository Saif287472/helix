import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';

class EphemeralMediaGatewayAdapter implements EphemeralMediaGateway {
  EphemeralMediaGatewayAdapter(this._getChannel);

  final SecureChannel? Function() _getChannel;

  @override
  Future<void> sendEphemeralMedia(EphemeralMediaFrame frame) async {
    final chan = _getChannel();
    if (chan != null) {
      await chan.sendEphemeralMedia(frame);
    }
  }
}
