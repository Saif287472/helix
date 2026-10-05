import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// The inbound pipeline against a fake server: dedupe, quarantine, content
/// handling, deferred actions and the checks on who may do what.
void main() {
  late Peers peers;
  late Peer alice;
  late Peer bob;

  setUp(() async {
    peers = Peers();
    alice = await peers.register('alice', phone: '+8801711000001');
    bob = await peers.register('bob', phone: '+8801711000002');
  });
  tearDown(() => peers.dispose());

  /// Alice sends [text] and Bob fetches it.
  Future<MessageRow> say(String text) async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    final row = await alice.engine.chats.sendText(chat.id, text);
    await alice.engine.drainOutbox();
    await bob.sync();
    return row;
  }

  MessageRow? rowOf(List<MessageRow> rows, String? text) =>
      rows.where((m) => m.body == text).firstOrNull;

  group('delivery and dedupe', () {
    test(
      'a message arrives as one row with its summary and a notice',
      () async {
        final chat = await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(chat.id, 'hello Bob');
        await alice.engine.drainOutbox();
        final summary = await bob.sync();
        expect(summary.processed, 1);
        expect(summary.complete, isTrue);
        final notice = summary.notices.single;
        expect(notice.preview, 'hello Bob');
        expect(notice.sender, alice.account);
        expect(notice.muted, isFalse);
        final conversation = (await bob.db.conversationsDao.byId(
          bob.chatWith(alice),
        ))!;
        expect(conversation.unreadCount, 1);
        expect(conversation.lastMessagePreview, 'hello Bob');
        expect(
          (await bob.db.messagesDao.search('hello')).single.sender,
          alice.account,
          reason: 'full-text search finds it',
        );
        expect(
          peers.server.device(bob.device).mailbox,
          isEmpty,
          reason: 'acked',
        );
      },
    );

    test('a replayed envelope is applied once and acked again', () async {
      final sent = await say('once');
      final original = peers.server.sends
          .firstWhere((s) => s.from.id == alice.device)
          .request
          .recipients
          .firstWhere((r) => r.account == bob.account)
          .devices
          .single;
      // The server delivers the same envelope id again (a replay after a
      // reconnect whose ack was lost).
      peers.server.deliver(
        bob.device,
        id: sent.messageId,
        from: EnvelopeSender(account: alice.account, device: alice.device),
        payload: original.payload,
      );
      final again = await bob.sync();
      expect(again.processed, 0, reason: 'a duplicate is not processed');
      expect(await bob.texts(alice), ['once']);
      expect(peers.server.device(bob.device).mailbox, isEmpty);
    });

    test('the cursor and processed ids are written with the message', () async {
      await say('one');
      await say('two');
      final cursor = (await bob.db.inboxDao.cursor())!;
      expect(cursor.lastProcessedSeq, 2);
      expect(cursor.lastAckedSeq, 2);
    });

    test(
      'a muted chat still stores the message, flagged for no alert',
      () async {
        await say('first');
        await bob.engine.chats.setMutedUntil(
          bob.chatWith(alice),
          peers.clock.now.add(const Duration(hours: 8)),
        );
        final chat = await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(chat.id, 'quiet');
        await alice.engine.drainOutbox();
        final summary = await bob.sync();
        expect(summary.notices.single.muted, isTrue);
        expect(await bob.texts(alice), ['first', 'quiet']);
      },
    );
  });

  group('quarantine never blocks the stream', () {
    test('a tampered ciphertext becomes a "couldn\'t decrypt" row and the '
        'next message still arrives', () async {
      await say('works');
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'tampered in transit');
      await alice.engine.drainOutbox();
      // Flip a byte inside the ratchet message's JSON ciphertext field.
      final box = peers.server.device(bob.device).mailbox;
      final victim = box.single;
      final text = String.fromCharCodes(victim.payload!);
      final at = text.indexOf('"ct":"') + 8;
      final flipped =
          text.substring(0, at) +
          (text[at] == 'A' ? 'B' : 'A') +
          text.substring(at + 1);
      box[0] = Envelope(
        id: victim.id,
        kind: victim.kind,
        sentAt: victim.sentAt,
        seq: victim.seq,
        from: victim.from,
        payload: Uint8List.fromList(flipped.codeUnits),
        urgent: victim.urgent,
      );
      await alice.engine.chats.sendText(chat.id, 'after the damage');
      await alice.engine.drainOutbox();

      final events = <EngineEvent>[];
      bob.engine.events.listen(events.add);
      final summary = await bob.sync();
      expect(summary.complete, isTrue);
      var rows = await bob.messages(alice);
      expect(rows.map((m) => m.kind), [
        'text',
        MessageKinds.undecryptable,
        'text',
      ]);
      expect(rows.last.body, 'after the damage');
      expect(rows[1].payload, contains('auth_failed'));
      expect(
        rows[1].payload,
        contains('"waiting":true'),
        reason:
            'a message that fails under a session we hold may be one '
            'from a session we lost: a re-send is requested',
      );
      expect(
        events.whereType<EnvelopeQuarantined>().single.code,
        'auth_failed',
      );

      // Alice re-sends it (the content is hers, so it is authentic) and the
      // placeholder turns into the real message.
      await alice.sync();
      await bob.sync();
      rows = await bob.messages(alice);
      expect(rows.where((m) => m.kind == MessageKinds.undecryptable), isEmpty);
      expect(await bob.texts(alice), [
        'works',
        'tampered in transit',
        'after the damage',
      ]);
    });

    test('garbage payloads and envelopes without a sender are recorded and '
        'skipped', () async {
      peers.server
        ..deliver(
          bob.device,
          from: EnvelopeSender(account: alice.account, device: alice.device),
          payload: Uint8List.fromList('not json at all'.codeUnits),
          urgent: true,
        )
        ..deliver(bob.device) // a message envelope with no sender or payload
        ..deliver(bob.device, kind: EnvelopeKind.unknown)
        ..deliver(bob.device, kind: EnvelopeKind.groupMessage)
        ..deliver(bob.device, kind: EnvelopeKind.callSignal)
        ..deliver(bob.device, kind: EnvelopeKind.rosterChange);
      await say('still fine');
      expect((await bob.sync()).processed, 0);
      expect(await bob.texts(alice), ['still fine']);
      final rows = await bob.messages(alice);
      expect(
        rows.where((m) => m.kind == MessageKinds.undecryptable).single.payload,
        contains('bad_payload'),
      );
      expect(
        (await bob.db.inboxDao.cursor())!.lastProcessedSeq,
        greaterThan(6),
      );
      expect(peers.server.device(bob.device).mailbox, isEmpty);
    });

    test('an envelope the pipeline cannot store is quarantined after a few '
        'tries instead of blocking the stream', () async {
      // Bob crafts a message with the id and time of one of Alice's: both
      // rows would get the same sort key, which the database refuses.
      final chat = await alice.engine.chats.openDirect(bob.account);
      final mine = await alice.engine.chats.sendText(chat.id, 'original');
      await alice.engine.drainOutbox();
      await bob.sync();
      await bob.engine.debugSend(
        ContentMessage(
          id: mine.messageId,
          sentAt: mine.sentAt,
          conversation: DirectConversation(to: alice.account),
          body: const TextBody(text: 'poison'),
        ),
        audience: [alice.account],
      );
      await bob.engine.drainOutbox();
      await bob.engine.chats.sendText(
        directConversationId(alice.account),
        'after the poison',
      );
      await bob.engine.drainOutbox();

      final summary = await alice.sync();
      expect(summary.complete, isTrue);
      expect(await alice.texts(bob), ['original', 'after the poison']);
      final rows = await alice.messages(bob);
      expect(
        rows.where((m) => m.kind == MessageKinds.undecryptable).single.payload,
        contains('internal_error'),
      );
      expect(
        peers.server.device(alice.device).mailbox,
        isEmpty,
        reason: 'everything was acked, the poison included',
      );
    });

    test('crafted numbers in decrypted content are quarantined as bad content '
        'at once, never retried, and the stream goes on', () async {
      await say('works');
      Uint8List craft(Map<String, Object?> patch) {
        final json = ContentMessage(
          id: Uuid.v7(),
          sentAt: peers.clock.now,
          conversation: DirectConversation(to: bob.account),
          body: const TextBody(text: 'crafted'),
        ).toJson();
        return Uint8List.fromList(utf8.encode(jsonEncode({...json, ...patch})));
      }

      final crafted = {
        'huge ts': craft({'ts': 9223372036854775807}),
        'float ts beyond the range': craft({'ts': 1e300}),
        'negative ts': craft({'ts': -1}),
        'huge exp': craft({'exp': 9007199254740991}),
        'huge version': craft({'v': 9223372036854775807}),
      };
      for (final bytes in crafted.values) {
        await alice.engine.debugSendRaw(bytes, audience: [bob.account]);
      }
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'after the crafted ones');
      await alice.engine.drainOutbox();

      final watch = Stopwatch()..start();
      final summary = await bob.sync();
      expect(summary.complete, isTrue);
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'no retry loop for a deterministic failure',
      );
      final placeholders = (await bob.messages(
        alice,
      )).where((m) => m.kind == MessageKinds.undecryptable).toList();
      expect(placeholders, hasLength(crafted.length));
      for (final row in placeholders) {
        expect(row.payload, contains('bad_content'));
        expect(row.payload, contains('"waiting":false'));
      }
      expect(await bob.texts(alice), ['works', 'after the crafted ones']);
      expect(peers.server.device(bob.device).mailbox, isEmpty);
    });

    test('a message from an unknown device without a session asks for a '
        'fresh one and shows a waiting row', () async {
      await say('m1');
      // Bob forgets his sessions (a restore); Alice keeps sending.
      await bob.db.cryptoDao.deleteSessions(alice.account);
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'm2');
      await alice.engine.chats.sendText(chat.id, 'm3');
      await alice.engine.drainOutbox();
      await bob.engine.syncOnce();
      final placeholders = (await bob.messages(
        alice,
      )).where((m) => m.kind == MessageKinds.undecryptable).toList();
      expect(placeholders, hasLength(2));
      expect(placeholders.first.payload, contains('"waiting":true'));
      expect(
        placeholders.first.payload,
        anyOf(contains('no_session'), contains('unknown_prekey')),
      );

      // The reset was sent in the same run; Alice answers with the
      // messages, and the placeholders turn into the real ones.
      await alice.sync();
      await bob.sync();
      final rows = await bob.messages(alice);
      expect(rows.where((m) => m.kind == MessageKinds.undecryptable), isEmpty);
      expect(await bob.texts(alice), ['m1', 'm2', 'm3']);
      // One fresh session served both, not one per message.
      final sessions = await bob.db.cryptoDao.sessionsWith(
        alice.account,
        alice.device,
      );
      expect(sessions.map((s) => s.slot), [0]);
    });
  });

  group('content', () {
    Future<void> sendRaw(
      Peer from,
      Peer to,
      ContentBody body, {
      DateTime? at,
      String? id,
      String? conversationTo,
      int version = ContentMessage.currentVersion,
      bool sync = true,
    }) async {
      await from.engine.debugSend(
        ContentMessage(
          version: version,
          id: id ?? Uuid.v7(now: at),
          sentAt: at ?? peers.clock.now,
          conversation: DirectConversation(to: conversationTo ?? to.account),
          body: body,
        ),
        audience: [to.account],
      );
      await from.engine.drainOutbox();
      if (sync) await to.sync();
    }

    test(
      'unknown types and newer versions are placeholders, not crashes',
      () async {
        await sendRaw(
          alice,
          bob,
          const UnknownBody(type: 'hologram', raw: {'depth': 3}),
        );
        await sendRaw(
          alice,
          bob,
          const TextBody(text: 'from the future'),
          version: 99,
        );
        final rows = await bob.messages(alice);
        expect(rows.map((m) => m.kind), ['hologram', MessageKinds.unsupported]);
        expect(MessageKinds.isRenderable(rows[0].kind), isFalse);
        expect(MessageKinds.isRenderable(rows[1].kind), isFalse);
        expect(
          rows[1].body,
          isNull,
          reason: 'future content is never searched',
        );
        expect((await bob.db.messagesDao.search('future')), isEmpty);
      },
    );

    test('every visible type is stored with its payload', () async {
      await sendRaw(
        alice,
        bob,
        const LocationBody(
          latE7: 233000000,
          lngE7: 901000000,
          accuracyM: 12,
          label: 'Dhaka',
        ),
      );
      await sendRaw(
        alice,
        bob,
        const ContactBody(name: 'Carol', numbers: ['+8801711000003']),
      );
      await sendRaw(
        alice,
        bob,
        const PollBody(
          question: 'Lunch?',
          options: [
            PollOption(id: 'a', text: 'Rice'),
            PollOption(id: 'b', text: 'Noodles'),
          ],
        ),
      );
      await sendRaw(
        alice,
        bob,
        const SystemBody(kind: 'timer_changed', fields: {'seconds': 60}),
      );
      await sendRaw(
        alice,
        bob,
        MediaBody(
          items: [
            MediaItem(
              kind: MediaItemKind.image,
              media: MediaPointer(
                id: Uuid.v7(),
                key: Uint8List(32),
                digest: Uint8List(32),
                size: 10,
                mime: 'image/jpeg',
              ),
              width: 4,
              height: 3,
            ),
          ],
          caption: 'a photo',
        ),
      );
      final rows = await bob.messages(alice);
      expect(rows.map((m) => m.kind), [
        'location',
        'contact',
        'poll',
        'system',
        'media',
      ]);
      expect(rows[0].payload, contains('Dhaka'));
      expect(rows[4].body, 'a photo');
      final media = await bob.db.messagesDao.attachmentsFor([
        rows[4].localRowid,
      ]);
      expect(media.single.transfer, AttachmentTransfer.remote);
      expect(media.single.width, 4);
      expect((await bob.db.messagesDao.search('photo')).single.kind, 'media');
    });

    test(
      'a peer cannot write engine-owned rows: system notices other '
      'than the timer are dropped, reserved kinds become unsupported',
      () async {
        await sendRaw(
          alice,
          bob,
          const SystemBody(kind: 'safety_number_changed'),
        );
        await sendRaw(alice, bob, const SystemBody(kind: 'you_were_removed'));
        await sendRaw(
          alice,
          bob,
          const UnknownBody(type: 'undecryptable', raw: {'code': 'forged'}),
        );
        await sendRaw(
          alice,
          bob,
          const UnknownBody(type: 'unsupported', raw: {}),
        );
        final rows = await bob.messages(alice);
        expect(rows.map((m) => m.kind), [
          MessageKinds.unsupported,
          MessageKinds.unsupported,
        ]);
        expect(
          rows.where((m) => m.kind == MessageKinds.undecryptable),
          isEmpty,
          reason: 'a forged placeholder would be replaced by a re-send',
        );
      },
    );

    test('poll votes and RSVPs update the poll message', () async {
      final chat = await alice.engine.chats.openDirect(bob.account);
      final poll = await alice.engine.chats.sendBody(
        chat.id,
        const PollBody(
          question: 'Lunch?',
          options: [
            PollOption(id: 'a', text: 'Rice'),
            PollOption(id: 'b', text: 'Noodles'),
          ],
        ),
      );
      final event = await alice.engine.chats.sendBody(
        chat.id,
        EventBody(
          title: 'Dinner',
          startsAt: peers.clock.now.add(const Duration(days: 1)),
          timeZone: 'Asia/Dhaka',
        ),
      );
      await alice.engine.drainOutbox();
      await bob.sync();
      final bobRows = await bob.messages(alice);
      final bobPoll = bobRows.firstWhere((m) => m.kind == 'poll');
      final bobEvent = bobRows.firstWhere((m) => m.kind == 'event');

      await bob.engine.chats.vote(bobPoll.localRowid, ['b']);
      await bob.engine.chats.rsvp(
        bobEvent.localRowid,
        RsvpState.going,
        plusOne: true,
      );
      // A vote for an option that does not exist is ignored on receipt.
      await bob.engine.debugSend(
        ContentMessage(
          id: Uuid.v7(),
          sentAt: peers.clock.now,
          conversation: DirectConversation(to: alice.account),
          body: PollVoteBody(
            target: MessageRef(id: poll.messageId, author: alice.account),
            optionIds: const ['zzz'],
          ),
        ),
        audience: [alice.account],
      );
      await bob.engine.drainOutbox();
      await alice.sync();
      final votes = (await alice.db.messagesDao.byRowid(poll.localRowid))!;
      expect(votes.payload, contains('"votes":{"${bob.account}":["b"]}'));
      final rsvps = (await alice.db.messagesDao.byRowid(event.localRowid))!;
      expect(rsvps.payload, contains('"rsvps"'));
      expect(rsvps.payload, contains('"going"'));
      // Bob's own copy shows his vote too.
      expect(
        (await bob.db.messagesDao.byRowid(bobPoll.localRowid))!.payload,
        contains('"votes":{"${bob.account}":["b"]}'),
      );

      await bob.engine.chats.vote(bobPoll.localRowid, []);
      await bob.engine.drainOutbox();
      await alice.sync();
      expect(
        (await alice.db.messagesDao.byRowid(poll.localRowid))!.payload,
        contains('"votes":{}'),
      );
    });

    test('content for a group chat or addressed to someone else is dropped '
        'without effect', () async {
      await sendRaw(alice, bob, const TextBody(text: 'valid one'), sync: false);
      await alice.engine.debugSend(
        ContentMessage(
          id: Uuid.v7(),
          sentAt: peers.clock.now,
          conversation: const GroupConversation(
            group: '0192a4f0-0000-7000-8000-0000000000ee',
          ),
          body: const TextBody(text: 'in a group'),
        ),
        audience: [bob.account],
      );
      await alice.engine.debugSend(
        ContentMessage(
          id: Uuid.v7(),
          sentAt: peers.clock.now,
          conversation: const DirectConversation(
            to: '0192a4f0-0000-7000-8000-00000000000c',
          ),
          body: const TextBody(text: 'for Carol, not Bob'),
        ),
        audience: [bob.account],
      );
      await alice.engine.drainOutbox();
      await bob.sync();
      expect(await bob.texts(alice), ['valid one']);
    });

    test('a locally blocked sender is ignored, and the session still works '
        'afterwards', () async {
      await say('before');
      await bob.db.peopleDao.setBlocked(
        alice.account,
        true,
        now: peers.clock.now,
      );
      await say('blocked');
      expect(await bob.texts(alice), ['before']);
      await bob.db.peopleDao.setBlocked(
        alice.account,
        false,
        now: peers.clock.now,
      );
      await say('after');
      expect(await bob.texts(alice), ['before', 'after']);
    });

    test('a message cannot claim to be from the future', () async {
      await sendRaw(
        alice,
        bob,
        const TextBody(text: 'from 2099'),
        at: DateTime.utc(2099),
      );
      final row = (await bob.messages(alice)).single;
      expect(
        row.sentAt.isBefore(peers.clock.now.add(const Duration(minutes: 2))),
        isTrue,
      );
    });
  });

  group('actions on messages', () {
    test(
      'an edit that arrives before its message waits, then applies',
      () async {
        final chat = await alice.engine.chats.openDirect(bob.account);
        final sent = await alice.engine.chats.sendText(chat.id, 'original');
        await alice.engine.chats.edit(sent.localRowid, 'edited');
        await alice.engine.drainOutbox();
        peers.server.reverseMailbox(bob.device);
        await bob.sync();
        final row = (await bob.messages(alice)).single;
        expect(row.body, 'edited');
        expect(row.editedAt, isNotNull);
        expect(
          await bob.db.inboxDao.takeDeferred(
            sent.messageId,
            author: alice.account,
          ),
          isEmpty,
        );
      },
    );

    test(
      'actions for a message that never arrives expire after 7 days',
      () async {
        await say('seed');
        await alice.engine.debugSend(
          ContentMessage(
            id: Uuid.v7(),
            sentAt: peers.clock.now,
            conversation: DirectConversation(to: bob.account),
            body: ReactionBody(
              target: MessageRef(id: Uuid.v7(), author: alice.account),
              emoji: 'A',
            ),
          ),
          audience: [bob.account],
        );
        await alice.engine.drainOutbox();
        await bob.sync();
        peers.clock.advance(const Duration(days: 8));
        await bob.engine.runMaintenance();
        // Nothing waits any more.
        expect(await bob.db.inboxDao.purgeExpiredDeferred(peers.clock.now), 0);
      },
    );

    test('only the author may edit or delete, within the windows', () async {
      final target = await say('mine');
      final ref = MessageRef(id: target.messageId, author: alice.account);
      Future<void> forge(
        ContentBody body, {
        Duration after = Duration.zero,
      }) async {
        await bob.engine.debugSend(
          ContentMessage(
            id: Uuid.v7(),
            sentAt: target.sentAt.add(after),
            conversation: DirectConversation(to: alice.account),
            body: body,
          ),
          audience: [alice.account],
        );
        await bob.engine.drainOutbox();
        await alice.sync();
      }

      // Bob forges an edit and a delete of Alice's message.
      await forge(EditBody(target: ref, text: 'hacked'));
      await forge(DeleteBody(target: ref));
      var mine = (await alice.messages(bob)).single;
      expect(mine.body, 'mine');
      expect(mine.deletedAt, isNull);

      // Alice's own edits: [sent] is when she wrote it, [received] the clock
      // at Bob's end when it arrives.
      Future<void> asAlice(
        ContentBody body, {
        required Duration sent,
        Duration? received,
      }) async {
        peers.clock.now = target.sentAt.add(received ?? sent);
        await alice.engine.debugSend(
          ContentMessage(
            id: Uuid.v7(),
            sentAt: target.sentAt.add(sent),
            conversation: DirectConversation(to: bob.account),
            body: body,
          ),
          audience: [bob.account],
        );
        await alice.engine.drainOutbox();
        await bob.sync();
      }

      // More than 15 minutes after the message: refused.
      await asAlice(
        EditBody(target: ref, text: 'too late'),
        sent: const Duration(minutes: 16),
      );
      expect((await bob.messages(alice)).single.body, 'mine');
      await asAlice(
        EditBody(target: ref, text: 'in time'),
        sent: const Duration(minutes: 14),
      );
      expect((await bob.messages(alice)).single.body, 'in time');
      // An edit older than the one already applied does not replace it.
      await asAlice(
        EditBody(target: ref, text: 'older'),
        sent: const Duration(minutes: 5),
        received: const Duration(minutes: 20),
      );
      expect((await bob.messages(alice)).single.body, 'in time');
      // Delete for everyone only within two days of the message.
      await asAlice(DeleteBody(target: ref), sent: const Duration(days: 3));
      expect((await bob.messages(alice)).single.deletedAt, isNull);
      await asAlice(
        DeleteBody(target: ref),
        sent: const Duration(days: 1),
        received: const Duration(days: 3),
      );
      final deleted = (await bob.messages(alice)).single;
      expect(deleted.deletedAt, isNotNull);
      expect(deleted.body, isNull);
      expect(deleted.payload, isNull);
      mine = (await alice.messages(bob)).single;
      expect(mine.body, 'mine');
    });

    test('reactions: the newest wins when they arrive out of order, and a '
        'removal needs a newer time too', () async {
      final target = await say('react');
      final ref = MessageRef(id: target.messageId, author: alice.account);
      Future<void> react(
        String emoji,
        int seconds, {
        bool remove = false,
      }) async {
        await bob.engine.debugSend(
          ContentMessage(
            id: Uuid.v7(),
            sentAt: target.sentAt.add(Duration(seconds: seconds)),
            conversation: DirectConversation(to: alice.account),
            body: ReactionBody(target: ref, emoji: emoji, remove: remove),
          ),
          audience: [alice.account],
        );
        await bob.engine.drainOutbox();
        await alice.sync();
      }

      Future<List<String>> seen() async => [
        for (final r in await alice.db.messagesDao.reactionsFor([
          (await alice.messages(bob)).single.localRowid,
        ]))
          r.emoji,
      ];

      await react('B', 20);
      await react('A', 10); // older: ignored
      expect(await seen(), ['B']);
      await react('C', 15, remove: true); // older removal: ignored
      expect(await seen(), ['B']);
      await react('B', 30, remove: true);
      expect(await seen(), isEmpty);
    });

    test('receipts move the status forward only', () async {
      final sent = await say('status');
      Future<MessageStatus> statusOf() async =>
          (await alice.db.messagesDao.byRowid(sent.localRowid))!.status;
      await alice.sync(); // Bob's delivered receipt
      expect(await statusOf(), MessageStatus.delivered);
      await bob.engine.chats.markRead(bob.chatWith(alice));
      await bob.engine.drainOutbox();
      await alice.sync();
      expect(await statusOf(), MessageStatus.read);
      // A late "delivered" cannot move it back.
      await bob.engine.debugSend(
        ContentMessage(
          id: Uuid.v7(),
          sentAt: peers.clock.now,
          conversation: DirectConversation(to: alice.account),
          body: ReceiptBody(kind: ReceiptKind.delivered, ids: [sent.messageId]),
        ),
        audience: [alice.account],
      );
      await bob.engine.drainOutbox();
      await alice.sync();
      expect(await statusOf(), MessageStatus.read);
      final receipts = await alice.db.messagesDao.receiptsFor(sent.localRowid);
      expect(receipts.single.accountId, bob.account);
      expect(receipts.single.deliveredAt, isNotNull);
      expect(receipts.single.readAt, isNotNull);
    });

    test('read receipts to the author can be turned off', () async {
      await bob.engine.settings.set(EngineSettings.sendReadReceipts, false);
      final sent = await say('private');
      await bob.engine.chats.markRead(bob.chatWith(alice));
      await bob.engine.drainOutbox();
      await alice.sync();
      final row = (await alice.db.messagesDao.byRowid(sent.localRowid))!;
      expect(row.status, MessageStatus.delivered, reason: 'never read');
      expect(
        (await bob.db.conversationsDao.byId(bob.chatWith(alice)))!.unreadCount,
        0,
      );
    });
  });

  group('disappearing messages', () {
    test(
      'the timer starts at first display and the row goes when it runs out',
      () async {
        final chat = await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.setDisappearing(chat.id, 60);
        await alice.engine.drainOutbox();
        await bob.sync();
        expect(
          (await bob.db.conversationsDao.byId(
            bob.chatWith(alice),
          ))!.disappearingSeconds,
          60,
        );
        await alice.engine.chats.sendText(chat.id, 'poof');
        await alice.engine.drainOutbox();
        await bob.sync();
        final row = rowOf(await bob.messages(alice), 'poof')!;
        expect(row.expireSeconds, 60);
        expect(row.expiresAt, isNull);

        peers.clock.advance(const Duration(minutes: 5));
        await bob.engine.runMaintenance();
        expect(
          rowOf(await bob.messages(alice), 'poof'),
          isNotNull,
          reason: 'never displayed, so the timer never started',
        );
        await bob.engine.chats.markDisplayed(row.localRowid);
        peers.clock.advance(const Duration(seconds: 59));
        await bob.engine.runMaintenance();
        expect(rowOf(await bob.messages(alice), 'poof'), isNotNull);
        peers.clock.advance(const Duration(seconds: 2));
        await bob.engine.runMaintenance();
        expect(rowOf(await bob.messages(alice), 'poof'), isNull);
        // The sender's copy ran from sending.
        expect(rowOf(await alice.messages(bob), 'poof'), isNotNull);
        await alice.engine.runMaintenance();
        expect(rowOf(await alice.messages(bob), 'poof'), isNull);
      },
    );
  });
}
