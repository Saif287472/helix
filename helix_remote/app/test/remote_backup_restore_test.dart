import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:path/path.dart' as pathpkg;

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
  if (foundPath != null) DynamicLibrary.open(foundPath);
}

HelixRemoteDatabase _freshDb() {
  final db = HelixRemoteDatabase(File(':memory:'));
  db.initialize();
  return db;
}

void main() {
  setUpAll(_loadSqlCipher);

  // -------------------------------------------------------------------------
  // RP5-010 — Schema version gate
  // -------------------------------------------------------------------------

  // 28 adds unmatched_phone_contacts (+ its sync marker), so the "not on
  // Helix yet" list survives leaving the Contacts screen.
  //
  // Deliberately a literal rather than HelixRemoteMigrations
  // .latestSchemaVersion: compared against the constant this test could only
  // ever agree with itself. Spelled out, it fails on any schema change and
  // makes bumping the version a decision someone took rather than something
  // that happened.
  test('RP5-010: fresh in-memory database has schema version 28', () {
    final db = _freshDb();
    addTearDown(db.close);
    expect(db.schemaVersion, equals(28));
  });

  // -------------------------------------------------------------------------
  // RP5-007 — Backup snapshot covers all required tables
  // -------------------------------------------------------------------------

  test(
    'RP5-007: exportBackupSnapshot returns versioned JSON with all required table keys',
    () {
      final db = _freshDb();
      addTearDown(db.close);

      final snapshot = db.exportBackupSnapshot();
      final decoded = jsonDecode(snapshot) as Map<String, dynamic>;

      expect(decoded['version'], equals(2));
      expect(decoded['snapshot_version'], equals(2));
      expect(decoded['restore_semantics'], equals('replace_local_state'));
      expect(decoded['exported_at'], isA<int>());
      expect(
        decoded.keys,
        containsAll([
          'version',
          'snapshot_version',
          'exported_at',
          'restore_semantics',
          'manifest',
          'accounts',
          'devices',
          'contacts',
          'contact_requests',
          'conversations',
          'members',
          'messages',
          'message_receipts',
          'revisions',
          'attachments',
          'groups',
          'group_epoch_keys',
          'group_invites',
          'call_history',
          'tombstones',
          'attachment_manifest',
        ]),
      );
      // crypto_sessions stores device-local history seeds; intentionally excluded
      // so that a restore to a new device starts fresh per-conversation seeds.
      expect(decoded.keys, isNot(contains('crypto_sessions')));
    },
  );

  test(
    'RP5-007: exportBackupSnapshot includes saved attachment metadata (encrypted key survives round-trip)',
    () {
      final db = _freshDb();
      addTearDown(db.close);

      db.saveAttachment(
        attachmentId: 'att_snap_001',
        filename: 'photo.jpg',
        sizeBytes: 1024,
        encryptedKey: 'wrapped_key_base64url_value',
        status: 'PENDING',
      );

      final snapshot = db.exportBackupSnapshot();
      final decoded = jsonDecode(snapshot) as Map<String, dynamic>;
      final attachments = (decoded['attachments'] as List)
          .cast<Map<String, dynamic>>();

      expect(attachments, hasLength(1));
      expect(attachments.first['attachment_id'], equals('att_snap_001'));
      // encrypted_key must survive the snapshot — recipients need it to re-download
      expect(
        attachments.first['encrypted_key'],
        equals('wrapped_key_base64url_value'),
      );

      // Round-trip: restore to a fresh DB and verify the attachment row is present
      final restored = _freshDb();
      addTearDown(restored.close);

      restored.restoreBackupSnapshot(snapshot);
      final att = restored.getAttachment('att_snap_001');
      expect(att, isNotNull);
      expect(att!['filename'], equals('photo.jpg'));
      expect(att['encrypted_key'], equals('wrapped_key_base64url_value'));
    },
  );

  test(
    'RP5-007: exportBackupSnapshot includes account and device state (identity and signing keys)',
    () {
      final db = _freshDb();
      addTearDown(db.close);

      db.upsertAccount(
        RemoteAccount(
          accountId: 'acc_p5',
          identityPublicKey: 'phase5_identity_key',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          status: 'Active',
        ),
      );
      db.upsertDevice(
        'acc_p5',
        RemoteDevice(
          deviceId: 'dev_p5',
          deviceName: 'Phase5 Phone',
          deviceSigningPublicKey: 'signing_key_p5',
          deviceAgreementPublicKey: 'agreement_key_p5',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );

      final snapshot = db.exportBackupSnapshot();
      final decoded = jsonDecode(snapshot) as Map<String, dynamic>;

      final accounts = (decoded['accounts'] as List)
          .cast<Map<String, dynamic>>();
      expect(accounts.any((a) => a['account_id'] == 'acc_p5'), isTrue);
      final accountRow = accounts.firstWhere(
        (a) => a['account_id'] == 'acc_p5',
      );
      expect(accountRow['identity_public_key'], equals('phase5_identity_key'));

      final devices = (decoded['devices'] as List).cast<Map<String, dynamic>>();
      expect(devices.any((d) => d['device_id'] == 'dev_p5'), isTrue);
      final deviceRow = devices.firstWhere((d) => d['device_id'] == 'dev_p5');
      expect(deviceRow['device_signing_public_key'], equals('signing_key_p5'));
    },
  );

  test(
    'RP5-007: backup encrypt-decrypt round-trip preserves original snapshot via Argon2id-AES-GCM envelope',
    () async {
      final db = _freshDb();
      addTearDown(db.close);

      db.saveAttachment(
        attachmentId: 'att_crypto_p5',
        filename: 'secret.pdf',
        sizeBytes: 2048,
        encryptedKey: 'wrapped_key_for_crypto_test_p5',
        status: 'COMPLETED',
      );

      final snapshot = db.exportBackupSnapshot();
      final plaintextBytes = Uint8List.fromList(utf8.encode(snapshot));

      const passphrase = 'correct-horse-battery-staple-2026';
      const backupId = 'backup_p5_test_001';
      final crypto = RemoteBackupCrypto();

      final envelope = await crypto.encryptBackupEnvelope(
        plaintext: plaintextBytes,
        passphrase: passphrase,
        backupId: backupId,
        backupKeyHint: 'User-held recovery secret required',
      );

      // Envelope metadata: versioned, KDF-tagged, non-empty salt
      expect(envelope.version, equals(RemoteBackupCrypto.currentBackupVersion));
      expect(envelope.kdf, contains('Argon2id'));
      expect(envelope.snapshotVersion, equals(2));
      expect(envelope.salt, hasLength(greaterThan(0)));
      expect(envelope.backupKeyHint, isNotEmpty);

      // Decryption reproduces the exact original bytes
      final decrypted = await crypto.decryptBackupEnvelope(
        envelope,
        passphrase: passphrase,
      );
      final restoredSnapshot = utf8.decode(decrypted);
      expect(restoredSnapshot, equals(snapshot));

      // Full end-to-end: restore the decrypted snapshot and verify attachment row
      final restored = _freshDb();
      addTearDown(restored.close);

      restored.restoreBackupSnapshot(restoredSnapshot);
      final att = restored.getAttachment('att_crypto_p5');
      expect(att, isNotNull);
      expect(att!['filename'], equals('secret.pdf'));
      expect(att['encrypted_key'], equals('wrapped_key_for_crypto_test_p5'));
    },
  );

  // -------------------------------------------------------------------------
  // RP5-008 — Restore atomicity
  // -------------------------------------------------------------------------

  test(
    'RP5-008: restoreBackupSnapshot applies all rows to a fresh database',
    () {
      final source = _freshDb();
      addTearDown(source.close);

      source.upsertAccount(
        RemoteAccount(
          accountId: 'acc_restore_p5',
          identityPublicKey: 'restore_identity_p5',
          createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
          status: 'Active',
        ),
      );
      source.saveAttachment(
        attachmentId: 'att_restore_p5',
        filename: 'restore.txt',
        sizeBytes: 512,
        encryptedKey: 'restored_key_p5',
        status: 'DOWNLOADED',
      );

      final snapshot = source.exportBackupSnapshot();

      final fresh = _freshDb();
      addTearDown(fresh.close);

      fresh.restoreBackupSnapshot(snapshot);

      expect(
        fresh.getAccount('acc_restore_p5')?.identityPublicKey,
        equals('restore_identity_p5'),
      );
      expect(
        fresh.getAttachment('att_restore_p5')!['filename'],
        equals('restore.txt'),
      );
    },
  );

  test(
    'RP5-008: prior state is preserved when restore fails — SAVEPOINT ensures atomicity',
    () {
      final db = _freshDb();
      addTearDown(db.close);

      // Pre-existing attachment that must survive a failed restore attempt
      db.saveAttachment(
        attachmentId: 'att_existing_p5',
        filename: 'existing.txt',
        sizeBytes: 100,
        encryptedKey: 'existing_key_p5',
        status: 'COMPLETED',
      );

      expect(db.getAttachment('att_existing_p5'), isNotNull);

      // A restore with an unsupported version must roll back the entire transaction
      expect(
        () => db.restoreBackupSnapshot(
          '{"version": 999, "accounts": [], "attachments": [{"attachment_id": "att_intruder", "filename": "intruder.txt", "size_bytes": 0, "encrypted_key": "", "status": "PENDING"}]}',
        ),
        throwsUnsupportedError,
      );

      // Pre-existing attachment intact; the rolled-back row must not exist
      expect(db.getAttachment('att_existing_p5'), isNotNull);
      expect(db.getAttachment('att_intruder'), isNull);
    },
  );

  // -------------------------------------------------------------------------
  // RP5-009 — Restore scenarios
  // -------------------------------------------------------------------------

  test(
    'RP5-009: restoreBackupSnapshot rejects version != 1 with UnsupportedError',
    () {
      final db = _freshDb();
      addTearDown(db.close);

      expect(
        () => db.restoreBackupSnapshot('{"version": 99, "accounts": []}'),
        throwsUnsupportedError,
      );
      expect(
        () => db.restoreBackupSnapshot('{"version": 0, "accounts": []}'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'RP5-009: restore on a different install (separate in-memory DB) works end-to-end',
    () {
      final source = _freshDb();
      addTearDown(source.close);

      source.upsertAccount(
        RemoteAccount(
          accountId: 'acc_install_b',
          identityPublicKey: 'install_b_identity',
          createdAt: DateTime.fromMillisecondsSinceEpoch(3000),
          status: 'Active',
        ),
      );

      final snapshot = source.exportBackupSnapshot();

      // Simulate restoring on a completely different device/install
      final installB = _freshDb();
      addTearDown(installB.close);

      installB.restoreBackupSnapshot(snapshot);

      expect(
        installB.getAccount('acc_install_b')?.identityPublicKey,
        equals('install_b_identity'),
      );
    },
  );

  test(
    'RP5-009: restoreBackupSnapshot with all empty tables is a safe no-op',
    () {
      final db = _freshDb();
      addTearDown(db.close);

      final emptySnapshot = jsonEncode({
        'version': 1,
        'exported_at': 0,
        'accounts': [],
        'devices': [],
        'contacts': [],
        'contact_requests': [],
        'conversations': [],
        'members': [],
        'messages': [],
        'message_receipts': [],
        'revisions': [],
        'attachments': [],
        'groups': [],
        'group_epoch_keys': [],
        'group_invites': [],
        'call_history': [],
        'tombstones': [],
      });

      expect(() => db.restoreBackupSnapshot(emptySnapshot), returnsNormally);
      expect(db.getConversations(), isEmpty);
    },
  );

  test('F2 transfer archive round-trips through schema-neutral JSON', () {
    final source = _freshDb();
    addTearDown(source.close);
    source.upsertAccount(
      RemoteAccount(
        accountId: 'acc_transfer',
        identityPublicKey: 'transfer_identity',
        createdAt: DateTime.fromMillisecondsSinceEpoch(4000),
        status: 'Active',
      ),
    );

    final archive = source.exportTransferArchive(sourcePlatform: 'windows');
    final decoded = jsonDecode(archive) as Map<String, dynamic>;
    expect(decoded['type'], equals('helix.remote.transfer-archive'));
    expect(decoded['snapshot'], isA<Map<String, dynamic>>());

    final restored = _freshDb();
    addTearDown(restored.close);
    restored.restoreTransferArchive(archive);
    expect(
      restored.getAccount('acc_transfer')?.identityPublicKey,
      'transfer_identity',
    );
  });

  test('F3 locked and view-once content is excluded from backup snapshots', () {
    final db = _freshDb();
    addTearDown(db.close);

    db.upsertConversation(
      RemoteConversation(
        conversationId: 'conv_visible',
        type: 'DIRECT',
        title: 'Visible',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        lastActivitySequence: 1,
      ),
      ['alice', 'bob'],
    );
    db.upsertConversation(
      RemoteConversation(
        conversationId: 'conv_locked',
        type: 'DIRECT',
        title: 'Locked',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        lastActivitySequence: 2,
      ),
      ['alice', 'bob'],
    );
    db.setConversationLocked('conv_locked', locked: true);
    db.saveMessage(
      const RemoteMessage(
        messageId: 'msg_visible',
        conversationId: 'conv_visible',
        senderAccountId: 'alice',
        senderDeviceId: 'dev',
        ciphertext: 'cipher-visible',
      ),
      1,
      1000,
      'SENT',
    );
    db.saveMessage(
      const RemoteMessage(
        messageId: 'msg_locked',
        conversationId: 'conv_locked',
        senderAccountId: 'alice',
        senderDeviceId: 'dev',
        ciphertext: 'cipher-locked',
      ),
      2,
      1000,
      'SENT',
    );
    db.saveMessage(
      const RemoteMessage(
        messageId: 'msg_view_once',
        conversationId: 'conv_visible',
        senderAccountId: 'alice',
        senderDeviceId: 'dev',
        ciphertext: 'cipher-view-once',
      ),
      3,
      1000,
      'SENT',
    );
    db.setMessagePrivacyMetadata(messageId: 'msg_view_once', viewOnce: true);

    final decoded =
        jsonDecode(db.exportBackupSnapshot()) as Map<String, dynamic>;
    final conversations = (decoded['conversations'] as List)
        .cast<Map<String, dynamic>>();
    final messages = (decoded['messages'] as List).cast<Map<String, dynamic>>();

    expect(
      conversations.map((row) => row['conversation_id']),
      contains('conv_visible'),
    );
    expect(
      conversations.map((row) => row['conversation_id']),
      isNot(contains('conv_locked')),
    );
    expect(messages.map((row) => row['message_id']), contains('msg_visible'));
    expect(
      messages.map((row) => row['message_id']),
      isNot(contains('msg_locked')),
    );
    expect(
      messages.map((row) => row['message_id']),
      isNot(contains('msg_view_once')),
    );
  });

  test('F2 backup key wraps support platform and recovery fallback', () async {
    final helper = RemoteBackupCrypto();
    final platformKey = Uint8List.fromList(List<int>.filled(32, 7));
    final envelope = await helper.encryptBackupEnvelopeWithWrappedKey(
      plaintext: Uint8List.fromList('portable encrypted snapshot'.codeUnits),
      recoverySecret: 'six word recovery secret fallback',
      platformWrappingKey: platformKey,
      backupId: 'backup_f2_wrapped',
      backupKeyHint: 'platform credential or recovery secret',
    );

    expect(
      envelope.keyWraps.map((wrap) => wrap.method),
      containsAll([
        RemoteBackupCrypto.platformKeyWrapMethod,
        RemoteBackupCrypto.recoveryKeyWrapMethod,
      ]),
    );
    final platformPlaintext = await helper.decryptBackupEnvelope(
      envelope,
      passphrase: 'not used when platform key is present',
      platformWrappingKey: platformKey,
    );
    expect(utf8.decode(platformPlaintext), 'portable encrypted snapshot');

    final recoveryPlaintext = await helper.decryptBackupEnvelope(
      envelope,
      passphrase: 'six word recovery secret fallback',
    );
    expect(utf8.decode(recoveryPlaintext), 'portable encrypted snapshot');
  });
}
