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

    final pendingAfterFail = db.getPendingOperations();
    expect(pendingAfterFail.length, equals(1));
    expect(pendingAfterFail.first['op_id'], equals('op_2'));
    expect(pendingAfterFail.first['status'], equals('PENDING'));
    expect(pendingAfterFail.first['retries'], equals(1));

    // Try processing again immediately - backoff should prevent processing
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
    expect(messages.first['text'], equals('hello alice decrypted text 2'));

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
}
