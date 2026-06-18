import 'dart:typed_data';

class ProtocolEnvelope {
  const ProtocolEnvelope({
    required this.protocolMajor,
    required this.protocolMinor,
    required this.frameType,
    required this.frameId,
    this.correlationId,
    this.senderDeviceId,
    this.sessionId,
    this.conversationId,
    required this.timestamp,
    required this.sequenceNumber,
    this.flags = 0,
    required this.payload,
  });

  final int protocolMajor;
  final int protocolMinor;
  final int frameType;
  final String frameId;
  final String? correlationId;
  final String? senderDeviceId;
  final String? sessionId;
  final String? conversationId;
  final int timestamp;
  final int sequenceNumber;
  final int flags;
  final Uint8List payload;
}
