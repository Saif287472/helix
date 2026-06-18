import 'dart:async';
import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';
import 'package:helix_local_domain/core/constants.dart';

class TransferGatewayAdapter implements TransferGateway {
  TransferGatewayAdapter(this._getChannel);

  final SecureChannel? Function() _getChannel;

  SecureChannel get _channel {
    final chan = _getChannel();
    if (chan == null) {
      throw StateError('SecureChannel is not active or available');
    }
    return chan;
  }

  @override
  bool get supportsFileResume {
    final chan = _getChannel();
    return chan != null && chan.supportsCapability(kCapFileResume);
  }

  @override
  Stream<FileResumeFrame> get resumeEvents {
    final chan = _getChannel();
    if (chan == null) return const Stream.empty();
    return chan.fileResumeEvents;
  }

  @override
  Future<void> sendProbe(FileProbeFrame frame) async {
    await _channel.sendFileProbe(frame);
  }

  @override
  Future<void> sendChunk(FileTransferFrame frame) async {
    await _channel.sendFileChunk(frame);
  }

  @override
  Future<void> sendComplete(FileCompleteFrame frame) async {
    await _channel.sendFileComplete(frame);
  }

  @override
  Future<void> sendCancel(FileCancelFrame frame) async {
    await _channel.sendFileCancel(frame);
  }

  @override
  Future<void> sendFileResume(FileResumeFrame frame) async {
    await _channel.sendFileResume(frame);
  }
}
