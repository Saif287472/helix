import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// One-way message
// ---------------------------------------------------------------------------

@immutable
class OneWayMessage {
  final String messageId;
  final String peerDisplayName;
  final String peerDeviceSuffix;
  final String peerSessionId;
  final String peerStaticKeyFingerprint;
  final String peerHost;
  final int peerPort;
  final String text;
  final DateTime timestamp;
  final String? subject;
  final DateTime? expiresAt;

  const OneWayMessage({
    required this.messageId,
    required this.peerDisplayName,
    required this.peerDeviceSuffix,
    required this.peerSessionId,
    required this.peerStaticKeyFingerprint,
    required this.peerHost,
    required this.peerPort,
    required this.text,
    required this.timestamp,
    this.subject,
    this.expiresAt,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}
