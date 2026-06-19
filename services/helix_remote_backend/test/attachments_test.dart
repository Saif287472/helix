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
    );

    // Register a mock user and device in the backend DB to perform auth
    final db = server.db;
    db.createAccount('user1', 'alice', 'alice_identity_public_key');
    db.registerDevice('device1', 'user1', 'device_public_key', 'Alice Device');

    // Generate JWT token for user1/device1
    token = server.jwt.generateToken({
      'account_id': 'user1',
      'device_id': 'device1',
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
}
