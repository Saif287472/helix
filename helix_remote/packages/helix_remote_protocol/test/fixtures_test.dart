import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Golden wire fixtures in `helix_remote/contracts/v2/fixtures/`. They pin the
/// exact JSON both ends exchange, so an accidental wire change fails here.
/// After an intended change, regenerate with `HELIX_UPDATE_FIXTURES=1 dart test`
/// and review the diff.
final _fixtures = <String, (Object, JsonMap Function(JsonReader))>{
  'content_text': (
    ContentMessage(
      id: messageM,
      sentAt: t0,
      conversation: const DirectConversation(to: accountB),
      body: const TextBody(text: 'Hello Bob'),
      profileKey: bytes(32, 3),
    ),
    (j) => ContentMessage.fromJson(j).toJson(),
  ),
  'content_group_media_view_once': (
    ContentMessage(
      id: messageM,
      sentAt: t0,
      conversation: const GroupConversation(group: groupG),
      body: MediaBody(
        items: [
          MediaItem(
            kind: MediaItemKind.image,
            media: MediaPointer(
              id: '0192a4f0-0000-7000-8000-0000000000ee',
              key: bytes(32, 4),
              digest: bytes(32, 5),
              size: 52311,
              mime: 'image/jpeg',
              blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
            ),
            width: 1280,
            height: 720,
          ),
        ],
      ),
      viewOnce: true,
      expireSeconds: 604800,
    ),
    (j) => ContentMessage.fromJson(j).toJson(),
  ),
  'content_reaction': (
    ContentMessage(
      id: '0192a4f0-0000-7000-8000-0000000000ef',
      sentAt: t0,
      conversation: const DirectConversation(to: accountA),
      body: const ReactionBody(
        target: MessageRef(id: messageM, author: accountA),
        emoji: '👍',
      ),
    ),
    (j) => ContentMessage.fromJson(j).toJson(),
  ),
  'envelope_message': (
    Envelope(
      id: messageM,
      kind: EnvelopeKind.message,
      sentAt: t0,
      seq: 1042,
      from: const EnvelopeSender(account: accountA, device: deviceA1),
      payload: bytes(48, 6),
      urgent: true,
    ),
    (j) => Envelope.fromJson(j).toJson(),
  ),
  'envelope_roster_change': (
    Envelope(
      id: messageM,
      kind: EnvelopeKind.rosterChange,
      sentAt: t0,
      seq: 1043,
      groupId: groupG,
      data: const RosterChangeEvent(
        groupId: groupG,
        change: RosterChangeKind.added,
        epoch: 2,
        actor: accountA,
        members: [accountB],
      ).toJson(),
    ),
    (j) => Envelope.fromJson(j).toJson(),
  ),
  'sealed_prekey_message': (
    PrekeyMessage(
      senderIdentityKey: bytes(32, 7),
      ephemeralKey: bytes(32, 8),
      signedPrekeyId: 3,
      oneTimePrekeyId: 77,
      header: RatchetHeader(
        ratchetKey: bytes(32, 9),
        previousCount: 0,
        count: 0,
      ),
      ciphertext: bytes(176, 10),
    ),
    (j) => PrekeyMessage.fromJson(j).toJson(),
  ),
  'send_message_request': (
    SendMessageRequest(
      id: messageM,
      recipients: [
        Recipient(
          account: accountB,
          devices: [DevicePayload(device: deviceB1, payload: bytes(24, 11))],
        ),
      ],
    ),
    (j) => SendMessageRequest.fromJson(j).toJson(),
  ),
  'error_device_list_stale': (
    const ApiError(
      ErrorCode.deviceListStale,
      message: 'The recipient has new devices.',
      details: {
        'accounts': [
          {
            'account': accountB,
            'missing': [deviceB1],
            'extra': <String>[],
          },
        ],
      },
    ),
    (j) => ApiError.fromJson(j).toJson(),
  ),
  'realtime_hello': (
    HelloFrame(
      serverTime: t0,
      heartbeatSeconds: 25,
      window: 100,
      lastSeq: 1041,
    ),
    (j) => ServerFrame.decode(jsonEncode(j.json)).toJson(),
  ),
};

JsonMap _encode(Object value) => switch (value) {
  final ContentMessage v => v.toJson(),
  final Envelope v => v.toJson(),
  final SealedPayload v => v.toJson(),
  final SendMessageRequest v => v.toJson(),
  final ApiError v => v.toJson(),
  final ServerFrame v => v.toJson(),
  _ => throw ArgumentError('no encoder for ${value.runtimeType}'),
};

void main() {
  final dir = Directory('../../contracts/v2/fixtures');
  final update = Platform.environment['HELIX_UPDATE_FIXTURES'] == '1';
  const encoder = JsonEncoder.withIndent('  ');

  for (final entry in _fixtures.entries) {
    test('fixture ${entry.key}', () {
      final file = File('${dir.path}/${entry.key}.json');
      final (value, redecode) = entry.value;
      final encoded = encoder.convert(_encode(value));
      if (update) {
        file
          ..createSync(recursive: true)
          ..writeAsStringSync('$encoded\n');
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run with HELIX_UPDATE_FIXTURES=1',
      );
      final stored = file.readAsStringSync().trim();
      expect(stored, encoded, reason: 'wire format of ${entry.key} changed');
      // Decoding the stored fixture and encoding again is lossless.
      expect(encoder.convert(redecode(JsonReader.decode(stored))), stored);
    });
  }
}
