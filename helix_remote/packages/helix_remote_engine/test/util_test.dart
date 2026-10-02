import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/crypto/db_stores.dart';
import 'package:helix_remote_engine/src/messaging/content_codec.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_engine/src/util/ids.dart';
import 'package:helix_remote_engine/src/util/keyed_lock.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

void main() {
  group('Backoff', () {
    const backoff = Backoff(
      initial: Duration(seconds: 2),
      max: Duration(seconds: 20),
      jitter: 0.25,
    );

    test('doubles from the initial delay and stops at the cap', () {
      Duration at(int failures) => backoff.delay(failures, 0.5);
      expect(at(1), const Duration(seconds: 2));
      expect(at(2), const Duration(seconds: 4));
      expect(at(3), const Duration(seconds: 8));
      expect(at(4), const Duration(seconds: 16));
      expect(at(5), const Duration(seconds: 20));
      expect(at(500), const Duration(seconds: 20));
      expect(at(0), const Duration(seconds: 2));
    });

    test('jitter spreads by the configured fraction', () {
      expect(backoff.delay(1, 0), const Duration(milliseconds: 1500));
      expect(backoff.delay(1, 1), const Duration(milliseconds: 2500));
    });
  });

  group('KeyedLock', () {
    test('runs actions of one key in order and keys in parallel', () async {
      final lock = KeyedLock<String>();
      final log = <String>[];
      final gate = Completer<void>();
      final a1 = lock.run('a', () async {
        log.add('a1 start');
        await gate.future;
        log.add('a1 end');
      });
      final a2 = lock.run('a', () async => log.add('a2'));
      await lock.run('b', () async => log.add('b'));
      expect(log, ['a1 start', 'b'], reason: 'b did not wait for a');
      gate.complete();
      await Future.wait([a1, a2]);
      expect(log, ['a1 start', 'b', 'a1 end', 'a2']);
      expect(lock.isBusy('a'), isFalse);
    });

    test('an exception releases the key', () async {
      final lock = KeyedLock<String>();
      await expectLater(
        lock.run('a', () async => throw StateError('boom')),
        throwsStateError,
      );
      expect(await lock.run('a', () async => 7), 7);
    });

    test('overlapping multi-key callers cannot deadlock', () async {
      final lock = KeyedLock<String>();
      final results = await Future.wait([
        for (var i = 0; i < 20; i++)
          lock.runAll(i.isEven ? ['x', 'y'] : ['y', 'x'], () async => i),
      ]);
      expect(results, List.generate(20, (i) => i));
    });

    test('device addresses work as keys', () async {
      final lock = KeyedLock<DeviceAddress>();
      final a = DeviceAddress(
        '0192a4f0-0000-7000-8000-00000000000a',
        '0192a4f0-0000-7000-8000-0000000000a1',
      );
      expect(await lock.run(a, () async => 1), 1);
    });
  });

  group('ids and randomness', () {
    test('ids are UUIDv7 from the injected clock and RNG', () {
      final clock = TestClock(DateTime.utc(2026, 10, 2, 9));
      final ids = IdFactory(clock.call, SeededRandom('ids'));
      final a = ids.next();
      final b = ids.next();
      expect(Uuid.isV7(a), isTrue);
      expect(a, isNot(b));
      expect(Uuid.timeOfV7(a).year, 2026);
      final again = IdFactory(clock.call, SeededRandom('ids'));
      clock.now = DateTime.utc(2026, 10, 2, 9);
      expect(
        again.next().substring(15),
        a.substring(15),
        reason: 'same seed, same random bits',
      );
    });

    test('the Random adapter stays in range', () {
      final random = RandomAdapter(SeededRandom('range'));
      for (var i = 0; i < 500; i++) {
        expect(random.nextInt(7), inInclusiveRange(0, 6));
        expect(
          random.nextDouble(),
          allOf(greaterThanOrEqualTo(0), lessThan(1)),
        );
      }
      expect(() => random.nextInt(0), throwsRangeError);
      expect({for (var i = 0; i < 60; i++) random.nextBool()}, {true, false});
    });
  });

  group('masking', () {
    test('phone numbers keep the country prefix and the last two digits', () {
      expect(maskPhone('+8801711000001'), '+880********01');
      expect(maskPhone('+8801711000001'), isNot(contains('1711000')));
      expect(maskPhone('12345'), '*****');
      expect(maskPhone(''), '');
    });

    test('ids are shortened', () {
      expect(shortId('0192a4f0-0000-7000-8000-00000000000a'), '0192a4f0…');
      expect(shortId('abc'), 'abc');
    });
  });

  group('session storage layout', () {
    test(
      'slots round-trip active, previous sessions and retired keys',
      () async {
        final peers = Peers();
        addTearDown(peers.dispose);
        final alice = await peers.register('alice');
        final bob = await peers.register('bob');
        final chat = await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(chat.id, 'x');
        await alice.engine.drainOutbox();

        final store = DbSessionStore(alice.db);
        final remote = DeviceAddress(bob.account, bob.device);
        final loaded = (await store.load(remote))!;
        expect(loaded.active, isNotNull);

        // Six sessions and a retired base key use every slot.
        var many = loaded;
        for (var i = 0; i < 4; i++) {
          many = many.withNewActive(loaded.active!);
        }
        expect(many.previous, hasLength(4));
        final slots = DbSessionStore.encode(many);
        expect(slots, hasLength(5));
        expect(DbSessionStore.decode(remote, slots).encode(), many.encode());
        await store.save(many, now: peers.clock.now);
        expect((await store.load(remote))!.encode(), many.encode());
        expect(
          (await alice.db.cryptoDao.sessionsWith(
            bob.account,
            bob.device,
          )).map((s) => s.slot),
          [0, 1, 2, 3, 4],
        );

        // A cleared record keeps only the retired base keys, in slot 0.
        final cleared = many.cleared();
        await store.save(cleared, now: peers.clock.now);
        final back = (await store.load(remote))!;
        expect(back.active, isNull);
        expect(back.retiredBaseKeys, isNotEmpty);
        expect(
          (await alice.db.cryptoDao.sessionsWith(bob.account, bob.device)),
          hasLength(1),
        );
        // An empty record with nothing to remember deletes the rows.
        await store.save(DeviceSessions(remote: remote), now: peers.clock.now);
        expect(await store.load(remote), isNull);
      },
    );
  });

  group('content codec', () {
    test('text, media and others split into columns and join back', () {
      MessageRow row(String kind, String? body, String? payload) => MessageRow(
        localRowid: 1,
        messageId: 'id',
        conversationId: 'direct:x',
        sender: 's',
        outgoing: true,
        sortKey: 'k',
        sentAt: DateTime.utc(2026),
        receivedAt: DateTime.utc(2026),
        kind: kind,
        body: body,
        payload: payload,
        forwarded: false,
        mentionsMe: false,
        status: MessageStatus.sent,
      );
      const bodies = <ContentBody>[
        TextBody(
          text: 'hello @bob',
          mentions: [Mention(account: 'b', start: 6, length: 4)],
        ),
        TextBody(text: 'plain'),
        LocationBody(latE7: 1, lngE7: 2, accuracyM: 3, label: 'here'),
        PollBody(
          question: 'q',
          options: [
            PollOption(id: 'a', text: 'A'),
            PollOption(id: 'b', text: 'B'),
          ],
          multiple: true,
        ),
        SystemBody(kind: 'timer_changed', fields: {'seconds': 60}),
        ContactBody(name: 'C', numbers: ['+1']),
      ];
      for (final body in bodies) {
        final split = ContentCodec.split(body);
        final joined = ContentCodec.join(
          row(body.type, split.text, split.payload),
        );
        expect(
          jsonEncode(joined.toJson()),
          jsonEncode(body.toJson()),
          reason: body.type,
        );
      }
      expect(ContentCodec.split(const TextBody(text: 'plain')).payload, isNull);
      final media = MediaBody(
        items: [
          MediaItem(
            kind: MediaItemKind.image,
            media: MediaPointer(
              id: 'm',
              key: Uint8List(32),
              digest: Uint8List(32),
              size: 1,
              mime: 'image/png',
            ),
          ),
        ],
        caption: 'cap',
      );
      final split = ContentCodec.split(media);
      expect(split.text, 'cap');
      expect(
        jsonEncode(
          ContentCodec.join(row('media', split.text, split.payload)).toJson(),
        ),
        jsonEncode(media.toJson()),
      );
      // A damaged payload degrades to an unknown body instead of throwing.
      expect(
        ContentCodec.join(row('text', 'x', '{not json')),
        isA<UnknownBody>(),
      );
    });

    test('a re-sent message keeps its id, time, reply and timer', () {
      final row = MessageRow(
        localRowid: 5,
        messageId: 'm-1',
        conversationId: 'direct:peer',
        sender: 'me',
        outgoing: true,
        sortKey: 'k',
        sentAt: DateTime.utc(2026, 10, 2),
        receivedAt: DateTime.utc(2026, 10, 2),
        kind: 'text',
        body: 'again',
        replyToId: 'r-1',
        replyToAuthor: 'them',
        forwarded: false,
        mentionsMe: false,
        status: MessageStatus.sent,
        expireSeconds: 30,
        viewOnceState: ViewOnceState.unopened,
      );
      final content = ContentCodec.rebuild(row, to: 'peer', profileKey: null);
      expect(content.id, 'm-1');
      expect(content.sentAt, DateTime.utc(2026, 10, 2));
      expect(content.reply!.id, 'r-1');
      expect(content.expireSeconds, 30);
      expect(content.viewOnce, isTrue);
      expect((content.conversation as DirectConversation).to, 'peer');
      expect((content.body as TextBody).text, 'again');
    });
  });

  group('outbox payloads', () {
    test('send_content and session_reset round-trip', () {
      final content = ContentMessage(
        id: Uuid.v7(),
        sentAt: DateTime.utc(2026),
        conversation: const DirectConversation(to: 'peer'),
        body: const TextBody(text: 'hi'),
      );
      final decoded = SendContentPayload.decode(
        SendContentPayload(
          content: content,
          audience: ['b', 'a'],
          urgent: false,
        ).encode(),
      );
      expect(decoded.audience, ['b', 'a']);
      expect(decoded.urgent, isFalse);
      expect(decoded.content.id, content.id);
      final reset = SessionResetPayload.decode(
        const SessionResetPayload(
          account: 'a',
          device: 'd',
          messageId: 'm',
        ).encode(),
      );
      expect([reset.account, reset.device, reset.messageId], ['a', 'd', 'm']);
      expect(
        () => SendContentPayload.decode('{}'),
        throwsA(isA<ProtocolFormatException>()),
      );
    });

    test('errors are sorted into retry, give up and account conditions', () {
      ApiException api(ErrorCode code, {Duration? retryAfter}) =>
          ApiException(status: code.status, code: code, retryAfter: retryAfter);
      expect(classifyOpError(const NetworkException()), isA<RetryLater>());
      expect(classifyOpError(api(ErrorCode.unavailable)), isA<RetryLater>());
      expect(classifyOpError(api(ErrorCode.rateLimited)), isA<RetryLater>());
      expect(classifyOpError(api(ErrorCode.quotaExceeded)), isA<RetryLater>());
      expect(
        classifyOpError(api(ErrorCode.deviceListStale)),
        isA<RetryLater>(),
      );
      expect(
        classifyOpError(api(ErrorCode.unauthenticated)),
        isA<RetryLater>(),
      );
      expect(classifyOpError(api(ErrorCode.forbidden)), isA<GiveUp>());
      expect(classifyOpError(api(ErrorCode.payloadTooLarge)), isA<GiveUp>());
      expect(classifyOpError(api(ErrorCode.notFound)), isA<GiveUp>());
      expect(
        classifyOpError(api(ErrorCode.deviceRevoked)),
        isA<DeviceRevoked>(),
      );
      expect(
        classifyOpError(const SignedOutException(SignedOutReason.noSession)),
        isA<SessionEnded>(),
      );
      expect(classifyOpError(const UntrustedPeerException('x')), isA<GiveUp>());
      expect(
        classifyOpError(const UntrustedIdentityException('x')),
        isA<GiveUp>(),
      );
      expect(
        classifyOpError(const TransientEngineException('x')),
        isA<RetryLater>(),
      );
      expect(
        classifyOpError(StateError('bug')),
        isA<RetryLater>(),
        reason: 'unknown errors are retried, then age out',
      );
      final waited =
          classifyOpError(
                api(
                  ErrorCode.rateLimited,
                  retryAfter: const Duration(seconds: 9),
                ),
              )
              as RetryLater;
      expect(waited.atLeast, const Duration(seconds: 9));
    });
  });
}
