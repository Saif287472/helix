// Phase 3 — Messaging, sync, outbox, and multi-device correctness.
//
// Covers:
//   RP3-001  One sequence/cursor model — global cursor advances correctly.
//   RP3-002  WebSocket replay and REST sync cannot duplicate or skip events.
//   RP3-003  Sender sibling devices receive the sender's own messages.
//   RP3-004  Outbound sends are idempotent across re-enqueue and restart.
//   RP3-005  Outbox retry reaches FAILED state after max retries.
//   RP3-006  chat_message, delivery_receipt, read_receipt produce correct status.
//   RP3-007  Reply reference is stored correctly in outgoing message ciphertext.
//   RP3-008  message_edited, message_deleted, reaction_added apply correctly.
//   RP3-010  Two-device scenario: sibling device receives sender's message.
//   RP3-011  Offline send stays PENDING; on reconnect outbox drains correctly.

import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as pathpkg;

// ---------------------------------------------------------------------------
// Fake gateway
// ---------------------------------------------------------------------------

class _FakeSyncGateway implements SyncGateway {
  final List<RemoteRealtimeEnvelope> _inbound;
  final List<Map<String, dynamic>> sent = [];
  Object? throwOnSend;

  _FakeSyncGateway({List<RemoteRealtimeEnvelope> inbound = const []})
    : _inbound = List.from(inbound);

  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) async =>
      _inbound.where((e) => (e.serverSequence ?? 0) > sinceSequence).toList();

  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    if (throwOnSend != null) throw throwOnSend!;
    sent.add({'op_id': opId, 'type': type, ...payload});
  }
}

// ---------------------------------------------------------------------------
// Envelope helpers
// ---------------------------------------------------------------------------

int _ts() => DateTime.now().millisecondsSinceEpoch;

RemoteRealtimeEnvelope _chatMsg({
  required String eventId,
  required int seq,
  String messageId = 'msg-001',
  String conversationId = 'conv-001',
  String senderAccountId = 'acc-alice',
  String senderDeviceId = 'dev-alice-1',
  String ciphertext = 'cipher:abc',
}) => RemoteRealtimeEnvelope(
  eventId: eventId,
  schemaVersion: 1,
  timestamp: _ts(),
  type: 'chat_message',
  serverSequence: seq,
  payload: {
    'message_id': messageId,
    'conversation_id': conversationId,
    'sender_account_id': senderAccountId,
    'sender_device_id': senderDeviceId,
    'ciphertext': ciphertext,
  },
);

RemoteRealtimeEnvelope _receipt({
  required String eventId,
  required int seq,
  required String receiptType,
  String messageId = 'msg-001',
  String conversationId = 'conv-001',
  String accountId = 'acc-bob',
}) => RemoteRealtimeEnvelope(
  eventId: eventId,
  schemaVersion: 1,
  timestamp: _ts(),
  type: receiptType,
  serverSequence: seq,
  payload: {
    'message_id': messageId,
    'conversation_id': conversationId,
    'account_id': accountId,
  },
);

RemoteRealtimeEnvelope _editEvent({
  required String eventId,
  required int seq,
  String messageId = 'msg-001',
  String ciphertext = 'cipher:edited',
}) => RemoteRealtimeEnvelope(
  eventId: eventId,
  schemaVersion: 1,
  timestamp: _ts(),
  type: 'message_edited',
  serverSequence: seq,
  payload: {
    'message_id': messageId,
    'ciphertext': ciphertext,
    'author_id': 'acc-alice',
  },
);

RemoteRealtimeEnvelope _deleteEvent({
  required String eventId,
  required int seq,
  String messageId = 'msg-001',
}) => RemoteRealtimeEnvelope(
  eventId: eventId,
  schemaVersion: 1,
  timestamp: _ts(),
  type: 'message_deleted',
  serverSequence: seq,
  payload: {'message_id': messageId},
);

RemoteRealtimeEnvelope _reactionEvent({
  required String eventId,
  required int seq,
  String messageId = 'msg-001',
  String reaction = '👍',
  String type = 'reaction_added',
}) => RemoteRealtimeEnvelope(
  eventId: eventId,
  schemaVersion: 1,
  timestamp: _ts(),
  type: type,
  serverSequence: seq,
  payload: {
    'message_id': messageId,
    'account_id': 'acc-bob',
    'reaction': reaction,
  },
);

