import 'dart:async';

import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// The outbound pipeline: encrypt at send time, backoff, ordering per
/// conversation, stale device lists, idempotent retries, give-up rules.
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

  Future<MessageRow> queue(String text, {Peer? to}) async {
    final chat = await alice.engine.chats.openDirect((to ?? bob).account);
    return alice.engine.chats.sendText(chat.id, text);
  }

  Future<OutboxOpRow> opOf(MessageRow row) async =>
      (await alice.db.outboxDao.forMessage(row.localRowid)).single;

  Future<MessageStatus> statusOf(MessageRow row) async =>
      (await alice.db.messagesDao.byRowid(row.localRowid))!.status;

  group('backoff', () {
    test('a server error reschedules with doubling delays and keeps the '
        'message pending', () async {
      final row = await queue('retry me');
      peers.server.failNext(Routes.sendMessage, times: 2);
      final start = peers.clock.now;

      await alice.engine.drainOutbox();
      var op = await opOf(row);
      expect(op.state, OutboxState.pending);
      expect(op.attempts, 1);
      expect(op.lastError, 'unavailable');
      expect(
        op.nextAttemptAt.difference(start),
        closeTo2(const Duration(seconds: 2)),
      );
      expect(await statusOf(row), MessageStatus.pending);

      // Not due yet: nothing is sent.
      final before = peers.server.callsTo(Routes.sendMessage);
      await alice.engine.drainOutbox();
      expect(peers.server.callsTo(Routes.sendMessage), before);

      peers.clock.advance(const Duration(seconds: 3));
      await alice.engine.drainOutbox();
      op = await opOf(row);
      expect(op.attempts, 2);
      expect(
        op.nextAttemptAt.difference(peers.clock.now),
        closeTo2(const Duration(seconds: 4)),
      );

      peers.clock.advance(const Duration(seconds: 5));
      await alice.engine.drainOutbox();
      expect(await alice.db.outboxDao.forMessage(row.localRowid), isEmpty);
      expect(await statusOf(row), MessageStatus.sent);
      await bob.sync();
      expect(await bob.texts(alice), ['retry me']);
    });

    test(
      'Retry-After is honoured when it is longer than the backoff',
      () async {
        final row = await queue('slow down');
        peers.server.failNext(
          Routes.sendMessage,
          code: ErrorCode.rateLimited,
          retryAfter: const Duration(seconds: 30),
        );
        await alice.engine.drainOutbox();
        final op = await opOf(row);
        expect(op.lastError, 'rate_limited');
        expect(
          op.nextAttemptAt.difference(peers.clock.now),
          greaterThan(const Duration(seconds: 28)),
        );
      },
    );

    test('no network is retried, not failed', () async {
      final row = await queue('offline');
      peers.server.dropNext(Routes.sendMessage, times: 3);
      await alice.engine.drainOutbox();
      expect((await opOf(row)).lastError, 'network');
      expect(await statusOf(row), MessageStatus.pending);
    });

    test('a retry after a lost response is idempotent and the ratchet '
        'survives the extra message key', () async {
      final row = await queue('exactly once');
      peers.server.loseResponseNext(Routes.sendMessage);
      await alice.engine.drainOutbox();
      expect((await opOf(row)).lastError, 'network');
      peers.clock.advance(const Duration(seconds: 3));
      await alice.engine.drainOutbox();
      expect(await alice.db.outboxDao.forMessage(row.localRowid), isEmpty);
      expect(
        peers.server.sends.where((s) => s.request.id == row.messageId),
        hasLength(2),
        reason: 'the same request id both times',
      );
      await queue('and the next');
      await alice.engine.drainOutbox();
      await bob.sync();
      expect(await bob.texts(alice), ['exactly once', 'and the next']);
    });

    test('an op older than the age limit is given up on', () async {
      final row = await queue('too old');
      final failures = <SendFailedEvent>[];
      alice.engine.events.listen((e) {
        if (e is SendFailedEvent) failures.add(e);
      });
      peers.server.failNext(Routes.sendMessage, times: 100);
      await alice.engine.drainOutbox();
      peers.clock.advance(const Duration(days: 4));
      await alice.engine.drainOutbox();
      final op = await opOf(row);
      expect(op.state, OutboxState.failed);
      expect(op.lastError, 'expired');
      expect(await statusOf(row), MessageStatus.failed);
      await Future<void>.delayed(Duration.zero);
      expect(failures.single.errorCode, 'expired');
    });
  });

  group('failures', () {
    test('a refused send fails at once, can be retried by the user', () async {
      final row = await queue('refused');
      peers.server.failNext(Routes.sendMessage, code: ErrorCode.forbidden);
      await alice.engine.drainOutbox();
      final op = await opOf(row);
      expect(op.state, OutboxState.failed);
      expect(op.lastError, 'forbidden');
      expect(await statusOf(row), MessageStatus.failed);

      await alice.engine.chats.retrySend(row.localRowid);
      expect(await statusOf(row), MessageStatus.pending);
      await alice.engine.drainOutbox();
      expect(await statusOf(row), MessageStatus.sent);
    });

    test('keys that do not verify are never encrypted to', () async {
      // The server presents a different identity key than the devices'
      // certificates were issued under.
      peers.server.accounts[bob.account]!.identityKey.fillRange(0, 32, 7);
      final row = await queue('to a forged identity');
      await alice.engine.drainOutbox();
      final op = await opOf(row);
      expect(op.state, OutboxState.failed);
      expect(op.lastError, 'untrusted_peer');
      expect(
        peers.server.sends.where((s) => s.from.id == alice.device),
        isEmpty,
        reason: 'nothing was sent',
      );
      expect(await alice.db.peopleDao.devicesOf(bob.account), isEmpty);
    });

    test('an unknown recipient fails with the server\'s answer', () async {
      final ghost = '0192a4f0-0000-7000-8000-0000000000ee';
      final chat = await alice.engine.chats.openDirect(ghost);
      final row = await alice.engine.chats.sendText(chat.id, 'anyone there?');
      await alice.engine.drainOutbox();
      final op = await opOf(row);
      expect(op.state, OutboxState.failed);
      expect(op.lastError, 'not_found');
    });
  });

  group('ordering', () {
    test('later messages of a chat wait for an earlier one that is backing '
        'off; other chats go on', () async {
      final carol = await peers.register('carol', phone: '+8801711000003');
      final first = await queue('one');
      final second = await queue('two');
      final other = await queue('hello Carol', to: carol);
      peers.server.failNext(Routes.sendMessage);

      await alice.engine.drainOutbox();
      // 'one' failed once; 'two' (same chat) was not tried; Carol's went.
      expect(await statusOf(first), MessageStatus.pending);
      expect(await statusOf(second), MessageStatus.pending);
      expect(await statusOf(other), MessageStatus.sent);
      expect(
        peers.server.sends
            .where((s) => s.from.id == alice.device)
            .map((s) => s.request.id),
        [other.messageId],
      );

      peers.clock.advance(const Duration(seconds: 3));
      await alice.engine.drainOutbox();
      expect(
        peers.server.sends
            .where((s) => s.from.id == alice.device)
            .map((s) => s.request.id),
        [other.messageId, first.messageId, second.messageId],
      );
      await bob.sync();
      expect(await bob.texts(alice), ['one', 'two']);
    });

    test(
      'the worker wakes itself on every enqueue and on retry timers',
      () async {
        final running = await peers.create(
          'running',
          clock: DateTime.now,
          config: fastConfig.copyWith(
            outboxBackoff: const Backoff(
              initial: Duration(milliseconds: 60),
              max: Duration(milliseconds: 200),
              jitter: 0,
            ),
          ),
        );
        await running.engine.account.requestPhoneCode('+8801711000009');
        await running.engine.account.register(
          verificationToken: 'verification',
          phoneNumber: '+8801711000009',
        );
        // Start the workers (no socket): the clock here is the real one.
        await running.engine.stop();
        await running.engine.start(realtime: false);
        final chat = await running.engine.chats.openDirect(bob.account);
        peers.server.failNext(Routes.sendMessage, times: 2);
        final row = await running.engine.chats.sendText(chat.id, 'by itself');
        // Nothing calls drainOutbox: the queue's change stream and the retry
        // timer do it.
        await _eventually(() async {
          final now = (await running.db.messagesDao.byRowid(row.localRowid))!;
          expect(now.status, MessageStatus.sent);
        });
        expect(
          peers.server.callsTo(Routes.sendMessage),
          greaterThanOrEqualTo(3),
        );
      },
    );
  });

  group('device lists', () {
    test('a device linked after Alice cached Bob is added after '
        'device_list_stale, and a revoked one is dropped', () async {
      await queue('first');
      await alice.engine.drainOutbox();
      expect((await alice.db.peopleDao.devicesOf(bob.account)).length, 1);

      final bob2 = await peers.link(bob, 'bob2');
      await queue('second');
      await alice.engine.drainOutbox();
      final statuses = peers.server.sends
          .where((s) => s.from.id == alice.device)
          .map((s) => s.status)
          .toList();
      expect(statuses, [200, 409, 200]);
      expect((await alice.db.peopleDao.devicesOf(bob.account)).length, 2);
      await bob.sync();
      await bob2.sync();
      expect(await bob.texts(alice), ['first', 'second']);
      expect(await bob2.texts(alice), ['second']);

      // Bob's second device is revoked: the next send learns it is gone.
      peers.server.revoke(bob2.device);
      await queue('third');
      await alice.engine.drainOutbox();
      expect(
        (await alice.db.peopleDao.devicesOf(
          bob.account,
        )).map((d) => d.deviceId),
        [bob.device],
      );
      expect(
        await alice.db.cryptoDao.sessionsWith(bob.account, bob2.device),
        isEmpty.or(hasLength(1)),
        reason: 'only retired base keys may remain',
      );
      await bob.sync();
      expect(await bob.texts(alice), ['first', 'second', 'third']);
    });

    test(
      'this account\'s own other devices get a copy of every send',
      () async {
        final alice2 = await peers.link(alice, 'alice2');
        await alice.engine.devices.refresh();
        await queue('with a copy');
        await alice.engine.drainOutbox();
        final send = peers.server.sends.last;
        expect(send.request.recipients.map((r) => r.account).toSet(), {
          alice.account,
          bob.account,
        });
        expect(
          send.request.recipients
              .firstWhere((r) => r.account == alice.account)
              .devices
              .map((d) => d.device),
          [alice2.device],
        );
        await alice2.sync();
        final copy = (await alice2.messages(bob)).single;
        expect(copy.outgoing, isTrue);
        expect(copy.body, 'with a copy');
      },
    );

    test(
      'a send addresses nobody twice and never the sending device',
      () async {
        await queue('plain');
        await alice.engine.drainOutbox();
        final send = peers.server.sends.last;
        expect(send.request.recipients, hasLength(1));
        expect(send.request.recipients.single.account, bob.account);
        expect(
          send.request.recipients.single.devices.single.device,
          bob.device,
        );
      },
    );
  });

  test('every enqueue goes through one path: the optimistic row and the '
      'op are written in one transaction', () async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    final row = await alice.engine.chats.sendText(chat.id, 'atomic');
    final op = await opOf(row);
    expect(op.idempotencyKey, row.messageId);
    expect(op.conversationId, chat.id);
    expect(await alice.db.messagesDao.byRowid(row.localRowid), isNotNull);
    // Deleting the message removes its queued op (cascade): a message that
    // is gone is not sent.
    await alice.db.messagesDao.removeMessages([row.localRowid]);
    expect(await alice.db.outboxDao.byId(op.id), isNull);
  });

  test('a revoked device ends itself when the server says so', () async {
    peers.server.revoke(bob.device);
    await expectLater(bob.engine.syncOnce(), throwsA(isA<ApiException>()));
    await _eventually(() async {
      expect(bob.engine.status, EngineStatus.revoked);
    });
    expect(await bob.db.accountDao.current(), isNull);
    expect(await bob.db.cryptoDao.identityKeys(), isNull);
  });
}

/// A matcher for "about this long" (the backoff has no jitter in tests, but
/// the clock moves a few milliseconds per read).
Matcher closeTo2(Duration expected) => predicate<Duration>(
  (d) => (d - expected).abs() < const Duration(milliseconds: 100),
  'within 100 ms of $expected',
);

Future<void> _eventually(Future<void> Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    try {
      await check();
      return;
    } on Object {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
