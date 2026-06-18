import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';

void main() {
  final outDir = Directory(
    'test/fixtures/protocol/v$kProtocolMajor.$kProtocolMinor',
  )..createSync(recursive: true);

  final fixtures = <Map<String, Object?>>[];
  for (final entry in _frames().entries) {
    fixtures.add({
      'name': entry.key,
      'type': entry.value.type,
      'payloadBase64': base64.encode(entry.value.encode()),
    });
  }

  final json = const JsonEncoder.withIndent('  ').convert({
    'protocolMajor': kProtocolMajor,
    'protocolMinor': kProtocolMinor,
    'wireFormat': 'legacy-cbor-payload',
    'generatedBy': 'tool/generate_protocol_fixtures.dart',
    'fixtures': fixtures,
  });

  File('${outDir.path}/frames.json').writeAsStringSync('$json\n');
  stdout.writeln('Wrote ${fixtures.length} fixtures to ${outDir.path}');
}

Map<String, ProtocolFrame> _frames() => {
  'request': RequestFrame(
    requestId: 'req-001',
    displayName: 'Alice',
    deviceSuffix: 'a1b2',
    sessionId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    staticKeyFingerprint: '0123456789abcdef0123456789abcdef',
    protocolMajor: kProtocolMajor,
    protocolMinor: kProtocolMinor,
    port: 4242,
    expiresAt: 1710000000000,
  ),
  'accept': AcceptFrame(requestId: 'req-001'),
  'reject': RejectFrame(requestId: 'req-001', reason: 'denied'),
  'cancel': CancelFrame(requestId: 'req-001'),
  'identity': IdentityFrame(
    staticPublicKeyDer: Uint8List.fromList([1, 2, 3, 4]),
    signature: Uint8List.fromList([5, 6, 7, 8]),
    sessionId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ),
  'identity_ack': IdentityAckFrame(
    ok: true,
    sessionId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ),
  'capability': CapabilityFrame(
    major: kProtocolMajor,
    minor: kProtocolMinor,
    features: const ['baseline'],
    capabilities: kCapAll,
  ),
  'chat_message': ChatMessageFrame(
    messageId: 'msg-001',
    text: 'hello',
    timestamp: 1710000000001,
    replyToMessageId: 'msg-000',
  ),
  'chat_ack': ChatAckFrame(messageId: 'msg-001', ok: true),
  'keepalive': KeepaliveFrame(counter: 7),
  'close': CloseFrame(reason: 'normal'),
  'profile_update': ProfileUpdateFrame(newDisplayName: 'Alice 2'),
  'busy': BusyFrame(),
  'version_mismatch': VersionMismatchFrame(
    ourMajor: kProtocolMajor,
    ourMinor: kProtocolMinor,
  ),
  'typing_indicator': TypingIndicatorFrame(isTyping: true),
  'read_receipt': ReadReceiptFrame(messageIds: const ['msg-001', 'msg-002']),
  'reaction': ReactionFrame(messageId: 'msg-001', emoji: '+1', remove: false),
  'file_transfer': FileTransferFrame(
    fileId: 'file-001',
    fileName: 'note.txt',
    mimeType: 'text/plain',
    totalSize: 4,
    chunkIndex: 0,
    chunkCount: 1,
    chunkData: Uint8List.fromList([9, 8, 7, 6]),
  ),
  'edit_message': EditMessageFrame(
    messageId: 'msg-001',
    newText: 'edited',
    editedAt: 1710000000002,
  ),
  'delete_message': DeleteMessageFrame(messageId: 'msg-001'),
  'wipe': WipeFrame(),
  'file_probe': FileProbeFrame(
    fileId: 'file-001',
    fileName: 'note.txt',
    mimeType: 'text/plain',
    totalSize: 4,
    sha256: '00' * 32,
  ),
  'file_resume': FileResumeFrame(fileId: 'file-001', resumeOffset: 0),
  'file_complete': FileCompleteFrame(fileId: 'file-001', sha256: '11' * 32),
  'file_cancel': FileCancelFrame(fileId: 'file-001', reason: 'user-cancel'),
  'ephemeral_media': EphemeralMediaFrame(
    mediaId: 'media-001',
    mimeType: 'image/jpeg',
    totalSize: 3,
    chunkIndex: 0,
    chunkCount: 1,
    chunkData: Uint8List.fromList([1, 1, 2]),
  ),
  'group_control': GroupControlFrame(
    groupId: 'public-lobby',
    eventId: 'evt-001',
    command: 'host-announce',
    senderFingerprint: '0123456789abcdef0123456789abcdef',
    hostFingerprint: '0123456789abcdef0123456789abcdef',
    hostEndpoint: '192.168.1.10:4242',
    epoch: 1,
    membershipVersion: 2,
    expiresAt: 1710003600000,
  ),
  'group_message': GroupMessageFrame(
    groupId: 'public-lobby',
    messageId: 'gmsg-001',
    senderFingerprint: '0123456789abcdef0123456789abcdef',
    epoch: 1,
    membershipVersion: 2,
    sentAt: 1710000000003,
    encryptedPayload: Uint8List.fromList([3, 1, 4, 1, 5]),
  ),
};