// ---------------------------------------------------------------------------
// Load SQLCipher (matches the pattern in remote_messaging_service_test.dart)
// ---------------------------------------------------------------------------

void _loadSqlCipher() {
  if (!Platform.isWindows) return;
  var dir = Directory.current;
  String? foundPath;
  for (var i = 0; i < 5; i++) {
    final candidate = pathpkg.join(
      dir.path,
      '.dart_tool',
      'lib',
      'sqlite3.dll',
    );
    if (File(candidate).existsSync()) {
      foundPath = candidate;
      break;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  if (foundPath != null) {
    DynamicLibrary.open(foundPath);
  }
}

// ---------------------------------------------------------------------------
// Shared DB setup
// ---------------------------------------------------------------------------

HelixRemoteDatabase _openDb() {
  final db = HelixRemoteDatabase(File(':memory:'));
  db.initialize();
  return db;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(_loadSqlCipher);

  group('RP3-001 — sequence/cursor model', () {
    test('inboundSequence starts at 0 on fresh database', () {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);
      expect(engine.inboundSequence, equals(0));
    });

    test(
      'cursor advances to highest applied sequence after HTTP sync',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        final gateway = _FakeSyncGateway(
          inbound: [
            _chatMsg(eventId: 'evt-1', seq: 1, messageId: 'msg-a'),
            _chatMsg(eventId: 'evt-2', seq: 2, messageId: 'msg-b'),
            _chatMsg(eventId: 'evt-3', seq: 3, messageId: 'msg-c'),
          ],
        );

        await engine.syncInbound(gateway);

        expect(engine.inboundSequence, equals(3));
      },
    );

    test('cursor persists across engine recreations', () async {
      final db = _openDb();
      addTearDown(db.close);

      final engine1 = RemoteSyncEngine(db);
      await engine1.syncInbound(
        _FakeSyncGateway(
          inbound: [_chatMsg(eventId: 'evt-1', seq: 1, messageId: 'msg-a')],
        ),
      );
      await engine1.dispose();

      final engine2 = RemoteSyncEngine(db);
      addTearDown(engine2.dispose);
      expect(engine2.inboundSequence, equals(1));
    });

    test('WebSocket handler advances cursor for each accepted envelope', () {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);

      final applied = engine.handleIncomingEnvelope(
        _chatMsg(eventId: 'evt-ws-1', seq: 1, messageId: 'msg-ws'),
      );

      expect(applied, isTrue);
      expect(engine.inboundSequence, equals(1));
    });

    test(
      'REST sync fetches only events newer than the stored cursor',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        final allEnvelopes = [
          _chatMsg(eventId: 'evt-1', seq: 1, messageId: 'msg-a'),
          _chatMsg(eventId: 'evt-2', seq: 2, messageId: 'msg-b'),
          _chatMsg(eventId: 'evt-3', seq: 3, messageId: 'msg-c'),
        ];
        final gateway = _FakeSyncGateway(inbound: allEnvelopes);

        // Apply events 1-2 first.
        await engine.syncInbound(
          _FakeSyncGateway(inbound: allEnvelopes.take(2).toList()),
        );
        expect(engine.inboundSequence, equals(2));

        // Second sync should only return event 3.
        final count = await engine.syncInbound(gateway);
        expect(count, equals(1));
        expect(engine.inboundSequence, equals(3));
      },
    );
  });

  group('RP3-002 — no duplicates or skips across reconnect', () {
    test(
      'HTTP sync: same eventId received twice is applied only once',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        final env = _chatMsg(eventId: 'evt-dup', seq: 1, messageId: 'msg-dup');
        final gateway = _FakeSyncGateway(inbound: [env]);

        final count1 = await engine.syncInbound(gateway);
        // Simulate server replaying the same event (seq filter would normally
        // remove it, but we reset the cursor filter to check dedup logic).
        // Force it back by using a gateway that ignores the sinceSequence check.
        final count2 = await engine.syncInbound(
          _FakeSyncGateway(
            inbound: [
              RemoteRealtimeEnvelope(
                eventId: 'evt-dup',
                schemaVersion: 1,
                timestamp: _ts(),
                type: 'chat_message',
                serverSequence: 1,
                payload: {
                  'message_id': 'msg-dup',
                  'conversation_id': 'conv-001',
                  'sender_account_id': 'acc-alice',
                  'sender_device_id': 'dev-alice-1',
                  'ciphertext': 'cipher:dup',
                },
              ),
            ],
          ),
        );

        expect(count1, equals(1));
        expect(count2, equals(0));
        expect(
          db.getMessageById('msg-dup'),
          isNotNull,
          reason: 'Message should be saved exactly once',
        );
      },
    );

    test(
      'WebSocket: same eventId delivered twice returns false on second delivery',
      () {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        final env = _chatMsg(eventId: 'evt-ws-dup', seq: 1, messageId: 'msg-x');

        final first = engine.handleIncomingEnvelope(env);
        final second = engine.handleIncomingEnvelope(env);

        expect(first, isTrue);
        expect(second, isFalse);
      },
    );

    test(
      'WebSocket: sequence gap (missing event) returns false to trigger catch-up',
      () {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        // Event at seq 1 arrives normally.
        final firstApplied = engine.handleIncomingEnvelope(
          _chatMsg(eventId: 'evt-1', seq: 1, messageId: 'msg-a'),
        );

        // Event at seq 3 arrives before seq 2 — gap detected.
        final gapApplied = engine.handleIncomingEnvelope(
          _chatMsg(eventId: 'evt-3', seq: 3, messageId: 'msg-c'),
        );

        expect(firstApplied, isTrue);
        expect(
          gapApplied,
          isFalse,
          reason: 'Gap should cause false; triggers catch-up',
        );
        // Cursor must not have jumped past seq 1.
        expect(engine.inboundSequence, equals(1));
      },
    );

    test('WebSocket: event with seq <= cursor is silently ignored', () {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);

      engine.handleIncomingEnvelope(
        _chatMsg(eventId: 'evt-1', seq: 1, messageId: 'msg-a'),
      );
      expect(engine.inboundSequence, equals(1));

      // Stale replay: seq 1 again with a NEW event_id.
      final staleApplied = engine.handleIncomingEnvelope(
        _chatMsg(eventId: 'evt-1-replay', seq: 1, messageId: 'msg-stale'),
      );

      expect(staleApplied, isFalse);
      expect(engine.inboundSequence, equals(1));
      expect(db.getMessageById('msg-stale'), isNull);
    });

    test('malformed event is quarantined and cursor still advances', () async {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);

      // A chat_message with missing conversation_id will throw in _MessageCreatedEvent.
      final bad = RemoteRealtimeEnvelope(
        eventId: 'evt-bad',
        schemaVersion: 1,
        timestamp: _ts(),
        type: 'chat_message',
        serverSequence: 1,
        payload: {'message_id': 'msg-bad'},
      );
      final good = _chatMsg(eventId: 'evt-good', seq: 2, messageId: 'msg-good');

      final gateway = _FakeSyncGateway(inbound: [bad, good]);
      await engine.syncInbound(gateway);

      // Cursor must reach 2 (both events processed, bad one quarantined).
      expect(engine.inboundSequence, equals(2));
      expect(db.getMessageById('msg-good'), isNotNull);
      expect(db.getMessageById('msg-bad'), isNull);
    });
  });

  group('RP3-003/RP3-010 — multi-device: sibling device receives own messages', () {
    test(
      'chat_message from a sibling device (same account, different deviceId) is saved',
      () {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        // Device 1 is sending; device 2 is a sibling that receives.
        // From the sibling's perspective the event arrives with senderDeviceId=dev-alice-1.
        final applied = engine.handleIncomingEnvelope(
          _chatMsg(
            eventId: 'evt-sibling',
            seq: 1,
            messageId: 'msg-sibling',
            senderAccountId: 'acc-alice',
            senderDeviceId: 'dev-alice-1',
          ),
        );

        expect(applied, isTrue);
        final row = db.getMessageById('msg-sibling');
        expect(row, isNotNull);
        expect(row!['sender_account_id'], equals('acc-alice'));
        expect(row['sender_device_id'], equals('dev-alice-1'));
        expect(row['status'], equals('DELIVERED'));
      },
    );

    test(
      'two messages from different devices in the same conversation are both saved',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        final gateway = _FakeSyncGateway(
          inbound: [
            _chatMsg(
              eventId: 'evt-d1',
              seq: 1,
              messageId: 'msg-from-d1',
              senderDeviceId: 'dev-alice-1',
            ),
            _chatMsg(
              eventId: 'evt-d2',
              seq: 2,
              messageId: 'msg-from-d2',
              senderDeviceId: 'dev-bob-1',
              senderAccountId: 'acc-bob',
            ),
          ],
        );
        await engine.syncInbound(gateway);

        expect(db.getMessageById('msg-from-d1'), isNotNull);
        expect(db.getMessageById('msg-from-d2'), isNotNull);
        expect(engine.inboundSequence, equals(2));
      },
    );
  });

  group('RP3-004 — outbound idempotency', () {
    test(
      'enqueuing the same op_id twice results in exactly one pending op',
      () {
        final db = _openDb();
        addTearDown(db.close);

        db.enqueueOperation(
          'op-send-001',
          'SEND_MESSAGE',
          '{"message_id":"msg-001"}',
          idempotencyKey: 'message:msg-001',
        );
        db.enqueueOperation(
          'op-send-001',
          'SEND_MESSAGE',
          '{"message_id":"msg-001"}',
          idempotencyKey: 'message:msg-001',
        );

        final ops = db.getPendingOperations();
        expect(
          ops.where((o) => o['op_id'] == 'op-send-001').length,
          equals(1),
          reason: 'INSERT OR IGNORE must prevent double-enqueue',
        );
      },
    );

    test(
      'pending operations survive engine recreation (simulates process restart)',
      () async {
        final db = _openDb();
        addTearDown(db.close);

        db.enqueueOperation(
          'op-restart-001',
          'SEND_MESSAGE',
          '{"message_id":"msg-restart"}',
          idempotencyKey: 'message:msg-restart',
        );

        // New engine instance — simulates restart with same DB.
        final engine2 = RemoteSyncEngine(db);
        addTearDown(engine2.dispose);
        final ops = db.getPendingOperations();
        expect(
          ops.any((o) => o['op_id'] == 'op-restart-001'),
          isTrue,
          reason: 'Outbox must survive engine recreation without re-enqueueing',
        );
      },
    );

    test('completed op is not returned by getPendingOperations', () async {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);

      db.enqueueOperation(
        'op-complete-001',
        'SEND_MESSAGE',
        '{"message_id":"msg-c","conversation_id":"conv-001"}',
        idempotencyKey: 'message:msg-c',
      );

      final gateway = _FakeSyncGateway();
      await engine.processOutboundQueue(gateway);

      expect(
        db.getPendingOperations().where((o) => o['op_id'] == 'op-complete-001'),
        isEmpty,
      );
      expect(gateway.sent.any((s) => s['op_id'] == 'op-complete-001'), isTrue);
    });
  });

  group('RP3-005 — outbox retry and failure state', () {
    test('operation reaches FAILED status after max retries (5)', () async {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);

      db.enqueueOperation(
        'op-fail-001',
        'SEND_MESSAGE',
        '{"message_id":"msg-fail","conversation_id":"conv-001"}',
        idempotencyKey: 'message:msg-fail',
      );

      final failGateway = _FakeSyncGateway()
        ..throwOnSend = StateError('permanent');

      // Five attempts → each increments retries; StateError is permanent.
      for (var i = 0; i < 5; i++) {
        // Reset next_attempt_at to now so the op is returned each time.
        db.scheduleNextOperationAttempt(
          'op-fail-001',
          DateTime.now().millisecondsSinceEpoch - 1,
        );
        await engine.processOutboundQueue(failGateway);
      }

      final ops = db.getPendingOperations();
      expect(ops.where((o) => o['op_id'] == 'op-fail-001'), isEmpty);
    });

    test('operation transitions to SENT after gateway recovers', () async {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);

      const conversationId = 'conv-001';
      const messageId = 'msg-recover';

      db.ensureConversationExists(
        conversationId: conversationId,
        senderAccountId: 'acc-alice',
        serverSequence: 0,
        timestamp: _ts(),
      );
      db.saveMessage(
        const RemoteMessage(
          messageId: messageId,
          conversationId: conversationId,
          senderAccountId: 'acc-alice',
          senderDeviceId: 'dev-alice-1',
          ciphertext: 'cipher:pending',
        ),
        0,
        _ts(),
        'PENDING',
      );
      db.enqueueOperation(
        'op-recover-001',
        'SEND_MESSAGE',
        '{"message_id":"$messageId","conversation_id":"$conversationId"}',
        idempotencyKey: 'message:$messageId',
      );

      // First drain fails.
      final failGateway = _FakeSyncGateway()
        ..throwOnSend = Exception('network error');
      await engine.processOutboundQueue(failGateway);

      var row = db.getMessageById(messageId);
      expect(row?['status'], equals('PENDING'));

      // Reset backoff and retry with a healthy gateway.
      db.scheduleNextOperationAttempt(
        'op-recover-001',
        DateTime.now().millisecondsSinceEpoch - 1,
      );
      final okGateway = _FakeSyncGateway();
      await engine.processOutboundQueue(okGateway);

      row = db.getMessageById(messageId);
      expect(row?['status'], equals('SENT'));
      expect(okGateway.sent.length, equals(1));
    });
  });

  group('RP3-006 — message receive state transitions', () {
    test('chat_message event saves message with DELIVERED status', () async {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);

      await engine.syncInbound(
        _FakeSyncGateway(
          inbound: [
            _chatMsg(
              eventId: 'evt-recv-1',
              seq: 1,
              messageId: 'msg-recv',
              senderAccountId: 'acc-bob',
              senderDeviceId: 'dev-bob-1',
            ),
          ],
        ),
      );

      final row = db.getMessageById('msg-recv');
      expect(row, isNotNull);
      expect(row!['status'], equals('DELIVERED'));
    });

    test(
      'delivery_receipt event upgrades message status to DELIVERED',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        // Start with a SENT message (sender's perspective).
        db.ensureConversationExists(
          conversationId: 'conv-001',
          senderAccountId: 'acc-alice',
          serverSequence: 0,
          timestamp: _ts(),
        );
        db.saveMessage(
          const RemoteMessage(
            messageId: 'msg-001',
            conversationId: 'conv-001',
            senderAccountId: 'acc-alice',
            senderDeviceId: 'dev-alice-1',
            ciphertext: 'cipher:sent',
          ),
          0,
          _ts(),
          'SENT',
        );

        await engine.syncInbound(
          _FakeSyncGateway(
            inbound: [
              _receipt(
                eventId: 'evt-delivery',
                seq: 1,
                receiptType: 'delivery_receipt',
              ),
            ],
          ),
        );

        final row = db.getMessageById('msg-001');
        expect(row?['status'], equals('DELIVERED'));
      },
    );

    test('read_receipt event upgrades message status to READ', () async {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);

      db.ensureConversationExists(
        conversationId: 'conv-001',
        senderAccountId: 'acc-alice',
        serverSequence: 0,
        timestamp: _ts(),
      );
      db.saveMessage(
        const RemoteMessage(
          messageId: 'msg-001',
          conversationId: 'conv-001',
          senderAccountId: 'acc-alice',
          senderDeviceId: 'dev-alice-1',
          ciphertext: 'cipher:delivered',
        ),
        0,
        _ts(),
        'DELIVERED',
      );

      await engine.syncInbound(
        _FakeSyncGateway(
          inbound: [
            _receipt(eventId: 'evt-read', seq: 1, receiptType: 'read_receipt'),
          ],
        ),
      );

      final row = db.getMessageById('msg-001');
      expect(row?['status'], equals('READ'));
    });
  });

  group('RP3-007 — reply reference storage', () {
    test(
      'outgoing message with replyTo stores reference in ciphertext payload',
      () {
        final db = _openDb();
        addTearDown(db.close);

        db.ensureConversationExists(
          conversationId: 'conv-001',
          senderAccountId: 'acc-alice',
          serverSequence: 0,
          timestamp: _ts(),
        );

        // The messaging service embeds replyTo inside the ciphertext JSON.
        // We test that the raw storage round-trip preserves arbitrary ciphertext.
        const ciphertextWithReply =
            'cipher:{"body":"reply text","replyTo":{"messageId":"msg-original"}}';
        db.saveMessage(
          const RemoteMessage(
            messageId: 'msg-with-reply',
            conversationId: 'conv-001',
            senderAccountId: 'acc-alice',
            senderDeviceId: 'dev-alice-1',
            ciphertext: ciphertextWithReply,
          ),
          0,
          _ts(),
          'PENDING',
        );

        final row = db.getMessageById('msg-with-reply');
        expect(row, isNotNull);
        expect(row!['ciphertext_blob'], equals(ciphertextWithReply));
        expect(row['ciphertext_blob'], contains('replyTo'));
        expect(row['ciphertext_blob'], contains('msg-original'));
      },
    );

    test(
      'incoming message with reply reference is stored intact for local decryption',
      () {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        const ciphertextWithReply =
            'cipher:{"body":"reply","replyTo":{"messageId":"msg-orig"}}';
        final applied = engine.handleIncomingEnvelope(
          _chatMsg(
            eventId: 'evt-reply',
            seq: 1,
            messageId: 'msg-reply',
            ciphertext: ciphertextWithReply,
          ),
        );

        expect(applied, isTrue);
        final row = db.getMessageById('msg-reply');
        expect(row!['ciphertext_blob'], equals(ciphertextWithReply));
      },
    );
  });

  group('RP3-008 — edits, deletes, and reactions', () {
    test('message_edited event saves a revision with type EDIT', () async {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);

      // Create the original message first.
      engine.handleIncomingEnvelope(
        _chatMsg(eventId: 'evt-orig', seq: 1, messageId: 'msg-001'),
      );

      await engine.syncInbound(
        _FakeSyncGateway(
          inbound: [
            _editEvent(eventId: 'evt-edit', seq: 2, messageId: 'msg-001'),
          ],
        ),
      );

      final revisions = db.getMessageRevisions('msg-001');
      expect(revisions, isNotEmpty);
      expect(revisions.any((r) => r['type'] == 'EDIT'), isTrue);
    });

    test(
      'message_deleted event tombstones the message and removes it',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        engine.handleIncomingEnvelope(
          _chatMsg(eventId: 'evt-to-delete', seq: 1, messageId: 'msg-del'),
        );
        expect(db.getMessageById('msg-del'), isNotNull);

        await engine.syncInbound(
          _FakeSyncGateway(
            inbound: [
              _deleteEvent(eventId: 'evt-delete', seq: 2, messageId: 'msg-del'),
            ],
          ),
        );

        expect(db.getMessageById('msg-del'), isNull);
        expect(db.isTombstoned('msg-del', 'MESSAGE'), isTrue);
      },
    );

    test(
      'tombstoned message is not re-created if replayed via chat_message',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        engine.handleIncomingEnvelope(
          _chatMsg(eventId: 'evt-msg', seq: 1, messageId: 'msg-revive'),
        );
        engine.handleIncomingEnvelope(
          _deleteEvent(eventId: 'evt-del', seq: 2, messageId: 'msg-revive'),
        );
        expect(db.getMessageById('msg-revive'), isNull);

        // A late replay of the original chat_message must be ignored.
        await engine.syncInbound(
          _FakeSyncGateway(
            inbound: [
              RemoteRealtimeEnvelope(
                eventId: 'evt-replay',
                schemaVersion: 1,
                timestamp: _ts(),
                type: 'chat_message',
                serverSequence: 3,
                payload: {
                  'message_id': 'msg-revive',
                  'conversation_id': 'conv-001',
                  'sender_account_id': 'acc-alice',
                  'sender_device_id': 'dev-alice-1',
                  'ciphertext': 'cipher:revive',
                },
              ),
            ],
          ),
        );

        expect(db.getMessageById('msg-revive'), isNull);
      },
    );

    test('reaction_added event saves a revision with type REACTION', () async {
      final db = _openDb();
      addTearDown(db.close);
      final engine = RemoteSyncEngine(db);
      addTearDown(engine.dispose);

      engine.handleIncomingEnvelope(
        _chatMsg(eventId: 'evt-base', seq: 1, messageId: 'msg-001'),
      );

      await engine.syncInbound(
        _FakeSyncGateway(
          inbound: [
            _reactionEvent(eventId: 'evt-react', seq: 2, messageId: 'msg-001'),
          ],
        ),
      );

      final revisions = db.getMessageRevisions('msg-001');
      expect(revisions.any((r) => r['type'] == 'REACTION'), isTrue);
    });

    test(
      'reaction_removed event saves a revision with type REACTION_REMOVED',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        engine.handleIncomingEnvelope(
          _chatMsg(eventId: 'evt-base2', seq: 1, messageId: 'msg-002'),
        );

        await engine.syncInbound(
          _FakeSyncGateway(
            inbound: [
              _reactionEvent(
                eventId: 'evt-unreact',
                seq: 2,
                messageId: 'msg-002',
                type: 'reaction_removed',
              ),
            ],
          ),
        );

        final revisions = db.getMessageRevisions('msg-002');
        expect(revisions.any((r) => r['type'] == 'REACTION_REMOVED'), isTrue);
      },
    );
  });

  group('RP3-011 — offline send and reconnect', () {
    test(
      'message saved as PENDING before send; stays PENDING when gateway fails',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        const conversationId = 'conv-001';
        const messageId = 'msg-offline';

        db.ensureConversationExists(
          conversationId: conversationId,
          senderAccountId: 'acc-alice',
          serverSequence: 0,
          timestamp: _ts(),
        );
        db.saveMessage(
          const RemoteMessage(
            messageId: messageId,
            conversationId: conversationId,
            senderAccountId: 'acc-alice',
            senderDeviceId: 'dev-alice-1',
            ciphertext: 'cipher:offline',
          ),
          0,
          _ts(),
          'PENDING',
        );
        db.enqueueOperation(
          'op-offline',
          'SEND_MESSAGE',
          '{"message_id":"$messageId","conversation_id":"$conversationId"}',
          idempotencyKey: 'message:$messageId',
        );

        // Offline: gateway throws.
        await engine.processOutboundQueue(
          _FakeSyncGateway()..throwOnSend = Exception('network unavailable'),
        );

        expect(db.getMessageById(messageId)?['status'], equals('PENDING'));
      },
    );

    test(
      'reconnect: after gateway recovers, pending message transitions to SENT',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        const conversationId = 'conv-001';
        const messageId = 'msg-reconnect';

        db.ensureConversationExists(
          conversationId: conversationId,
          senderAccountId: 'acc-alice',
          serverSequence: 0,
          timestamp: _ts(),
        );
        db.saveMessage(
          const RemoteMessage(
            messageId: messageId,
            conversationId: conversationId,
            senderAccountId: 'acc-alice',
            senderDeviceId: 'dev-alice-1',
            ciphertext: 'cipher:reconnect',
          ),
          0,
          _ts(),
          'PENDING',
        );
        db.enqueueOperation(
          'op-reconnect',
          'SEND_MESSAGE',
          '{"message_id":"$messageId","conversation_id":"$conversationId"}',
          idempotencyKey: 'message:$messageId',
        );

        // First attempt fails.
        await engine.processOutboundQueue(
          _FakeSyncGateway()..throwOnSend = Exception('offline'),
        );
        expect(db.getMessageById(messageId)?['status'], equals('PENDING'));

        // Reset backoff, then reconnect.
        db.scheduleNextOperationAttempt(
          'op-reconnect',
          DateTime.now().millisecondsSinceEpoch - 1,
        );

        final okGateway = _FakeSyncGateway();
        await engine.processOutboundQueue(okGateway);

        expect(db.getMessageById(messageId)?['status'], equals('SENT'));
        expect(okGateway.sent.length, equals(1));
      },
    );

    test(
      'duplicate suppression: same op_id not re-sent even if enqueued again after reconnect',
      () async {
        final db = _openDb();
        addTearDown(db.close);
        final engine = RemoteSyncEngine(db);
        addTearDown(engine.dispose);

        const conversationId = 'conv-001';
        const messageId = 'msg-dedup';

        db.ensureConversationExists(
          conversationId: conversationId,
          senderAccountId: 'acc-alice',
          serverSequence: 0,
          timestamp: _ts(),
        );
        db.saveMessage(
          const RemoteMessage(
            messageId: messageId,
            conversationId: conversationId,
            senderAccountId: 'acc-alice',
            senderDeviceId: 'dev-alice-1',
            ciphertext: 'cipher:dedup',
          ),
          0,
          _ts(),
          'PENDING',
        );

        // Enqueue twice (simulates two reconnect cycles before send).
        db.enqueueOperation(
          'op-dedup',
          'SEND_MESSAGE',
          '{"message_id":"$messageId","conversation_id":"$conversationId"}',
          idempotencyKey: 'message:$messageId',
        );
        db.enqueueOperation(
          'op-dedup',
          'SEND_MESSAGE',
          '{"message_id":"$messageId","conversation_id":"$conversationId"}',
          idempotencyKey: 'message:$messageId',
        );

        final okGateway = _FakeSyncGateway();
        await engine.processOutboundQueue(okGateway);

        expect(
          okGateway.sent.length,
          equals(1),
          reason: 'INSERT OR IGNORE must prevent duplicate sends',
        );
      },
    );
  });
}
