import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:crypto/crypto.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

void main() {
  late BackendServer server;
  late int port;
  late String token;
  late String bobToken;
  late String malloryToken;
  final tempStorageDir = Directory('test_attachments_storage');

  setUp(() async {
    if (tempStorageDir.existsSync()) {
      tempStorageDir.deleteSync(recursive: true);
    }
    tempStorageDir.createSync(recursive: true);

    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_attachments_testing',
      rateLimitMaxTokens: 100.0,
      rateLimitRefillRate: 10.0,
      attachmentsStorageDir: tempStorageDir,
      // Explicit rather than relying on the defaults: those are an operator
      // choice now (settable per deployment via .env and reported to the
      // client through /server/info), so a test pinned to them would break
      // whenever someone tuned a limit. These assert the mechanism.
      maxAttachmentBytes: 10 * 1024 * 1024,
      accountQuotaBytes: 50 * 1024 * 1024,
    );

    // Register a mock user and device in the backend DB to perform auth
    final db = server.db;
    db.createAccount('user1', 'alice', 'alice_identity_public_key');
    db.registerDevice('device1', 'user1', 'device_public_key', 'Alice Device');
    db.createAccount('user2', 'bob', 'bob_identity_public_key');
    db.registerDevice(
      'device2',
      'user2',
      'bob_device_public_key',
      'Bob Device',
    );
    db.createAccount('user3', 'mallory', 'mallory_identity_public_key');
    db.registerDevice(
      'device3',
      'user3',
      'mallory_device_public_key',
      'Mallory Device',
    );

    // Generate JWT token for user1/device1
    token = server.jwt.generateToken({
      'account_id': 'user1',
      'device_id': 'device1',
    }, const Duration(hours: 1));
    bobToken = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
    malloryToken = server.jwt.generateToken({
      'account_id': 'user3',
      'device_id': 'device3',
    }, const Duration(hours: 1));

    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async {
    await server.stop();
    if (tempStorageDir.existsSync()) {
      tempStorageDir.deleteSync(recursive: true);
    }
  });

  test(
    'Resumable upload, status checks, hash verification, and resumable download range checks',
    () async {
      final client = HttpClient();

      // 0. Setup dummy file content
      final originalBytes = List.generate(1000, (i) => i % 256);
      final fileHash = sha256.convert(originalBytes).toString();
      final fileSize = originalBytes.length;

      // 1. Request upload URL
      final uploadReq = await client.post(
        '127.0.0.1',
        port,
        '/api/v1/attachments/upload',
      );
      uploadReq.headers.set('Authorization', 'Bearer $token');
      uploadReq.headers.set('Content-Type', 'application/json');
      uploadReq.add(
        utf8.encode(jsonEncode({'file_size': fileSize, 'file_hash': fileHash})),
      );
      var resp = await uploadReq.close();
      expect(resp.statusCode, equals(200));

      final uploadReqBody =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      final fileId = uploadReqBody['file_id'] as String;
      final uploadUrl = uploadReqBody['upload_url'] as String;
      expect(fileId, equals(fileHash));
      expect(uploadUrl, contains(fileId));

      // 2. Query status (should show 0 uploaded bytes)
      final statusReq1 = await client.get(
        '127.0.0.1',
        port,
        '/api/v1/attachments/upload/status/$fileId',
      );
      statusReq1.headers.set('Authorization', 'Bearer $token');
      resp = await statusReq1.close();
      expect(resp.statusCode, equals(200));
      var statusBody =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(statusBody['uploaded_bytes'], equals(0));
      expect(statusBody['status'], equals('PENDING'));

      // 3. Upload first chunk (400 bytes)
      final chunk1 = originalBytes.sublist(0, 400);
      final putReq1 = await client.put(
        '127.0.0.1',
        port,
        '/api/v1/attachments/upload/file/$fileId?offset=0',
      );
      putReq1.headers.set('Authorization', 'Bearer $token');
      putReq1.add(chunk1);
      resp = await putReq1.close();
      expect(resp.statusCode, equals(200));
      var putBody =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(putBody['uploaded_bytes'], equals(400));
      expect(putBody['status'], equals('UPLOADING'));

      // 4. Query status (should show 400 uploaded bytes)
      final statusReq2 = await client.get(
        '127.0.0.1',
        port,
        '/api/v1/attachments/upload/status/$fileId',
      );
      statusReq2.headers.set('Authorization', 'Bearer $token');
      resp = await statusReq2.close();
      expect(resp.statusCode, equals(200));
      statusBody =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(statusBody['uploaded_bytes'], equals(400));
      expect(statusBody['status'], equals('UPLOADING'));

      // 5. Upload second chunk (remaining 600 bytes)
      final chunk2 = originalBytes.sublist(400, 1000);
      final putReq2 = await client.put(
        '127.0.0.1',
        port,
        '/api/v1/attachments/upload/file/$fileId?offset=400',
      );
      putReq2.headers.set('Authorization', 'Bearer $token');
      putReq2.add(chunk2);
      resp = await putReq2.close();
      expect(resp.statusCode, equals(200));
      putBody =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(putBody['uploaded_bytes'], equals(1000));
      expect(putBody['status'], equals('COMPLETED'));

      // 6. Query status (should show 1000 uploaded bytes, status COMPLETED)
      final statusReq3 = await client.get(
        '127.0.0.1',
        port,
        '/api/v1/attachments/upload/status/$fileId',
      );
      statusReq3.headers.set('Authorization', 'Bearer $token');
      resp = await statusReq3.close();
      expect(resp.statusCode, equals(200));
      statusBody =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(statusBody['uploaded_bytes'], equals(1000));
      expect(statusBody['status'], equals('COMPLETED'));

      // 7. Request download
      final downloadReq = await client.get(
        '127.0.0.1',
        port,
        '/api/v1/attachments/download/$fileId',
      );
      downloadReq.headers.set('Authorization', 'Bearer $token');
      resp = await downloadReq.close();
      expect(resp.statusCode, equals(200));
      final downloadBody =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      final downloadUrl = downloadBody['download_url'] as String;
      expect(downloadUrl, contains(fileId));

      // 8. Resumable download chunk: download first 300 bytes
      final getReq1 = await client.get('127.0.0.1', port, downloadUrl);
      getReq1.headers.set('Authorization', 'Bearer $token');
      getReq1.headers.set('Range', 'bytes=0-299');
      resp = await getReq1.close();
      expect(resp.statusCode, equals(206)); // Partial Content
      expect(resp.headers.value('content-range'), equals('bytes 0-299/1000'));
      final chunkReceived1 = await resp.expand((x) => x).toList();
      expect(chunkReceived1.length, equals(300));
      expect(chunkReceived1, equals(originalBytes.sublist(0, 300)));

      // 9. Download second chunk: download from byte 300 to end
      final getReq2 = await client.get('127.0.0.1', port, downloadUrl);
      getReq2.headers.set('Authorization', 'Bearer $token');
      getReq2.headers.set('Range', 'bytes=300-');
      resp = await getReq2.close();
      expect(resp.statusCode, equals(206)); // Partial Content
      expect(resp.headers.value('content-range'), equals('bytes 300-999/1000'));
      final chunkReceived2 = await resp.expand((x) => x).toList();
      expect(chunkReceived2.length, equals(700));
      expect(chunkReceived2, equals(originalBytes.sublist(300, 1000)));

      // Verify full concat
      final fullRec = [...chunkReceived1, ...chunkReceived2];
      expect(fullRec, equals(originalBytes));

      client.close();
    },
  );

  test('File size limits (10MB) and quota limits (50MB) on backend', () async {
    final client = HttpClient();

    // 1. File size limit check (11MB)
    final uploadReq1 = await client.post(
      '127.0.0.1',
      port,
      '/api/v1/attachments/upload',
    );
    uploadReq1.headers.set('Authorization', 'Bearer $token');
    uploadReq1.headers.set('Content-Type', 'application/json');
    uploadReq1.add(
      utf8.encode(
        jsonEncode({
          'file_size': 11 * 1024 * 1024, // 11MB
          'file_hash': 'too_large_hash',
        }),
      ),
    );
    var resp = await uploadReq1.close();
    expect(resp.statusCode, equals(400));
    var respBody =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    expect(respBody['error'], contains('exceeds the maximum of 10MB'));

    // 2. User storage quota limit check
    // Simulate current storage use of 48MB by inserting directly into database
    server.db.createAttachment(
      fileId: 'mock_48mb_file',
      accountId: 'user1',
      fileSize: 48 * 1024 * 1024,
      fileHash: 'mock_48mb_hash',
    );
    server.db.updateAttachmentProgress(
      'mock_48mb_file',
      48 * 1024 * 1024,
      'COMPLETED',
    );

    // Attempt to upload a 3MB file (total would be 51MB > 50MB quota)
    final uploadReq2 = await client.post(
      '127.0.0.1',
      port,
      '/api/v1/attachments/upload',
    );
    uploadReq2.headers.set('Authorization', 'Bearer $token');
    uploadReq2.headers.set('Content-Type', 'application/json');
    uploadReq2.add(
      utf8.encode(
        jsonEncode({
          'file_size': 3 * 1024 * 1024, // 3MB
          'file_hash': 'exceeds_quota_hash',
        }),
      ),
    );
    resp = await uploadReq2.close();
    expect(resp.statusCode, equals(400));
    respBody =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    expect(
      respBody['error'],
      contains('exceeds the account storage quota of 50MB'),
    );

    client.close();
  });

  test(
    'Reference registration and reference-count automatic file deletion',
    () async {
      final client = HttpClient();

      // 1. Upload a small 100-byte file
      final originalBytes = List.generate(100, (i) => i % 256);
      final fileHash = sha256.convert(originalBytes).toString();
      final fileSize = originalBytes.length;

      final uploadReq = await client.post(
        '127.0.0.1',
        port,
        '/api/v1/attachments/upload',
      );
      uploadReq.headers.set('Authorization', 'Bearer $token');
      uploadReq.headers.set('Content-Type', 'application/json');
      uploadReq.add(
        utf8.encode(jsonEncode({'file_size': fileSize, 'file_hash': fileHash})),
      );
      var resp = await uploadReq.close();
      expect(resp.statusCode, equals(200));

      final putReq = await client.put(
        '127.0.0.1',
        port,
        '/api/v1/attachments/upload/file/$fileHash?offset=0',
      );
      putReq.headers.set('Authorization', 'Bearer $token');
      putReq.add(originalBytes);
      resp = await putReq.close();
      expect(resp.statusCode, equals(200));

      // Verify physical file exists on disk
      final physicalFile = File('${tempStorageDir.path}/$fileHash');
      expect(physicalFile.existsSync(), isTrue);

      // 2. Setup mock message in backend DB
      server.db.createConversation('conv_cleanup', 'DIRECT', 'Cleanup Conv', [
        'user1',
      ]);
      server.db.saveMessage(
        messageId: 'msg_to_delete_99',
        conversationId: 'conv_cleanup',
        senderAccountId: 'user1',
        senderDeviceId: 'device1',
        recipientDeviceId: 'device1',
        ciphertext: 'encrypted_payload',
      );

      // 3. Register attachment reference via HTTP API
      final refReq = await client.post(
        '127.0.0.1',
        port,
        '/api/v1/attachments/register-reference',
      );
      refReq.headers.set('Authorization', 'Bearer $token');
      refReq.headers.set('Content-Type', 'application/json');
      refReq.add(
        utf8.encode(
          jsonEncode({'file_id': fileHash, 'message_id': 'msg_to_delete_99'}),
        ),
      );
      resp = await refReq.close();
      expect(resp.statusCode, equals(200));

      // Verify reference exists in DB
      expect(server.db.getAttachmentReferenceCount(fileHash), equals(1));

      // 4. Delete the message using the /delete endpoint
      final deleteReq = await client.post(
        '127.0.0.1',
        port,
        '/api/v1/messages/delete',
      );
      deleteReq.headers.set('Authorization', 'Bearer $token');
      deleteReq.headers.set('Content-Type', 'application/json');
      deleteReq.add(
        utf8.encode(jsonEncode({'message_id': 'msg_to_delete_99'})),
      );
      resp = await deleteReq.close();
      expect(resp.statusCode, equals(200));

      // 5. Verify reference count is now 0 and physical file + DB row are gone
      expect(server.db.getAttachmentReferenceCount(fileHash), equals(0));
      expect(physicalFile.existsSync(), isFalse);
      expect(server.db.getAttachment(fileHash), isNull);

      client.close();
    },
  );

  test(
    'attachment download is granted to referenced conversation recipients only',
    () async {
      final client = HttpClient();

      final originalBytes = List.generate(128, (i) => (i * 7) % 256);
      final fileHash = sha256.convert(originalBytes).toString();

      final uploadReq = await client.post(
        '127.0.0.1',
        port,
        '/api/v1/attachments/upload',
      );
      uploadReq.headers.set('Authorization', 'Bearer $token');
      uploadReq.headers.set('Content-Type', 'application/json');
      uploadReq.add(
        utf8.encode(
          jsonEncode({
            'file_size': originalBytes.length,
            'file_hash': fileHash,
          }),
        ),
      );
      var resp = await uploadReq.close();
      expect(resp.statusCode, equals(200));
      await resp.drain();

      final putReq = await client.put(
        '127.0.0.1',
        port,
        '/api/v1/attachments/upload/file/$fileHash?offset=0',
      );
      putReq.headers.set('Authorization', 'Bearer $token');
      putReq.add(originalBytes);
      resp = await putReq.close();
      expect(resp.statusCode, equals(200));
      await resp.drain();

      server.db.createConversation('conv_attachment_grant', 'DIRECT', null, [
        'user1',
        'user2',
      ]);
      server.db.saveMessage(
        messageId: 'msg_attachment_grant',
        conversationId: 'conv_attachment_grant',
        senderAccountId: 'user1',
        senderDeviceId: 'device1',
        recipientDeviceId: 'device2',
        ciphertext: 'ciphertext-only attachment message',
      );

      final refReq = await client.post(
        '127.0.0.1',
        port,
        '/api/v1/attachments/register-reference',
      );
      refReq.headers.set('Authorization', 'Bearer $token');
      refReq.headers.set('Content-Type', 'application/json');
      refReq.add(
        utf8.encode(
          jsonEncode({
            'file_id': fileHash,
            'message_id': 'msg_attachment_grant',
          }),
        ),
      );
      resp = await refReq.close();
      expect(resp.statusCode, equals(200));
      await resp.drain();

      final bobDownloadReq = await client.get(
        '127.0.0.1',
        port,
        '/api/v1/attachments/download/$fileHash',
      );
      bobDownloadReq.headers.set('Authorization', 'Bearer $bobToken');
      resp = await bobDownloadReq.close();
      expect(resp.statusCode, equals(200));
      final downloadBody =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      final downloadUrl = downloadBody['download_url'] as String;

      final bobFileReq = await client.get('127.0.0.1', port, downloadUrl);
      bobFileReq.headers.set('Authorization', 'Bearer $bobToken');
      resp = await bobFileReq.close();
      expect(resp.statusCode, equals(200));
      expect(await resp.expand((x) => x).toList(), equals(originalBytes));

      final malloryReq = await client.get(
        '127.0.0.1',
        port,
        '/api/v1/attachments/download/$fileHash',
      );
      malloryReq.headers.set('Authorization', 'Bearer $malloryToken');
      resp = await malloryReq.close();
      expect(resp.statusCode, equals(403));
      await resp.drain();

      client.close();
    },
  );

  test(
    'F2 backup media object storage uploads and downloads ciphertext',
    () async {
      final client = HttpClient();
      final encryptedBytes = utf8.encode('encrypted-backup-media-bytes');
      final objectHash = sha256.convert(encryptedBytes).toString();
      final reserve = await client.post(
        '127.0.0.1',
        port,
        '/api/v1/backups/media',
      );
      reserve.headers.contentType = ContentType.json;
      reserve.headers.set('Authorization', 'Bearer $token');
      reserve.write(
        jsonEncode({
          'object_id': objectHash,
          'byte_size': encryptedBytes.length,
          'sha256': objectHash,
        }),
      );
      var resp = await reserve.close();
      expect(resp.statusCode, equals(200));
      final target =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;

      final upload = await client.put(
        '127.0.0.1',
        port,
        target['upload_url'] as String,
      );
      upload.headers.set('Authorization', 'Bearer $token');
      upload.add(encryptedBytes);
      resp = await upload.close();
      expect(resp.statusCode, equals(200));
      final uploadBody =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      expect(uploadBody['status'], equals('COMPLETED'));

      final download = await client.get(
        '127.0.0.1',
        port,
        target['download_url'] as String,
      );
      download.headers.set('Authorization', 'Bearer $token');
      resp = await download.close();
      expect(resp.statusCode, equals(200));
      expect(await resp.expand((chunk) => chunk).toList(), encryptedBytes);
      client.close();
    },
  );

  // P14-011: Orphan cleanup
  test('cleanupOrphans removes stale incomplete uploads', () {
    final module = AttachmentsModule(server.db, storageDir: tempStorageDir);

    final pastTime = DateTime.now()
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch;

    // Create two orphan attachments (never completed)
    server.db.createAttachment(
      fileId: 'orphan_a',
      accountId: 'user1',
      fileSize: 100,
      fileHash: 'orphan_a',
      createdAt: pastTime,
    );
    server.db.createAttachment(
      fileId: 'orphan_b',
      accountId: 'user1',
      fileSize: 200,
      fileHash: 'orphan_b',
      createdAt: pastTime,
    );
    // Write a physical partial file for orphan_a
    final partialFile = File('${tempStorageDir.path}/orphan_a');
    partialFile.writeAsBytesSync([1, 2, 3]);

    // Also create a completed attachment — should NOT be removed
    server.db.createAttachment(
      fileId: 'completed_c',
      accountId: 'user1',
      fileSize: 50,
      fileHash: 'completed_c',
      createdAt: pastTime,
    );
    server.db.updateAttachmentProgress('completed_c', 50, 'COMPLETED');

    final removed = module.cleanupOrphans(staleAfter: const Duration(hours: 1));

    expect(removed, equals(2));
    expect(server.db.getAttachment('orphan_a'), isNull);
    expect(server.db.getAttachment('orphan_b'), isNull);
    expect(partialFile.existsSync(), isFalse);
    // Completed attachment must survive
    expect(server.db.getAttachment('completed_c'), isNotNull);
  });

  test('cleanupOrphans sanitizes path-traversal file ids', () {
    final module = AttachmentsModule(server.db, storageDir: tempStorageDir);
    final canary = File(
      'canary_dart_test_${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    canary.writeAsStringSync('do not delete me');
    addTearDown(() {
      if (canary.existsSync()) canary.deleteSync();
    });

    final pastTime = DateTime.now()
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch;
    final maliciousFileId = '../${canary.path}';
    server.db.createAttachment(
      fileId: maliciousFileId,
      accountId: 'user1',
      fileSize: 100,
      fileHash: maliciousFileId,
      createdAt: pastTime,
    );

    final removed = module.cleanupOrphans(staleAfter: const Duration(hours: 1));

    // The DB row is still reclaimed, but the traversal must not escape
    // the storage directory to delete the file living outside it.
    expect(removed, equals(1));
    expect(server.db.getAttachment(maliciousFileId), isNull);
    expect(canary.existsSync(), isTrue);
    expect(canary.readAsStringSync(), equals('do not delete me'));
  });

  // P14-012: Object storage lifecycle rules
  test(
    'runLifecycleRules expires unreferenced completed attachments older than retention period',
    () {
      final module = AttachmentsModule(server.db, storageDir: tempStorageDir);

      final oldTime = DateTime.now()
          .subtract(const Duration(days: 31))
          .millisecondsSinceEpoch;

      // Old completed attachment with no references -> should be expired
      server.db.createAttachment(
        fileId: 'old_unreferenced',
        accountId: 'user1',
        fileSize: 100,
        fileHash: 'old_unreferenced',
        createdAt: oldTime,
      );
      server.db.updateAttachmentProgress('old_unreferenced', 100, 'COMPLETED');
      final oldFile = File('${tempStorageDir.path}/old_unreferenced');
      oldFile.writeAsBytesSync([9, 8, 7]);

      // Old completed attachment that IS referenced -> must survive
      server.db.createAttachment(
        fileId: 'old_referenced',
        accountId: 'user1',
        fileSize: 50,
        fileHash: 'old_referenced',
        createdAt: oldTime,
      );
      server.db.updateAttachmentProgress('old_referenced', 50, 'COMPLETED');
      server.db.createConversation('lc_conv', 'DIRECT', 'Test', ['user1']);
      server.db.saveMessage(
        messageId: 'lc_msg1',
        conversationId: 'lc_conv',
        senderAccountId: 'user1',
        senderDeviceId: 'device1',
        recipientDeviceId: 'device1',
        ciphertext: 'x',
      );
      server.db.registerAttachmentReference('old_referenced', 'lc_msg1');

      // Recent completed attachment -> must survive even without references
      final recentTime = DateTime.now()
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;
      server.db.createAttachment(
        fileId: 'new_unreferenced',
        accountId: 'user1',
        fileSize: 75,
        fileHash: 'new_unreferenced',
        createdAt: recentTime,
      );
      server.db.updateAttachmentProgress('new_unreferenced', 75, 'COMPLETED');

      final expired = module.runLifecycleRules(
        retainFor: const Duration(days: 30),
      );

      expect(expired, equals(1));
      expect(server.db.getAttachment('old_unreferenced'), isNull);
      expect(oldFile.existsSync(), isFalse);
      expect(server.db.getAttachment('old_referenced'), isNotNull);
      expect(server.db.getAttachment('new_unreferenced'), isNotNull);
    },
  );

  // P14-016: Corruption test — hash mismatch triggers FAILED status
  test('upload with hash mismatch is rejected and marked FAILED', () async {
    final client = HttpClient();

    final originalBytes = List.generate(200, (i) => i % 256);
    final realHash = sha256.convert(originalBytes).toString();

    // Register with the correct hash
    final uploadReq = await client.post(
      '127.0.0.1',
      port,
      '/api/v1/attachments/upload',
    );
    uploadReq.headers.set('Authorization', 'Bearer $token');
    uploadReq.headers.set('Content-Type', 'application/json');
    uploadReq.add(
      utf8.encode(
        jsonEncode({'file_size': originalBytes.length, 'file_hash': realHash}),
      ),
    );
    var resp = await uploadReq.close();
    expect(resp.statusCode, equals(200));
    await resp.drain();

    // Upload corrupted bytes (all zeros instead of real content)
    final corruptBytes = List.filled(200, 0);
    final putReq = await client.put(
      '127.0.0.1',
      port,
      '/api/v1/attachments/upload/file/$realHash?offset=0',
    );
    putReq.headers.set('Authorization', 'Bearer $token');
    putReq.add(corruptBytes);
    resp = await putReq.close();
    expect(resp.statusCode, equals(400));
    final body =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    expect(body['error'], contains('hash mismatch'));

    final attachment = server.db.getAttachment(realHash);
    expect(attachment!['status'], equals('FAILED'));

    client.close();
  });

  // P14-016: Interrupted upload resume — second session picks up from offset
  test('interrupted upload resumes correctly from server offset', () async {
    final client = HttpClient();

    final bytes = List.generate(600, (i) => (i * 3) % 256);
    final fileHash = sha256.convert(bytes).toString();

    final uploadReq = await client.post(
      '127.0.0.1',
      port,
      '/api/v1/attachments/upload',
    );
    uploadReq.headers.set('Authorization', 'Bearer $token');
    uploadReq.headers.set('Content-Type', 'application/json');
    uploadReq.add(
      utf8.encode(
        jsonEncode({'file_size': bytes.length, 'file_hash': fileHash}),
      ),
    );
    var resp = await uploadReq.close();
    expect(resp.statusCode, equals(200));
    await resp.drain();

    // Upload first 300 bytes
    final put1 = await client.put(
      '127.0.0.1',
      port,
      '/api/v1/attachments/upload/file/$fileHash?offset=0',
    );
    put1.headers.set('Authorization', 'Bearer $token');
    put1.add(bytes.sublist(0, 300));
    resp = await put1.close();
    expect(resp.statusCode, equals(200));
    final b1 =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    expect(b1['status'], equals('UPLOADING'));

    // "Network drops" — resume from offset 300 in a new session
    final statusReq = await client.get(
      '127.0.0.1',
      port,
      '/api/v1/attachments/upload/status/$fileHash',
    );
    statusReq.headers.set('Authorization', 'Bearer $token');
    resp = await statusReq.close();
    final statusBody =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    final resumeOffset = statusBody['uploaded_bytes'] as int;
    expect(resumeOffset, equals(300));

    // Upload remaining bytes from the resume offset
    final put2 = await client.put(
      '127.0.0.1',
      port,
      '/api/v1/attachments/upload/file/$fileHash?offset=$resumeOffset',
    );
    put2.headers.set('Authorization', 'Bearer $token');
    put2.add(bytes.sublist(resumeOffset));
    resp = await put2.close();
    expect(resp.statusCode, equals(200));
    final b2 =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    expect(b2['status'], equals('COMPLETED'));
    expect(b2['uploaded_bytes'], equals(600));

    client.close();
  });
}
