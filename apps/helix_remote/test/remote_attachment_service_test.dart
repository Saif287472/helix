import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote/app/remote_attachment_service.dart';
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

  setUp(() async {
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
        localAttachment['size_bytes'],
        equals(File(cipherPath).lengthSync()),
      );

      // 3. Resumable upload (simulate partial upload first)
      // We'll manually insert 300 bytes into the server's directory to simulate an interrupted upload
      final serverFile = File('attachments_storage/$attachmentId');
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
}
