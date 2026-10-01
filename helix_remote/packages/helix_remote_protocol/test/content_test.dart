import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

MediaPointer _pointer({bool thumb = true}) => MediaPointer(
  id: 'media-1',
  key: bytes(32, 1),
  digest: bytes(32, 2),
  size: 1234,
  mime: 'image/jpeg',
  name: 'a.jpg',
  blurhash: 'LEHV6nWB2yk8',
  thumbnail: thumb ? _pointer(thumb: false) : null,
);

const _target = MessageRef(id: messageM, author: accountB);

final _bodies = <ContentBody>[
  const TextBody(
    text: 'hi @bob',
    mentions: [Mention(account: accountB, start: 3, length: 4)],
  ),
  MediaBody(
    items: [
      MediaItem(
        kind: MediaItemKind.image,
        media: _pointer(),
        width: 10,
        height: 20,
      ),
      MediaItem(
        kind: MediaItemKind.voiceNote,
        media: _pointer(thumb: false),
        durationMs: 4000,
        waveform: bytes(10),
      ),
    ],
    caption: 'holiday',
  ),
  StickerBody(packId: 'p', stickerId: 's', media: _pointer(), emoji: '😀'),
  const LocationBody(
    latE7: 237777000,
    lngE7: 904000000,
    accuracyM: 5,
    label: 'Office',
  ),
  LiveLocationBody(
    sessionId: 'l1',
    state: LiveLocationState.update,
    latE7: 1,
    lngE7: 2,
    accuracyM: 3,
    expiresAt: t0,
  ),
  const ContactBody(
    name: 'Rahim',
    numbers: ['+8801700000000'],
    account: accountB,
  ),
  PollBody(
    question: 'Lunch?',
    options: const [
      PollOption(id: 'a', text: 'Yes'),
      PollOption(id: 'b', text: 'No'),
    ],
    multiple: true,
    closesAt: t0,
  ),
  EventBody(
    title: 'Party',
    startsAt: t0,
    timeZone: 'Asia/Dhaka',
    plusOneAllowed: true,
  ),
  const SystemBody(kind: 'timer_changed', fields: {'seconds': 86400}),
  const CallLogBody(
    callId: 'c1',
    media: CallMedia.video,
    outcome: CallOutcome.answered,
    durationS: 61,
  ),
  const ReactionBody(target: _target, emoji: '❤️'),
  const EditBody(target: _target, text: 'fixed'),
  const DeleteBody(target: _target),
  const PollVoteBody(target: _target, optionIds: ['a']),
  const RsvpBody(target: _target, state: RsvpState.maybe, plusOne: true),
  const ReceiptBody(kind: ReceiptKind.read, ids: [messageM]),
  const TypingBody(state: TypingState.started),
  SenderKeyDistributionBody(
    groupId: groupG,
    distributionId: 'd1',
    iteration: 0,
    chainKey: bytes(32),
    signingKey: bytes(32, 3),
  ),
  GroupKeyBody(groupId: groupG, epoch: 4, key: bytes(32)),
  ProfileKeyUpdateBody(key: bytes(32), version: 2),
  const DecryptionErrorBody(messageId: messageM, senderDevice: deviceB1),
  const ResendRequestBody(ids: [messageM]),
  const ContactSyncBody(
    entries: [ContactSyncEntry(account: accountB, nickname: 'Bob')],
  ),
];

ContentMessage _message(ContentBody body) => ContentMessage(
  id: messageM,
  sentAt: t0,
  conversation: const DirectConversation(to: accountB),
  body: body,
  reply: _target,
  expireSeconds: 3600,
  profileKey: bytes(32, 9),
  viewOnce: body is MediaBody,
);

