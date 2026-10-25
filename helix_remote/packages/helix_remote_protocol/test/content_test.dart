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

  test(
    'an unknown conversation kind is kept whole and re-encodes unchanged',
    () {
      final conv = {'kind': 'channel', 'channel': 'c-1', 'thread': 7};
      final message = ContentMessage.fromJson(
        JsonReader({
          'v': 2,
          'id': messageM,
          'ts': 0,
          'conv': conv,
          'type': 'text',
          'body': {'text': 'hello'},
        }),
      );
      expect(message.conversation, isA<UnknownConversation>());
      expect((message.conversation as UnknownConversation).kind, 'channel');
      expect(message.toJson()['conv'], conv);
    },
  );

  group('every field a peer writes is bounded on decode', () {
    JsonReader body(Map<String, Object?> json) =>
        JsonReader(json, path: 'body');
    void refused(String what, String type, Map<String, Object?> json) {
      test(what, () {
        expect(
          () => ContentBody.decode(type, body(json)),
          throwsA(isA<ProtocolFormatException>()),
        );
      });
    }

    final options = [
      for (var i = 0; i < ContentLimits.maxPollOptions; i++)
        {'id': 'o$i', 'text': 'o$i'},
    ];
    final pointer = _pointer(thumb: false).toJson();

    refused('text over the message limit', 'text', {
      'text': 'x' * (ContentLimits.maxTextLength + 1),
    });
    refused('more mentions than the largest group has members', 'text', {
      'text': 'hi',
      'mentions': [
        for (var i = 0; i <= ContentLimits.maxMentions; i++)
          {'account': accountB, 'start': i, 'length': 3},
      ],
    });
    refused('a link preview url over the url limit', 'text', {
      'text': 'hi',
      'link_preview': {'url': 'u' * (ContentLimits.maxUrlLength + 1)},
    });
    refused('a link preview title or description over its limit', 'text', {
      'text': 'hi',
      'link_preview': {
        'url': 'https://x',
        'description': 'd' * (ContentLimits.maxCaptionLength + 1),
      },
    });
    refused('more media items than an album may hold', 'media', {
      'items': [
        for (var i = 0; i <= ContentLimits.maxMediaItems; i++)
          {'kind': 'image', 'media': pointer},
      ],
    });
    refused('an empty album', 'media', {'items': <Object?>[]});
    refused('a per-item caption over the caption limit', 'media', {
      'items': [
        {
          'kind': 'image',
          'media': pointer,
          'caption': 'c' * (ContentLimits.maxCaptionLength + 1),
        },
      ],
    });
    refused('a media file name of any size', 'media', {
      'items': [
        {
          'kind': 'image',
          'media': {
            ...pointer,
            'name': 'n' * (ContentLimits.maxNameLength + 1),
          },
        },
      ],
    });
    refused('a sticker emoji over the emoji limit', 'sticker', {
      'pack_id': 'p',
      'sticker_id': 's',
      'media': pointer,
      'emoji': 'x' * (ContentLimits.maxEmojiLength + 1),
    });
    refused('a location label or address of any size', 'location', {
      'lat_e7': 1,
      'lng_e7': 1,
      'accuracy_m': 1,
      'label': 'l' * (ContentLimits.maxNameLength + 1),
    });
    refused('a contact card with a name of any size', 'contact', {
      'name': 'n' * (ContentLimits.maxNameLength + 1),
    });
    refused('a contact card with more numbers than a card holds', 'contact', {
      'name': 'Ann',
      'numbers': [
        for (var i = 0; i <= ContentLimits.maxContactNumbers; i++) '+1',
      ],
    });
    refused('a contact card with a number of any size', 'contact', {
      'name': 'Ann',
      'numbers': ['1' * (ContentLimits.maxNumberLength + 1)],
    });
    refused('a poll question of any size', 'poll', {
      'question': 'q' * (ContentLimits.maxCaptionLength + 1),
      'options': options,
    });
    refused('a poll option over the name limit', 'poll', {
      'question': 'q',
      'options': [
        {'id': 'a', 'text': 'a'},
        {'id': 'b', 'text': 'b' * (ContentLimits.maxNameLength + 1)},
      ],
    });
    refused('a poll with fewer options than it may offer', 'poll', {
      'question': 'q',
      'options': [
        {'id': 'a', 'text': 'a'},
      ],
    });
    refused('a poll with more options than it may offer', 'poll', {
      'question': 'q',
      'options': [
        ...options,
        {'id': 'extra', 'text': 'extra'},
      ],
    });
    refused('a vote for more options than the poll has', 'poll_vote', {
      'target': _target.toJson(),
      'option_ids': [
        for (var i = 0; i <= ContentLimits.maxPollOptions; i++) 'o',
      ],
    });
    refused('an event title, zone or place of any size', 'event', {
      'title': 't' * (ContentLimits.maxNameLength + 1),
      'starts_at': 1,
      'time_zone': 'Asia/Dhaka',
    });
    refused('a system notice with more fields than it may carry', 'system', {
      'kind': 'member_added',
      for (var i = 0; i <= ContentLimits.maxSystemFields; i++) 'f$i': i,
    });
    refused('a reaction emoji over the emoji limit', 'reaction', {
      'target': _target.toJson(),
      'emoji': 'x' * (ContentLimits.maxEmojiLength + 1),
    });
    refused('an edit over the text limit', 'edit', {
      'target': _target.toJson(),
      'text': 'x' * (ContentLimits.maxTextLength + 1),
    });
    refused('an edit with neither text nor caption', 'edit', {
      'target': _target.toJson(),
    });
    refused('a receipt of more ids than it may name', 'receipt', {
      'kind': 'read',
      'ids': [
        for (var i = 0; i <= ContentLimits.maxIdsPerReceipt; i++) messageM,
      ],
    });
    refused('a receipt naming an id of any size', 'receipt', {
      'kind': 'read',
      'ids': ['x' * (ContentLimits.maxIdLength + 1)],
    });
    refused('an empty receipt', 'receipt', {
      'kind': 'read',
      'ids': <Object?>[],
    });
    refused('a resend request of more ids than it may name', 'resend_request', {
      'ids': [
        for (var i = 0; i <= ContentLimits.maxIdsPerReceipt; i++) messageM,
      ],
    });
    refused(
      'a contact sync of more entries than it may carry',
      'contact_sync',
      {
        'entries': [
          for (var i = 0; i <= ContentLimits.maxContactEntries; i++)
            {'account': accountB},
        ],
      },
    );
    refused('a contact sync nickname of any size', 'contact_sync', {
      'entries': [
        {
          'account': accountB,
          'nickname': 'n' * (ContentLimits.maxNameLength + 1),
        },
      ],
    });
    refused(
      'a transfer offering more devices than an account has',
      'device_transfer_offer',
      {
        'transfer_id': 't',
        'devices': [for (var i = 0; i <= ContentLimits.maxDevices; i++) 'd'],
      },
    );
    refused('a media pointer whose key is not 32 bytes', 'media', {
      'items': [
        {
          'kind': 'image',
          'media': {...pointer, 'key': encodeBytes(List.filled(16, 1))},
        },
      ],
    });
    refused(
      'a sender-key distribution with a chain key of the wrong length',
      'sender_key_distribution',
      {
        'group_id': groupG,
        'dist_id': 'd',
        'iteration': 1,
        'chain_key': encodeBytes(List.filled(31, 1)),
        'signing_key': encodeBytes(List.filled(32, 2)),
      },
    );
    refused('a group key of the wrong length', 'group_key', {
      'group_id': groupG,
      'epoch': 1,
      'key': encodeBytes(List.filled(33, 1)),
    });
    refused('a profile key of the wrong length', 'profile_key_update', {
      'key': encodeBytes(List.filled(16, 1)),
      'version': 1,
    });

    test('a message profile key of the wrong length is refused', () {
      final message = _message(const TextBody(text: 'hi')).toJson();
      JsonReader withKey(int length) => JsonReader({
        ...message,
        'profile_key': encodeBytes(List.filled(length, 1)),
      });
      expect(
        () => ContentMessage.fromJson(withKey(31)),
        throwsA(isA<ProtocolFormatException>()),
      );
      expect(ContentMessage.fromJson(withKey(32)).profileKey, hasLength(32));
    });

    test('a body at exactly its limit decodes', () {
      expect(
        ContentBody.decode(
          'contact',
          body({
            'name': 'n' * ContentLimits.maxNameLength,
            'numbers': ['1' * ContentLimits.maxNumberLength],
          }),
        ),
        isA<ContactBody>(),
      );
      expect(
        ContentBody.decode(
          'poll_vote',
          body({
            'target': _target.toJson(),
            'option_ids': [
              for (var i = 0; i < ContentLimits.maxPollOptions; i++) 'o$i',
            ],
          }),
        ),
        isA<PollVoteBody>(),
      );
      expect(
        ContentBody.decode(
          'text',
          body({
            'text': 'x' * ContentLimits.maxTextLength,
            'mentions': [
              for (var i = 0; i < ContentLimits.maxMentions; i++)
                {'account': accountB, 'start': 0, 'length': 3},
            ],
          }),
        ),
        isA<TextBody>(),
      );
    });
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

  group('crafted content never throws anything but a FormatException', () {
    Map<String, Object?> message({
      Object? ts = 1700000000000,
      Object? exp,
      Map<String, Object?>? body,
      String type = 'text',
    }) => {
      'v': 1,
      'id': messageM,
      'ts': ts,
      'conv': {'kind': 'direct', 'to': accountB},
      'type': type,
      'body': body ?? {'text': 'hi'},
      'exp': ?exp,
    };

    void rejected(String why, Map<String, Object?> json) => test(why, () {
      expect(
        () => ContentMessage.decode(utf8.encode(jsonEncode(json))),
        throwsA(isA<FormatException>()),
      );
    });

    rejected('a huge timestamp', message(ts: 9223372036854775807));
    rejected('a negative timestamp', message(ts: -5));
    rejected('a huge disappearing timer', message(exp: 9007199254740991));
    rejected(
      'a huge media size',
      message(
        type: 'media',
        body: {
          'items': [
            {
              'kind': 'image',
              'media': {
                'id': 'm',
                'key': encodeBytes(bytes(32, 1)),
                'digest': encodeBytes(bytes(32, 2)),
                'size': 9007199254740991,
                'mime': 'image/png',
              },
            },
          ],
        },
      ),
    );
    rejected(
      'a huge live-location expiry',
      message(
        type: 'live_location',
        body: {
          'session_id': 's',
          'state': 'start',
          'lat_e7': 1,
          'lng_e7': 1,
          'accuracy_m': 1,
          'expires_at': 9223372036854775807,
        },
      ),
    );
    rejected(
      'an absurd mention range',
      message(
        body: {
          'text': 'hi',
          'mentions': [
            {'account': accountB, 'start': 9007199254740991, 'length': 4},
          ],
        },
      ),
    );
    rejected(
      'a coordinate outside the globe',
      message(
        type: 'location',
        body: {'lat_e7': 9000000001, 'lng_e7': 0, 'accuracy_m': 5},
      ),
    );
    rejected(
      'an iteration beyond 32 bits',
      message(
        type: 'sender_key_distribution',
        body: {
          'group_id': groupG,
          'dist_id': messageM,
          'iteration': 4294967296,
          'chain_key': encodeBytes(bytes(32, 1)),
          'signing_key': encodeBytes(bytes(32, 2)),
        },
      ),
    );
  });
}
