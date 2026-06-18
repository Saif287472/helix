part of '../protocol_messages.dart';

// ---------------------------------------------------------------------------
// 0x1C GroupControlFrame
// ---------------------------------------------------------------------------

class GroupControlFrame extends ProtocolFrame {
  @override
  final int type = kTypeGroupControl;

  final String groupId;
  final String eventId;
  final String command;
  final String senderFingerprint;
  final String? targetFingerprint;
  final String? hostFingerprint;
  final String? hostEndpoint;
  final int epoch;
  final int membershipVersion;
  final int expiresAt;

  GroupControlFrame({
    required this.groupId,
    required this.eventId,
    required this.command,
    required this.senderFingerprint,
    this.targetFingerprint,
    this.hostFingerprint,
    this.hostEndpoint,
    required this.epoch,
    required this.membershipVersion,
    this.expiresAt = 0,
  });

  factory GroupControlFrame._fromMap(Map<Object?, Object?> map) =>
      GroupControlFrame(
        groupId: _requireString(map, 1, 'groupId'),
        eventId: _requireString(map, 2, 'eventId'),
        command: _requireString(map, 3, 'command'),
        senderFingerprint: _requireString(map, 4, 'senderFingerprint'),
        targetFingerprint: map[5] as String?,
        hostFingerprint: map[6] as String?,
        hostEndpoint: map[7] as String?,
        epoch: _requireInt(map, 8, 'epoch'),
        membershipVersion: _requireInt(map, 9, 'membershipVersion'),
        expiresAt: map[10] == null ? 0 : _requireInt(map, 10, 'expiresAt'),
      );

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeGroupControl,
    1: groupId,
    2: eventId,
    3: command,
    4: senderFingerprint,
    if (targetFingerprint != null) 5: targetFingerprint,
    if (hostFingerprint != null) 6: hostFingerprint,
    if (hostEndpoint != null) 7: hostEndpoint,
    8: epoch,
    9: membershipVersion,
    if (expiresAt > 0) 10: expiresAt,
  });
}

// ---------------------------------------------------------------------------
// 0x1D GroupMessageFrame
// ---------------------------------------------------------------------------

class GroupMessageFrame extends ProtocolFrame {
  @override
  final int type = kTypeGroupMessage;

  final String groupId;
  final String messageId;
  final String senderFingerprint;
  final int epoch;
  final int membershipVersion;
  final int sentAt;

  /// Sender-encrypted payload. The host forwards this without reading it.
  final Uint8List encryptedPayload;

  GroupMessageFrame({
    required this.groupId,
    required this.messageId,
    required this.senderFingerprint,
    required this.epoch,
    required this.membershipVersion,
    required this.sentAt,
    required this.encryptedPayload,
  });

  factory GroupMessageFrame._fromMap(Map<Object?, Object?> map) =>
      GroupMessageFrame(
        groupId: _requireString(map, 1, 'groupId'),
        messageId: _requireString(map, 2, 'messageId'),
        senderFingerprint: _requireString(map, 3, 'senderFingerprint'),
        epoch: _requireInt(map, 4, 'epoch'),
        membershipVersion: _requireInt(map, 5, 'membershipVersion'),
        sentAt: _requireInt(map, 6, 'sentAt'),
        encryptedPayload: _requireBytes(map, 7, 'encryptedPayload'),
      );

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeGroupMessage,
    1: groupId,
    2: messageId,
    3: senderFingerprint,
    4: epoch,
    5: membershipVersion,
    6: sentAt,
    7: encryptedPayload,
  });
}
