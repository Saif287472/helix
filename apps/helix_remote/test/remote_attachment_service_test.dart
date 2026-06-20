import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
import 'package:helix_remote/app/attachment_safety.dart';
import 'package:helix_remote/app/attachment_export.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      String? foundPath;
      for (var i = 0; i < 5; i++) {
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

  late BackendServer server;
  late int port;
  late String token;
  late HelixRemoteDatabase db;
  final tempStorageDir = Directory('test_remote_attachments_storage');
  final clientTempDir = Directory('test_client_temp');

  late Uint8List wrappingKey;

  Uint8List generateWrappingKey() {
    final rand = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rand.nextInt(256)));
  }

  setUp(() async {
    wrappingKey = generateWrappingKey();

    if (tempStorageDir.existsSync()) {
      tempStorageDir.deleteSync(recursive: true);
    }
    tempStorageDir.createSync(recursive: true);

    if (clientTempDir.existsSync()) {
      clientTempDir.deleteSync(recursive: true);
    }
    clientTempDir.createSync(recursive: true);

    // Initialize backend server
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_remote_attachments_service_testing',
      rateLimitMaxTokens: 100.0,
      rateLimitRefillRate: 10.0,
      attachmentsStorageDir: tempStorageDir,
    );

    final backendDb = server.db;
    backendDb.createAccount('user1', 'alice', 'alice_identity_public_key');
    backendDb.registerDevice(
      'device1',
      'user1',
      'device_public_key',
      'Alice Device',
    );

    token = server.jwt.generateToken({
      'account_id': 'user1',
      'device_id': 'device1',
    }, const Duration(hours: 1));

    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;

    // Initialize client database
    db = HelixRemoteDatabase(File(':memory:'));
    db.initialize();
  });

  tearDown(() async {
    db.close();
    await server.stop();
    if (tempStorageDir.existsSync()) {
      tempStorageDir.deleteSync(recursive: true);
    }
    if (clientTempDir.existsSync()) {
      clientTempDir.deleteSync(recursive: true);
    }
  });

  test(
    'RemoteAttachmentService client-side upload/download roundtrip with resumable verification',
    () async {
      final service = RemoteAttachmentService(
        baseUrl: 'http://127.0.0.1:$port',
        authToken: token,
        db: db,
        tempDir: clientTempDir,
        wrappingKey: wrappingKey,
      );

      // 1. Create a dummy plaintext file (1000 bytes)
      final plaintextBytes = List.generate(1000, (i) => i % 256);
      final plaintextFile = File(p.join(clientTempDir.path, 'dummy.txt'));
      await plaintextFile.writeAsBytes(plaintextBytes);

      // 2. Prepare attachment (generates keys, encrypts, writes to temp cipher file)
      final prepResult = await service.prepareAttachment(plaintextFile);
      final attachmentId = prepResult['attachment_id'] as String;
      final cipherPath = prepResult['ciphertext_path'] as String;

      expect(attachmentId, isNotEmpty);
      expect(File(cipherPath).existsSync(), isTrue);

      // Verify metadata stored locally
      final localAttachment = db.getAttachment(attachmentId);
      expect(localAttachment, isNotNull);
      expect(localAttachment!['status'], equals('PENDING'));
      expect(
        localAttachment['imported_source_path'],
        equals(plaintextFile.path),
      );
      expect(localAttachment['local_path'], isNull);
      expect(localAttachment['encrypted_cache_path'], equals(cipherPath));
      expect(
        localAttachment['size_bytes'],
        equals(File(cipherPath).lengthSync()),
      );

      // 3. Resumable upload (simulate partial upload first)
      // We'll manually insert 300 bytes into the server's directory to simulate an interrupted upload
      final serverFile = File('${tempStorageDir.path}/$attachmentId');
      if (!serverFile.parent.existsSync()) {
        serverFile.parent.createSync(recursive: true);
      }
      // Read the first 300 bytes of the encrypted ciphertext
      final fullCiphertext = File(
        prepResult['ciphertext_path'] as String,
      ).readAsBytesSync();
      await serverFile.writeAsBytes(fullCiphertext.sublist(0, 300));

      // Register attachment metadata on backend database as PENDING with 300 bytes
      server.db.createAttachment(
        fileId: attachmentId,
        accountId: 'user1',
        fileSize: fullCiphertext.length,
        fileHash: attachmentId,
      );
      server.db.updateAttachmentProgress(attachmentId, 300, 'UPLOADING');

      // Run upload from client side, which should start from 300 offset
      final progressList = <double>[];
      await service.uploadAttachment(
        attachmentId: attachmentId,
        ciphertextPath: cipherPath,
        onProgress: (p) => progressList.add(p),
      );

      // The upload must complete successfully, and progress list must contain progress updates
      expect(progressList, isNotEmpty);
      expect(progressList.last, equals(1.0));

      final localAttachmentAfterUpload = db.getAttachment(attachmentId);
      expect(localAttachmentAfterUpload!['status'], equals('COMPLETED'));

      // Check backend status is COMPLETED
      final backendAttachment = server.db.getAttachment(attachmentId);
      expect(backendAttachment!['status'], equals('COMPLETED'));
      expect(
        backendAttachment['uploaded_bytes'],
        equals(fullCiphertext.length),
      );

      // 4. Resumable download (simulate partial download first)
      final downloadDestPath = p.join(clientTempDir.path, 'downloaded.enc');
      final downloadDestFile = File(downloadDestPath);
      // Write first 400 bytes of ciphertext to destination
      await downloadDestFile.writeAsBytes(fullCiphertext.sublist(0, 400));

      // Perform download using RemoteAttachmentService, which will see 400 bytes exist
      // and make a Range request for bytes 400-
      final decryptedFile = await service.downloadAttachment(
        attachmentId: attachmentId,
        savePath: downloadDestPath,
      );

      expect(decryptedFile.existsSync(), isTrue);
      final decryptedBytes = decryptedFile.readAsBytesSync();
      expect(decryptedBytes, equals(plaintextBytes));

      // Check client DB status updated to DOWNLOADED
      final localAttachmentAfterDownload = db.getAttachment(attachmentId);
      expect(localAttachmentAfterDownload!['status'], equals('DOWNLOADED'));
      expect(
        localAttachmentAfterDownload['local_path'],
        equals(decryptedFile.path),
      );
    },
  );

  test('Client-side size limit validation throws ArgumentError', () async {
    final service = RemoteAttachmentService(
      baseUrl: 'http://127.0.0.1:$port',
      authToken: token,
      db: db,
      tempDir: clientTempDir,
      wrappingKey: wrappingKey,
    );

    // Create a mock File that claims to be 11MB
    final largeFile = File(p.join(clientTempDir.path, 'large.txt'));
    await largeFile.writeAsBytes(Uint8List(10)); // just small actual write
    // To mock the lengthSync without writing 11MB, we will write a file and mock length check if needed.
    // Wait! lengthSync reads length from filesystem, so we must write a large file or use custom mocking.
    // Since writing 11MB on local disk takes less than 10 milliseconds, we can write it!
    final largeBytes = Uint8List(11 * 1024 * 1024);
    await largeFile.writeAsBytes(largeBytes);

    expect(() => service.prepareAttachment(largeFile), throwsArgumentError);
  });

  test(
    'Encrypted thumbnail preparation, database storage, and manifest serialization',
    () async {
      final service = RemoteAttachmentService(
        baseUrl: 'http://127.0.0.1:$port',
        authToken: token,
        db: db,
        tempDir: clientTempDir,
        wrappingKey: wrappingKey,
      );

      // 1. Setup plaintext primary and thumbnail files
      final mainFile = File(p.join(clientTempDir.path, 'photo.jpg'));
      await mainFile.writeAsBytes(List.generate(500, (i) => i % 256));

      final thumbFile = File(p.join(clientTempDir.path, 'photo_thumb.jpg'));
      await thumbFile.writeAsBytes(List.generate(50, (i) => (i * 2) % 256));

      // 2. Prepare attachment with thumbnail
      final prepResult = await service.prepareAttachment(
        mainFile,
        thumbnailFile: thumbFile,
      );
      final mainId = prepResult['attachment_id'] as String;
      final thumbData = prepResult['thumbnail'] as Map<String, dynamic>;
      final thumbId = thumbData['attachment_id'] as String;

      expect(mainId, isNotEmpty);
      expect(thumbId, isNotEmpty);
      expect(mainId, isNot(equals(thumbId)));

      // Verify both are stored in client DB
      final mainLocal = db.getAttachment(mainId);
      final thumbLocal = db.getAttachment(thumbId);
      expect(mainLocal, isNotNull);
      expect(thumbLocal, isNotNull);
      expect(mainLocal!['status'], equals('PENDING'));
      expect(thumbLocal!['status'], equals('PENDING'));
      expect(mainLocal['filename'], equals('photo.jpg'));
      expect(thumbLocal['filename'], equals('photo.jpg.thumb'));

      // 3. Serialize and deserialize RemoteAttachmentManifest with thumbnail metadata
      final manifest = RemoteAttachmentManifest(
        fileId: mainId,
        fileSize: prepResult['size_bytes'] as int,
        fileHash: prepResult['file_hash'] as String,
        mimeType: 'image/jpeg',
        thumbnailFileId: thumbId,
        thumbnailFileSize: thumbData['size_bytes'] as int,
        thumbnailFileHash: thumbData['file_hash'] as String,
      );

      final json = manifest.toJson();
      expect(json['thumbnail_file_id'], equals(thumbId));
      expect(json['thumbnail_file_size'], equals(thumbData['size_bytes']));

      final parsed = RemoteAttachmentManifest.fromJson(json);
      expect(parsed.thumbnailFileId, equals(thumbId));
      expect(parsed.thumbnailFileSize, equals(thumbData['size_bytes']));
      expect(parsed.thumbnailFileHash, equals(thumbData['file_hash']));
    },
  );

  test(
    'Malware warning UX string verification without server scanning claims',
    () {
      // 1. Get the warning message
      final warning = RemoteAttachmentSafety.malwareWarningMessage;

      // 2. Verify warning properties
      expect(warning, contains('end-to-end encrypted'));
      expect(warning, contains('cannot scan'));
      expect(warning, contains('malware'));
      expect(warning, isNot(contains('server does scan')));
      expect(warning, isNot(contains('server performs scan')));

      // 3. Check helper method
      expect(RemoteAttachmentSafety.verifyWarningMessage(warning), isTrue);
      expect(
        RemoteAttachmentSafety.verifyWarningMessage('Some other warning'),
        isFalse,
      );
    },
  );

  // P14-013: Cache eviction without deleting server history
  test(
    'evictLocalCache removes local plaintext file and updates status',
    () async {
      final service = RemoteAttachmentService(
        baseUrl: 'http://127.0.0.1:$port',
        authToken: token,
        db: db,
        tempDir: clientTempDir,
        wrappingKey: wrappingKey,
      );

      // 1. Prepare and upload a file
      final plaintextBytes = List.generate(200, (i) => i % 256);
      final plaintextFile = File(p.join(clientTempDir.path, 'evict_test.txt'));
      await plaintextFile.writeAsBytes(plaintextBytes);

      final prepResult = await service.prepareAttachment(plaintextFile);
      final attachmentId = prepResult['attachment_id'] as String;
      final cipherPath = prepResult['ciphertext_path'] as String;

      // Register on backend and upload
      server.db.createAttachment(
        fileId: attachmentId,
        accountId: 'user1',
        fileSize: File(cipherPath).lengthSync(),
        fileHash: attachmentId,
      );
      await service.uploadAttachment(
        attachmentId: attachmentId,
        ciphertextPath: cipherPath,
      );

      // 2. Download to get a local plaintext cache file
      final downloadPath = p.join(clientTempDir.path, 'evict_download.enc');
      final decryptedFile = await service.downloadAttachment(
        attachmentId: attachmentId,
        savePath: downloadPath,
      );
      expect(decryptedFile.existsSync(), isTrue);
      expect(db.getAttachment(attachmentId)!['status'], equals('DOWNLOADED'));

      // 3. Evict the local cache
      service.evictLocalCache(attachmentId);

      expect(decryptedFile.existsSync(), isFalse);
      expect(plaintextFile.existsSync(), isTrue);
      expect(File(cipherPath).existsSync(), isFalse);
      final afterEvict = db.getAttachment(attachmentId);
      expect(afterEvict!['status'], equals('CACHE_EVICTED'));
      expect(afterEvict['local_path'], isNull);
      expect(afterEvict['imported_source_path'], equals(plaintextFile.path));
      expect(afterEvict['encrypted_cache_path'], isNull);
      expect(afterEvict['downloaded_ciphertext_path'], isNull);

      // Server copy is unaffected
      expect(server.db.getAttachment(attachmentId), isNotNull);
      expect(
        server.db.getAttachment(attachmentId)!['status'],
        equals('COMPLETED'),
      );
    },
  );

  // P14-014: External export warning
  test('export warning message is accurate and verifiable', () {
    final warning = RemoteAttachmentExport.exportWarningMessage;

    expect(warning, contains('end-to-end encryption'));
    expect(warning, contains('decrypted'));
    expect(warning, isNot(contains('Helix cannot see')));
    expect(RemoteAttachmentExport.verifyExportWarning(warning), isTrue);
    expect(
      RemoteAttachmentExport.verifyExportWarning('Other message'),
      isFalse,
    );
  });

  // P14-015: Multi-device attachment key delivery
  test('buildKeyDeliveryPackage produces per-device key slots', () {
    final service = RemoteAttachmentService(
      baseUrl: 'http://127.0.0.1:$port',
      authToken: token,
      db: db,
      tempDir: clientTempDir,
      wrappingKey: wrappingKey,
    );

    const attachmentId = 'test_attachment_id';
    const rawKey = 'base64encodedattachmentkey==';
    final deviceIds = ['device_A', 'device_B', 'device_C'];

    // Per-device encryption — raw-key fallback is no longer allowed (P14-015)
    final package = service.buildKeyDeliveryPackage(
      attachmentId: attachmentId,
      attachmentKey: rawKey,
      deviceIds: deviceIds,
      encryptForDevice: (did, key) => '$did:$key',
    );

    expect(package.attachmentId, equals(attachmentId));
    expect(package.deviceKeys.keys, containsAll(deviceIds));
    expect(package.deviceKeys['device_A'], equals('device_A:$rawKey'));
    expect(package.deviceKeys['device_B'], equals('device_B:$rawKey'));

    // Round-trip serialization
    final json = package.toJson();
    final parsed = AttachmentKeyPackage.fromJson(json);
    expect(parsed.attachmentId, equals(attachmentId));
    expect(parsed.deviceKeys, equals(package.deviceKeys));
  });

  // P14-016: evictLocalCache is a no-op for unknown attachment
  test('evictLocalCache is safe when attachment is not in local DB', () {
    final service = RemoteAttachmentService(
      baseUrl: 'http://127.0.0.1:$port',
      authToken: token,
      db: db,
      tempDir: clientTempDir,
      wrappingKey: wrappingKey,
    );
    // Should not throw
    expect(() => service.evictLocalCache('nonexistent_id'), returnsNormally);
  });

  test(
    'download detects ciphertext tampering before plaintext cache write',
    () async {
      final service = RemoteAttachmentService(
        baseUrl: 'http://127.0.0.1:$port',
        authToken: token,
        db: db,
        tempDir: clientTempDir,
        wrappingKey: wrappingKey,
      );

      final plaintextFile = File(p.join(clientTempDir.path, 'tamper.txt'));
      await plaintextFile.writeAsBytes(List.generate(300, (i) => i % 251));

      final prepResult = await service.prepareAttachment(plaintextFile);
      final attachmentId = prepResult['attachment_id'] as String;
      final cipherPath = prepResult['ciphertext_path'] as String;
      final fullCiphertext = File(cipherPath).readAsBytesSync();

      server.db.createAttachment(
        fileId: attachmentId,
        accountId: 'user1',
        fileSize: fullCiphertext.length,
        fileHash: attachmentId,
      );
      await service.uploadAttachment(
        attachmentId: attachmentId,
        ciphertextPath: cipherPath,
      );

      final serverFile = File('${tempStorageDir.path}/$attachmentId');
      final tampered = serverFile.readAsBytesSync();
      tampered[tampered.length - 1] ^= 0x01;
      await serverFile.writeAsBytes(tampered);

      final downloadPath = p.join(clientTempDir.path, 'tampered.enc');
      expect(
        () => service.downloadAttachment(
          attachmentId: attachmentId,
          savePath: downloadPath,
        ),
        throwsStateError,
      );
      expect(
        File(downloadPath.replaceFirst(RegExp(r'\.enc$'), '')).existsSync(),
        isFalse,
      );
    },
  );
}
