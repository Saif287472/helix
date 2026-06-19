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
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({required int sinceSequence}) async {
    return inboundEvents.where((e) => (e.serverSequence ?? 0) > sinceSequence).toList();
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
    sentOutboundOps.add({
      'opId': opId,
      'type': type,
      'payload': payload,
    });
  }
}

/// A gateway whose fetch always throws — used to prove batch rollback.
class _FailingFetchGateway implements SyncGateway {
  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({required int sinceSequence}) async {
    throw Exception('Simulated network failure');
  }

  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {}
}

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      String? foundPath;
      for (int i = 0; i < 5; i++) {
        final possiblePath = p.join(dir.path, '.dart_tool', 'lib', 'sqlite3.dll');
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
    expect(db.getPendingOperations().isEmpty, isTrue,
        reason: 'Backoff-scheduled op must not appear in the ready queue');

    // Processing immediately should also return 0 (nothing is due).
    final processedBackoff = await engine.processOutboundQueue(gateway);
    expect(processedBackoff, equals(0));
  });

  test('Inbound Sync fetches messages, suppresses duplicates and handles tombstones', () async {
    // 1. Enqueue mock messages in gateway
    gateway.inboundEvents.addAll([
      RemoteRealtimeEnvelope(
        eventId: 'msg_101',
        serverSequence: 1,
        schemaVersion: 1,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: 'chat_message',
        payload: {
          'sender_account_id': 'bob',
          'sender_device_id': 1,
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
          'sender_account_id': 'bob',
          'sender_device_id': 1,
          'ciphertext': 'hello alice decrypted text 2',
        },
      ),
    ]);

    // 2. Sync inbound
    final syncCount1 = await engine.syncInbound(gateway, 'conv_123');
    expect(syncCount1, equals(2));

    // Check database cursor
    expect(db.getSyncCursor('conv_123'), equals(2));

    // Check saved messages
    final messages = db.getMessages('conv_123');
    expect(messages.length, equals(2));
    expect(messages.first['ciphertext_blob'], equals('hello alice decrypted text 2'));

    // 3. Duplicate checks - sync again with same events, should not add messages
    final syncCount2 = await engine.syncInbound(gateway, 'conv_123');
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
          'sender_account_id': 'bob',
          'sender_device_id': 1,
          'ciphertext': 'deleted message',
        },
      ),
    );

    final syncCount3 = await engine.syncInbound(gateway, 'conv_123');
    expect(syncCount3, equals(0)); // skipped due to tombstone
    expect(db.getSyncCursor('conv_123'), equals(3)); // cursor still advances
  });

  // ---------------------------------------------------------------------------
  // Scenario D (Stage 4a/4c): batch atomicity — a failing batch must not
  // advance the cursor or persist partial message data.
  // ---------------------------------------------------------------------------

  group('Scenario D (Stage 4a/4c): inbound batch atomicity', () {
    test('Fetch failure leaves cursor and messages unchanged', () async {
      // Confirm baseline
      expect(db.getSyncCursor('conv_123'), equals(0));
      expect(db.getMessages('conv_123').isEmpty, isTrue);

      final failingGateway = _FailingFetchGateway();

      // syncInbound must throw and must NOT advance the cursor.
      expect(
        () => engine.syncInbound(failingGateway, 'conv_123'),
        throwsA(anything),
        reason: 'A failing fetch must propagate the exception',
      );

      expect(db.getSyncCursor('conv_123'), equals(0),
          reason: 'Cursor must be unchanged after a batch failure');
      expect(db.getMessages('conv_123').isEmpty, isTrue,
          reason: 'No messages must be persisted after a batch failure');
    });

    test('Cursor advances atomically after a successful full batch', () async {
      gateway.inboundEvents.addAll([
        RemoteRealtimeEnvelope(
          eventId: 'batch_msg_1',
          serverSequence: 10,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {'sender_account_id': 'alice', 'sender_device_id': 1, 'ciphertext': 'ct1'},
        ),
        RemoteRealtimeEnvelope(
          eventId: 'batch_msg_2',
          serverSequence: 11,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {'sender_account_id': 'alice', 'sender_device_id': 1, 'ciphertext': 'ct2'},
        ),
        RemoteRealtimeEnvelope(
          eventId: 'batch_msg_3',
          serverSequence: 12,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {'sender_account_id': 'alice', 'sender_device_id': 1, 'ciphertext': 'ct3'},
        ),
      ]);

      final count = await engine.syncInbound(gateway, 'conv_123');
      expect(count, equals(3));

      // Cursor must reflect the last event in the batch.
      expect(db.getSyncCursor('conv_123'), equals(12));

      // All three messages must be persisted.
      expect(db.getMessages('conv_123').length, equals(3));
    });

    test('Re-sync after failure re-fetches and applies the same batch', () async {
      gateway.inboundEvents.add(
        RemoteRealtimeEnvelope(
          eventId: 'retry_msg_1',
          serverSequence: 20,
          schemaVersion: 1,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: 'chat_message',
          payload: {'sender_account_id': 'bob', 'sender_device_id': 2, 'ciphertext': 'ct_retry'},
        ),
      );

      final failingGateway = _FailingFetchGateway();

      // First attempt: fails, cursor stays at 0.
      expect(() => engine.syncInbound(failingGateway, 'conv_123'), throwsA(anything));
      expect(db.getSyncCursor('conv_123'), equals(0));

      // Second attempt: uses the real gateway, succeeds.
      final count = await engine.syncInbound(gateway, 'conv_123');
      expect(count, equals(1));
      expect(db.getSyncCursor('conv_123'), equals(20));
    });
  });

  // ---------------------------------------------------------------------------
  // Scenario E/F (Stage 4b/4c): outbound queue — idempotency_key and
  // next_attempt_at are persisted; backoff is computed from failure time.
  // ---------------------------------------------------------------------------

  group('Scenario E/F (Stage 4b/4c): outbound queue backoff persistence', () {
    test('Enqueued operation carries idempotency_key and next_attempt_at = now', () {
      db.enqueueOperation('idem_op', 'SEND', '{}', idempotencyKey: 'stable-key-abc');
      final op = db.getOperationById('idem_op');
      expect(op, isNotNull);
      expect(op!['idempotency_key'], equals('stable-key-abc'));
      // next_attempt_at should be now-ish (within 2 seconds).
      final diff = DateTime.now().millisecondsSinceEpoch - (op['next_attempt_at'] as int);
      expect(diff.abs(), lessThan(2000));
    });

    test('After failure, next_attempt_at is strictly in the future', () async {
      gateway.failOutbound = true;
      db.enqueueOperation('backoff_op', 'SEND', '{}');

      await engine.processOutboundQueue(gateway);

      final op = db.getOperationById('backoff_op');
      expect(op!['retries'], equals(1));
      expect(
        op['next_attempt_at'] as int,
        greaterThan(DateTime.now().millisecondsSinceEpoch),
        reason: 'next_attempt_at must be a future timestamp after first failure',
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
  });
}
