import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;

class MockSyncGateway implements SyncGateway {
  final List<RemoteRealtimeEnvelope> inboundEvents = [];
  final List<Map<String, dynamic>> sentOutboundOps = [];
  bool failOutbound = false;

  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) async {
    return inboundEvents
        .where((e) => (e.serverSequence ?? 0) > sinceSequence)
        .toList();
  }

  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    if (failOutbound) {
      throw Exception('Network error');
    }
    sentOutboundOps.add({'opId': opId, 'type': type, 'payload': payload});
  }
}

/// A gateway whose fetch always throws. Used to prove batch rollback.
class _FailingFetchGateway implements SyncGateway {
  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) async {
    throw Exception('Simulated network failure');
  }

  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {}
}

class _StaticFetchGateway implements SyncGateway {
  _StaticFetchGateway(this.events);

  final List<RemoteRealtimeEnvelope> events;

  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) async {
    return events;
  }

  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {}
}

class _DelayedSendGateway implements SyncGateway {
  _DelayedSendGateway(this.release);

  final Future<void> release;
  int sendCalls = 0;

  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) async {
    return const [];
  }

  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    sendCalls++;
    await release;
  }
}

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      String? foundPath;
      for (int i = 0; i < 5; i++) {
        final possiblePath = p.join(
          dir.path,
          '.dart_tool',
          'lib',
          'sqlite3.dll',
        );
        if (File(possiblePath).existsSync()) {
          foundPath = possiblePath;
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
  });

  late HelixRemoteDatabase db;
  late RemoteSyncEngine engine;
  late MockSyncGateway gateway;

  setUp(() {
    db = HelixRemoteDatabase(File(':memory:'));
    db.initialize();
    engine = RemoteSyncEngine(db);
    gateway = MockSyncGateway();

    // Create a mock conversation to allow sync operations
    final conversation = RemoteConversation(
      conversationId: 'conv_123',
      title: 'Sync Chat',
      type: 'DIRECT',
      lastActivitySequence: 0,
      createdAt: DateTime.now(),
    );
    db.upsertConversation(conversation, ['alice', 'bob']);
  });

  tearDown(() {
    db.close();
  });

  test('Outbound Queue processing with success and backoff fail', () async {
    db.enqueueOperation('op_1', 'SEND_MESSAGE', '{"text": "Hello Bob"}');

    // 1. Successful dispatch
    final processed = await engine.processOutboundQueue(gateway);
    expect(processed, equals(1));
    expect(gateway.sentOutboundOps.length, equals(1));
    expect(gateway.sentOutboundOps.first['opId'], equals('op_1'));

    // Check database status
    final pending = db.getPendingOperations();
    expect(pending.isEmpty, isTrue);

    // 2. Failed dispatch with retry backoff
    gateway.failOutbound = true;
    db.enqueueOperation('op_2', 'SEND_MESSAGE', '{"text": "Retry test"}');

    final processedFail = await engine.processOutboundQueue(gateway);
    expect(processedFail, equals(0));

    // Use getOperationById to inspect state without the backoff time filter.
    final op2State = db.getOperationById('op_2');
    expect(op2State, isNotNull);
    expect(op2State!['op_id'], equals('op_2'));
    expect(op2State['status'], equals('PENDING'));
    expect(op2State['retries'], equals(1));
    // next_attempt_at must be in the future (backoff is active).
    expect(
      op2State['next_attempt_at'] as int,
      greaterThan(DateTime.now().millisecondsSinceEpoch),
      reason: 'Backoff deadline must be a future timestamp',
    );

    // getPendingOperations() should return 0 while backoff deadline is in the future.
    expect(
      db.getPendingOperations().isEmpty,
      isTrue,
      reason: 'Backoff-scheduled op must not appear in the ready queue',
    );

    // Processing immediately should also return 0 (nothing is due).
    final processedBackoff = await engine.processOutboundQueue(gateway);
    expect(processedBackoff, equals(0));
  });

  test(
    'Inbound Sync uses authoritative conversation IDs from event payloads',
    () async {
      final otherConversation = RemoteConversation(
        conversationId: 'conv_authoritative',
        title: 'Server-scoped chat',
        type: 'DIRECT',
        lastActivitySequence: 0,
        createdAt: DateTime.now(),
      );
      db.upsertConversation(otherConversation, ['alice', 'carol']);

      // 1. Enqueue mock messages in gateway
      gateway.inboundEvents.addAll([
        RemoteRealtimeEnvelope(
          eventId: 'msg_101',
          serverSequence: 1,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'conversation_id': 'conv_authoritative',
            'sender_account_id': 'bob',
            'sender_device_id': 'device1',
            'ciphertext': 'hello alice decrypted text 1',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'msg_102',
          serverSequence: 2,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'conversation_id': 'conv_authoritative',
            'sender_account_id': 'bob',
            'sender_device_id': 'device1',
            'ciphertext': 'hello alice decrypted text 2',
          },
        ),
      ]);

      // 2. Sync inbound
      final syncCount1 = await engine.syncInbound(gateway);
      expect(syncCount1, equals(2));

      // Caller-supplied conversation relabeling is gone: messages land in the
      // conversation carried by the server envelope payload, not the default
      // test conversation.
      expect(db.getMessages('conv_123'), isEmpty);

      // Check saved messages
      final messages = db.getMessages('conv_authoritative');
      expect(messages.length, equals(2));
      expect(
        messages.first['ciphertext_blob'],
        equals('hello alice decrypted text 2'),
      );

      // 3. Duplicate checks - sync again with same events, should not add messages
      final syncCount2 = await engine.syncInbound(gateway);
      expect(syncCount2, equals(0));

      // 4. Tombstones - tombstone msg_103, enqueue it, sync, it should be skipped
      db.saveTombstone('msg_103', 'MESSAGE');
      gateway.inboundEvents.add(
        RemoteRealtimeEnvelope(
          eventId: 'msg_103',
          serverSequence: 3,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'conversation_id': 'conv_authoritative',
            'sender_account_id': 'bob',
            'sender_device_id': 'device1',
            'ciphertext': 'deleted message',
          },
        ),
      );

      final syncCount3 = await engine.syncInbound(gateway);
      expect(syncCount3, equals(0)); // skipped due to tombstone
    },
  );

  test(
    'Typed event dispatch applies foundational events and redacts unknown diagnostics',
    () async {
      final diagnostics = <String>[];
      engine = RemoteSyncEngine(db, diagnostics: diagnostics.add);
      db.upsertAccount(
        RemoteAccount(
          accountId: 'alice',
          username: 'alice_old',
          identityPublicKey: 'alice_identity',
          createdAt: DateTime.now(),
        ),
      );

      gateway.inboundEvents.addAll([
        RemoteRealtimeEnvelope(
          eventId: 'event_conversation_created',
          serverSequence: 1,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'conversation_created',
          payload: {
            'conversation_id': 'conv_typed',
            'conversation_type': 'GROUP',
            'title': 'Typed handlers',
            'member_ids': ['alice'],
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_membership_added',
          serverSequence: 2,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'membership_changed',
          payload: {
            'conversation_id': 'conv_typed',
            'account_id': 'bob',
            'action': 'added',
            'role': 'MEMBER',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_message_created',
          serverSequence: 3,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'message_id': 'msg_typed_1',
            'conversation_id': 'conv_typed',
            'sender_account_id': 'alice',
            'sender_device_id': 'device1',
            'ciphertext': 'opaque-ciphertext',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_delivery_receipt',
          serverSequence: 4,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'delivery_receipt',
          payload: {
            'message_id': 'msg_typed_1',
            'conversation_id': 'conv_typed',
            'account_id': 'bob',
            'device_id': 'device2',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_read_receipt',
          serverSequence: 5,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'read_receipt',
          payload: {
            'message_id': 'msg_typed_1',
            'conversation_id': 'conv_typed',
            'account_id': 'bob',
            'device_id': 'device2',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_message_created_for_revision',
          serverSequence: 6,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'message_id': 'msg_typed_2',
            'conversation_id': 'conv_typed',
            'sender_account_id': 'alice',
            'sender_device_id': 'device1',
            'ciphertext': 'opaque-ciphertext-for-revision',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_message_edited',
          serverSequence: 7,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'message_edited',
          payload: {
            'message_id': 'msg_typed_2',
            'conversation_id': 'conv_typed',
            'author_id': 'alice',
            'ciphertext': 'opaque-edited-ciphertext',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_reaction_added',
          serverSequence: 8,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'reaction_added',
          payload: {
            'message_id': 'msg_typed_2',
            'conversation_id': 'conv_typed',
            'author_id': 'bob',
            'reaction': '+1',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_contact_updated',
          serverSequence: 9,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'contact_updated',
          payload: {
            'peer_account_id': 'carol',
            'nickname': 'Carol',
            'status': 'Accepted',
            'request_id': 'cr_carol',
            'direction': 'received',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_contact_removed',
          serverSequence: 10,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'contact_removed',
          payload: {'peer_account_id': 'carol'},
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_profile_updated',
          serverSequence: 11,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'profile_updated',
          payload: {'account_id': 'alice', 'username': 'alice_new'},
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_privacy_updated',
          serverSequence: 12,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'privacy_updated',
          payload: {'presence_visibility': 'NOBODY'},
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_membership_removed',
          serverSequence: 13,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'membership_changed',
          payload: {
            'conversation_id': 'conv_typed',
            'account_id': 'bob',
            'action': 'removed',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_message_deleted',
          serverSequence: 14,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'message_deleted',
          payload: {
            'message_id': 'msg_typed_1',
            'conversation_id': 'conv_typed',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'event_unknown_full_id_must_not_log',
          serverSequence: 15,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'future_required_event',
          payload: {'plaintext': 'SECRET_MESSAGE_SENTINEL'},
          isUnrecognized: true,
        ),
      ]);

      final applied = await engine.syncInbound(gateway);

      expect(applied, equals(14));
      expect(
        db.getConversations().map((c) => c.conversationId),
        contains('conv_typed'),
      );
      expect(db.getConversationMembers('conv_typed'), ['alice']);
      final remainingMessages = db.getMessages('conv_typed');
      expect(remainingMessages.single['message_id'], equals('msg_typed_2'));
      expect(db.isTombstoned('msg_typed_1', 'MESSAGE'), isTrue);

      final revisions = db.getMessageRevisions('msg_typed_2');
      expect(
        revisions.map((r) => r['type']),
        containsAll(['EDIT', 'REACTION']),
      );
      expect(
        revisions.map((r) => r['payload']).join(' '),
        contains('opaque-edited-ciphertext'),
      );
      expect(db.getContact('carol'), isNull);
      expect(db.getContactRequest('cr_carol')!.status, 'Accepted');
      expect(db.getAccount('alice')!.username, equals('alice_new'));

      final receipts = db.getMessageReceipts('msg_typed_1');
      expect(
        receipts.map((r) => r['receipt_type']),
        containsAll(['DELIVERY', 'READ']),
      );

      expect(db.getSyncCursor('__remote_global_stream__'), equals(15));
      expect(diagnostics.length, equals(1));
      expect(diagnostics.single, contains('future_required_event'));
      expect(
        diagnostics.single,
        isNot(contains('event_unknown_full_id_must_not_log')),
      );
      expect(diagnostics.single, isNot(contains('SECRET_MESSAGE_SENTINEL')));
    },
  );

  group('Stage 4.4 duplicate and reordered event protection', () {
    test(
      'Duplicate event IDs are suppressed before applying effects',
      () async {
        final duplicate = RemoteRealtimeEnvelope(
          eventId: 'event_duplicate_once',
          serverSequence: 1,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'message_id': 'msg_duplicate_once',
            'conversation_id': 'conv_123',
            'sender_account_id': 'alice',
            'sender_device_id': 'device1',
            'ciphertext': 'first-copy',
          },
        );

        gateway.inboundEvents.addAll([duplicate, duplicate]);

        final applied = await engine.syncInbound(gateway);

        expect(applied, equals(1));
        final messages = db.getMessages('conv_123');
        expect(messages.length, equals(1));
        expect(messages.single['message_id'], equals('msg_duplicate_once'));
        expect(db.hasProcessedEventId('event_duplicate_once'), isTrue);
        expect(db.getSyncCursor('__remote_global_stream__'), equals(1));
      },
    );

    test('Unseen sequence regression fails closed and rolls back', () async {
      db.updateSyncCursor('__remote_global_stream__', 5);
      final regressionGateway = _StaticFetchGateway([
        RemoteRealtimeEnvelope(
          eventId: 'event_sequence_regression',
          serverSequence: 4,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'message_id': 'msg_regression',
            'conversation_id': 'conv_123',
            'sender_account_id': 'alice',
            'sender_device_id': 'device1',
            'ciphertext': 'must-not-apply',
          },
        ),
      ]);

      expect(
        () => engine.syncInbound(regressionGateway),
        throwsA(isA<StateError>()),
      );

      expect(db.getSyncCursor('__remote_global_stream__'), equals(5));
      expect(db.getMessages('conv_123'), isEmpty);
      expect(db.hasProcessedEventId('event_sequence_regression'), isFalse);
    });

    test('Inbound sequence gap fails closed and leaves cursor unchanged', () {
      final gapGateway = _StaticFetchGateway([
        RemoteRealtimeEnvelope(
          eventId: 'event_sequence_gap',
          serverSequence: 2,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'message_id': 'msg_gap',
            'conversation_id': 'conv_123',
            'sender_account_id': 'alice',
            'sender_device_id': 'device1',
            'ciphertext': 'must-not-apply',
          },
        ),
      ]);

      expect(() => engine.syncInbound(gapGateway), throwsA(isA<StateError>()));
      expect(db.getSyncCursor('__remote_global_stream__'), equals(0));
      expect(db.getMessages('conv_123'), isEmpty);
      expect(db.hasProcessedEventId('event_sequence_gap'), isFalse);
    });

    test('Realtime sequence gap does not advance cursor', () {
      final diagnostics = <String>[];
      engine = RemoteSyncEngine(db, diagnostics: diagnostics.add);

      final applied = engine.handleIncomingEnvelope(
        RemoteRealtimeEnvelope(
          eventId: 'event_realtime_gap',
          serverSequence: 2,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'message_id': 'msg_realtime_gap',
            'conversation_id': 'conv_123',
            'sender_account_id': 'alice',
            'sender_device_id': 'device1',
            'ciphertext': 'must-not-apply',
          },
        ),
      );

      expect(applied, isFalse);
      expect(db.getSyncCursor('__remote_global_stream__'), equals(0));
      expect(db.getMessages('conv_123'), isEmpty);
      expect(diagnostics.single, contains('sequence gap'));
    });
  });

  // ---------------------------------------------------------------------------
  // Scenario D (Stage 4a/4c): batch atomicity. A failing batch must not
  // advance the cursor or persist partial message data.
  // ---------------------------------------------------------------------------

  group('Scenario D (Stage 4a/4c): inbound batch atomicity', () {
    test('Fetch failure leaves cursor and messages unchanged', () async {
      // Confirm baseline
      expect(db.getSyncCursor('__remote_global_stream__'), equals(0));
      expect(db.getMessages('conv_123').isEmpty, isTrue);

      final failingGateway = _FailingFetchGateway();

      // syncInbound must throw and must NOT advance the cursor.
      expect(
        () => engine.syncInbound(failingGateway),
        throwsA(anything),
        reason: 'A failing fetch must propagate the exception',
      );

      expect(
        db.getSyncCursor('__remote_global_stream__'),
        equals(0),
        reason: 'Cursor must be unchanged after a batch failure',
      );
      expect(
        db.getMessages('conv_123').isEmpty,
        isTrue,
        reason: 'No messages must be persisted after a batch failure',
      );
    });

    test('Cursor advances atomically after a successful full batch', () async {
      gateway.inboundEvents.addAll([
        RemoteRealtimeEnvelope(
          eventId: 'batch_msg_1',
          serverSequence: 1,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'conversation_id': 'conv_123',
            'sender_account_id': 'alice',
            'sender_device_id': 'device1',
            'ciphertext': 'ct1',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'batch_msg_2',
          serverSequence: 2,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'conversation_id': 'conv_123',
            'sender_account_id': 'alice',
            'sender_device_id': 'device1',
            'ciphertext': 'ct2',
          },
        ),
        RemoteRealtimeEnvelope(
          eventId: 'batch_msg_3',
          serverSequence: 3,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {
            'conversation_id': 'conv_123',
            'sender_account_id': 'alice',
            'sender_device_id': 'device1',
            'ciphertext': 'ct3',
          },
        ),
      ]);

      final count = await engine.syncInbound(gateway);
      expect(count, equals(3));

      // Cursor must reflect the last event in the batch.
      expect(db.getSyncCursor('__remote_global_stream__'), equals(3));

      // All three messages must be persisted.
      expect(db.getMessages('conv_123').length, equals(3));
    });

    test(
      'Re-sync after failure re-fetches and applies the same batch',
      () async {
        gateway.inboundEvents.add(
          RemoteRealtimeEnvelope(
            eventId: 'retry_msg_1',
            serverSequence: 1,
            schemaVersion: 1,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            type: 'chat_message',
            payload: {
              'conversation_id': 'conv_123',
              'sender_account_id': 'bob',
              'sender_device_id': 'device2',
              'ciphertext': 'ct_retry',
            },
          ),
        );

        final failingGateway = _FailingFetchGateway();

        // First attempt: fails, cursor stays at 0.
        expect(() => engine.syncInbound(failingGateway), throwsA(anything));
        expect(db.getSyncCursor('__remote_global_stream__'), equals(0));

        // Second attempt: uses the real gateway, succeeds.
        final count = await engine.syncInbound(gateway);
        expect(count, equals(1));
        expect(db.getSyncCursor('__remote_global_stream__'), equals(1));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Scenario E/F (Stage 4b/4c): outbound queue. idempotency_key and
  // next_attempt_at are persisted; backoff is computed from failure time.
  // ---------------------------------------------------------------------------

  group('Scenario E/F (Stage 4b/4c): outbound queue backoff persistence', () {
    test(
      'Enqueued operation carries idempotency_key and next_attempt_at = now',
      () {
        db.enqueueOperation(
          'idem_op',
          'SEND',
          '{}',
          idempotencyKey: 'stable-key-abc',
        );
        final op = db.getOperationById('idem_op');
        expect(op, isNotNull);
        expect(op!['idempotency_key'], equals('stable-key-abc'));
        // next_attempt_at should be now-ish (within 2 seconds).
        final diff =
            DateTime.now().millisecondsSinceEpoch -
            (op['next_attempt_at'] as int);
        expect(diff.abs(), lessThan(2000));
      },
    );

    test('After failure, next_attempt_at is strictly in the future', () async {
      gateway.failOutbound = true;
      db.enqueueOperation('backoff_op', 'SEND', '{}');

      await engine.processOutboundQueue(gateway);

      final op = db.getOperationById('backoff_op');
      expect(op!['retries'], equals(1));
      expect(
        op['next_attempt_at'] as int,
        greaterThan(DateTime.now().millisecondsSinceEpoch),
        reason:
            'next_attempt_at must be a future timestamp after first failure',
      );

      // The op must not be visible in the ready queue.
      expect(db.getPendingOperations().isEmpty, isTrue);
    });

    test('Operation is DLQ-ed after 5 failures', () async {
      gateway.failOutbound = true;
      db.enqueueOperation('dlq_op', 'SEND', '{}');

      // Force-advance retries to 4 so the next failure pushes it to FAILED.
      db.updateOperationStatus('dlq_op', 'PENDING', 4);
      db.scheduleNextOperationAttempt('dlq_op', 0); // make it due now

      await engine.processOutboundQueue(gateway);

      final op = db.getOperationById('dlq_op');
      expect(op!['status'], equals('FAILED'));
      expect(op['retries'], equals(5));
    });

    test(
      'Concurrent outbound drains share a single in-flight worker',
      () async {
        db.enqueueOperation('single_flight_op', 'SEND_MESSAGE', '{}');
        final release = Completer<void>();
        final delayedGateway = _DelayedSendGateway(release.future);

        final first = engine.processOutboundQueue(delayedGateway);
        final second = engine.processOutboundQueue(delayedGateway);

        await Future<void>.delayed(Duration.zero);
        expect(delayedGateway.sendCalls, equals(1));

        release.complete();
        expect(await first, equals(1));
        expect(await second, equals(1));
        expect(delayedGateway.sendCalls, equals(1));
      },
    );
  });
}
