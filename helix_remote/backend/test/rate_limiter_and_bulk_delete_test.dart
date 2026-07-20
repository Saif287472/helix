// Batch 4 — bounded in-memory rate limit store + chunked mailbox deletes.

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryRateLimitStore TTL cleanup', () {
    test(
      'periodic cleanup evicts buckets that have been idle long enough to '
      'be fully refilled, bounding memory for a stream of one-off keys',
      () async {
        final store = InMemoryRateLimitStore(
          cleanupInterval: const Duration(milliseconds: 30),
        );
        addTearDown(store.dispose);

        // maxTokens=1, refillRate=1000/s => refills to full in ~1ms.
        for (var i = 0; i < 50; i++) {
          final bucket = store.bucketFor(
            'ip_$i',
            maxTokens: 1.0,
            refillRatePerSecond: 1000.0,
          );
          bucket.consume(1.0);
        }
        expect(store.trackedKeys, equals(50));

        // Long enough for both the buckets to refill and a cleanup tick to
        // run at least once.
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(store.trackedKeys, equals(0));
      },
    );

    test(
      'cleanup does not evict a bucket that is still genuinely rate-limited',
      () async {
        final store = InMemoryRateLimitStore(
          cleanupInterval: const Duration(milliseconds: 30),
        );
        addTearDown(store.dispose);

        // maxTokens=1, slow refill: still empty well past one cleanup tick.
        final bucket = store.bucketFor(
          'hot_ip',
          maxTokens: 1.0,
          refillRatePerSecond: 0.001,
        );
        expect(bucket.consume(1.0), isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(store.trackedKeys, equals(1));
      },
    );

    test('cleanupInterval=Duration.zero disables the periodic timer', () {
      final store = InMemoryRateLimitStore(cleanupInterval: Duration.zero);
      addTearDown(store.dispose);
      store.bucketFor('k', maxTokens: 1.0, refillRatePerSecond: 1.0);
      expect(store.trackedKeys, equals(1));
    });
  });

  group('Chunked mailbox deletes', () {
    late BackendDatabase db;

    setUp(() {
      db = BackendDatabase(sqlite3.openInMemory());
      db.createAccount('bulk_account', 'bulk_user', 'bulk_identity_key');
      db.registerDevice(
        'bulk_sender_device',
        'bulk_account',
        'bulk_sender_signing_key',
        'bulk_sender_agreement_key',
        'Bulk Sender',
      );
      db.createAccount('bulk_recipient', 'bulk_recipient_user', 'r_key');
      db.registerDevice(
        'bulk_recipient_device',
        'bulk_recipient',
        'r_signing_key',
        'r_agreement_key',
        'Bulk Recipient',
      );
      db.createConversation('conv_bulk', 'DIRECT', null, [
        'bulk_account',
        'bulk_recipient',
      ]);
    });

    tearDown(() => db.close());

    test(
      'deleteMessagesForDevice removes a mailbox spanning multiple '
      '500-row chunks in full',
      () async {
        const total = 1200; // 2 full chunks + 1 partial
        for (var i = 0; i < total; i++) {
          db.saveMessage(
            messageId: 'bulk_msg_$i',
            conversationId: 'conv_bulk',
            senderAccountId: 'bulk_account',
            senderDeviceId: 'bulk_sender_device',
            recipientDeviceId: 'bulk_recipient_device',
            ciphertext: 'ct_$i',
          );
        }
        expect(db.getMessage('bulk_msg_0'), isNotNull);
        expect(db.getMessage('bulk_msg_${total - 1}'), isNotNull);

        await db.deleteMessagesForDevice('bulk_recipient_device');

        for (final i in [0, 1, 499, 500, 999, 1000, total - 1]) {
          expect(
            db.getMessage('bulk_msg_$i'),
            isNull,
            reason: 'bulk_msg_$i should have been deleted',
          );
        }
        expect(db.quickCheckOk(), isTrue);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'deleteAccountData cascades message cleanup without an explicit '
      'per-device delete loop',
      () async {
        db.saveMessage(
          messageId: 'cascade_msg_1',
          conversationId: 'conv_bulk',
          senderAccountId: 'bulk_account',
          senderDeviceId: 'bulk_sender_device',
          recipientDeviceId: 'bulk_recipient_device',
          ciphertext: 'ct',
        );
        expect(db.getMessage('cascade_msg_1'), isNotNull);

        await db.deleteAccountData('bulk_recipient');

        expect(db.getMessage('cascade_msg_1'), isNull);
        expect(db.getAccount('bulk_recipient'), isNull);
        expect(db.quickCheckOk(), isTrue);
      },
    );
  });
}