void main() {
  test('every body type round-trips inside a content message', () {
    final seen = <String>{};
    for (final body in _bodies) {
      final decoded = expectRoundTrip(
        _message(body),
        (v) => v.toJson(),
        ContentMessage.fromJson,
      );
      expect(decoded.body.runtimeType, body.runtimeType);
      expect(seen.add(body.type), isTrue, reason: 'duplicate ${body.type}');
    }
  });

  test('visibility: chat bubbles vs actions and control', () {
    final visible = {
      for (final b in _bodies)
        if (b.isVisible) b.type,
    };
    expect(visible, {
      'text',
      'media',
      'sticker',
      'location',
      'contact',
      'poll',
      'event',
      'system',
      'call_log',
    });
    expect(
      LiveLocationBody(
        sessionId: 's',
        state: LiveLocationState.start,
        latE7: 0,
        lngE7: 0,
        accuracyM: 0,
        expiresAt: t0,
      ).isVisible,
      isTrue,
    );
  });

  test('unknown types are kept, not shown as JSON or dropped', () {
    final json = {
      'v': 1,
      'id': messageM,
      'ts': 0,
      'conv': {'kind': 'group', 'group': groupG},
      'type': 'hologram',
      'body': {'depth': 3},
    };
    final message = ContentMessage.fromJson(JsonReader(json));
    expect(message.body, isA<UnknownBody>());
    expect(message.body.type, 'hologram');
    expect(message.body.isVisible, isTrue);
    expect(message.toJson()['body'], {'depth': 3});
  });

  test('a newer content version decodes as unknown, even for known types', () {
    final message = ContentMessage.fromJson(
      JsonReader({
        'v': 2,
        'id': messageM,
        'ts': 0,
        'conv': {'kind': 'direct', 'to': accountB},
        'type': 'text',
        'body': {'rich_text': '...'},
      }),
    );
    expect(message.isFromNewerVersion, isTrue);
    expect(message.body, isA<UnknownBody>());
  });

  test('limits are enforced on decode', () {
    JsonReader body(Map<String, Object?> json) =>
        JsonReader(json, path: 'body');
    expect(
      () => TextBody.fromJson(
        body({'text': 'x' * (ContentLimits.maxTextLength + 1)}),
      ),
      throwsA(isA<ProtocolFormatException>()),
    );
    expect(
      () => PollBody.fromJson(
        body({
          'question': 'q',
          'options': [
            {'id': 'a', 'text': 'a'},
          ],
        }),
      ),
      throwsA(isA<ProtocolFormatException>()),
    );
    expect(
      () => MediaBody.fromJson(body({'items': <Object?>[]})),
      throwsA(isA<ProtocolFormatException>()),
    );
    expect(
      () => EditBody.fromJson(body({'target': _target.toJson()})),
      throwsA(isA<ProtocolFormatException>()),
    );
    expect(
      () => MediaPointer.fromJson(
        body({
          'id': 'm',
          'key': encodeBytes(bytes(16)),
          'digest': encodeBytes(bytes(32)),
          'size': 1,
          'mime': 'x/y',
        }),
      ),
      throwsA(isA<ProtocolFormatException>()),
    );
  });

  test('direct chats resolve to the other person on every device', () {
    const conv = DirectConversation(to: accountB);
    // On Bob's devices, a message from Alice is the chat with Alice.
    expect(conv.chatPeer(sender: accountA, selfAccount: accountB), accountA);
    // On Alice's other devices, her own message is the chat with Bob.
    expect(conv.chatPeer(sender: accountA, selfAccount: accountA), accountB);
  });

  group('padding', () {
    test('pads to 160-byte blocks and strips exactly', () {
      for (final length in [0, 1, 158, 159, 160, 161, 1000]) {
        final plain = bytes(
          length,
          5,
        ).map((b) => b == 0x80 ? 0x81 : b).toList();
        final padded = padPlaintext(plain);
        expect(padded.length % padBlock, 0);
        expect(padded.length, greaterThan(plain.length));
        expect(unpadPlaintext(padded), plain);
      }
    });

    test('plaintext ending in 0x80 or zeros survives', () {
      final plain = [1, 0x80, 0, 0];
      expect(unpadPlaintext(padPlaintext(plain)), plain);
    });

    test('bad padding is rejected', () {
      expect(
        () => unpadPlaintext([0, 0, 0]),
        throwsA(isA<ProtocolFormatException>()),
      );
      expect(
        () => unpadPlaintext([1, 2, 3]),
        throwsA(isA<ProtocolFormatException>()),
      );
    });
  });

  test('encode/decode go through UTF-8 JSON', () {
    final message = _message(const TextBody(text: 'নমস্কার 👋'));
    final decoded = ContentMessage.decode(message.encode());
    expect((decoded.body as TextBody).text, 'নমস্কার 👋');
    expect(
      () => ContentMessage.decode([0xff, 0xfe]),
      throwsA(isA<ProtocolFormatException>()),
    );
    expect(utf8.decode(message.encode()), contains('"type":"text"'));
  });
}
