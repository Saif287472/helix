import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('P10 repository transaction rolls back grouped writes', () {
    final db = BackendDatabase(sqlite3.openInMemory());
    addTearDown(db.close);
    final repos = SqliteBackendRepositories(db);

    expect(
      () => repos.run<void>(() {
        repos.createAccount('acct_tx', 'tx_user', 'pub');
        throw StateError('rollback');
      }),
      throwsStateError,
    );

    expect(repos.accountExists('acct_tx'), isFalse);
  });

  test(
    'P10 immutable migration plan validates checksum and phase ordering',
    () {
      const sql = 'CREATE TABLE phase10_example (id TEXT PRIMARY KEY);';
      final migration = BackendMigration(
        version: 1,
        phase: MigrationPhase.expand,
        name: 'create_example',
        sql: sql,
        checksum: sha256ForTest(sql),
      );
      final plan = BackendMigrationPlan([migration]);
      final policy = BackendMigrationPolicy(
        backupVerified: true,
        rollbackRunbook: Uri.parse('docs/workflows/RELEASE_ROLLBACK.md'),
      );

      expect(plan.pendingAfter(0), contains(migration));
      expect(() => policy.validateFor(migration), returnsNormally);
    },
  );

  test(
    'P10 object storage adapter stores opaque encrypted blobs only',
    () async {
      final root = await Directory.systemTemp.createTemp('helix_p10_objects_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final storage = LocalFileSystemObjectStorage(root);

      await storage.putObject('object_1', utf8.encode('ciphertext-only'));

      expect(await storage.exists('object_1'), isTrue);
      expect(
        utf8.decode(await storage.getObject('object_1')),
        'ciphertext-only',
      );
      await expectLater(
        storage.putObject('../escape', const [1, 2, 3]),
        throwsArgumentError,
      );
    },
  );

  test('P10 operational retention purges only bounded operational rows', () {
    final db = BackendDatabase(sqlite3.openInMemory());
    addTearDown(db.close);
    final futureCutoff = DateTime.now().millisecondsSinceEpoch + 60000;

    db.enqueueOutbox(
      'completed_old',
      'PUSH_NOTIFICATION',
      jsonEncode({'notification_type': 'new_message'}),
    );
    db.updateOutboxStatus('completed_old', 'COMPLETED', 0);
    db.enqueueOutbox(
      'pending_keep',
      'PUSH_NOTIFICATION',
      jsonEncode({'notification_type': 'new_message'}),
    );
    db.saveTombstone('old_msg', 'MESSAGE');

    final purged = db.purgeOperationalRecords(
      completedOutboxOlderThan: futureCutoff,
      auditOlderThan: futureCutoff,
      tombstonesOlderThan: futureCutoff,
    );

    expect(purged['outbox'], equals(1));
    expect(purged['tombstones'], equals(1));
    expect(db.getOutboxEvent('completed_old'), isNull);
    expect(db.getOutboxEvent('pending_keep'), isNotNull);
  });

  test('P10 rate limiter exposes replaceable state store for scaling', () {
    final store = InMemoryRateLimitStore();
    final limiter = RateLimiter(
      maxTokens: 1,
      refillRatePerSecond: 0,
      store: store,
    );

    expect(limiter.isAllowed('acct:alice'), isTrue);
    expect(limiter.isAllowed('acct:alice'), isFalse);
    expect(limiter.stats()['store'], contains('InMemoryRateLimitStore'));
  });

  test('P10 redacted logger removes tokens and sensitive fields', () {
    final logger = RedactedLogger(now: () => DateTime.utc(2026, 6, 20));

    final record = logger.log(
      LogSeverity.warning,
      'failed Authorization Bearer abc.def.ghi',
      fields: {
        'token': 'secret-token',
        'queue_depth': 7,
        'ciphertext': 'opaque-but-sensitive',
      },
      correlationId: 'corr_1',
    );

    final line = record.toJsonLine();
    expect(line, contains('corr_1'));
    expect(line, contains('queue_depth'));
    expect(line, isNot(contains('secret-token')));
    expect(line, isNot(contains('abc.def.ghi')));
    expect(line, isNot(contains('opaque-but-sensitive')));
  });

  test('P10 runbook documents required DR and load drills', () {
    final doc = File(
      '../../docs/performance/DR_DRILL_RUNBOOK.md',
    ).readAsStringSync();
    final datasets = File(
      '../../docs/performance/BENCHMARK_DATASETS.md',
    ).readAsStringSync();

    for (final phrase in [
      'Load baseline',
      'Reconnect storm',
      'Large mailbox',
      'Prekey depletion',
      'TURN outage',
      'Object-store outage',
      'DB failover rehearsal',
      'Retention purge',
    ]) {
      expect(doc, contains(phrase));
    }
    expect(datasets, contains('remote_messages_10k'));
    expect(datasets, contains('remote_messages_100k'));
  });
}

String sha256ForTest(String value) =>
    sha256.convert(utf8.encode(value)).toString();
