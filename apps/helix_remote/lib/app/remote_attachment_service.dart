import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:helix_remote_crypto/helix_remote_crypto.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:cryptography/cryptography.dart' as crypto_pkg;

class RemoteAttachmentService {
  RemoteAttachmentService({
    required this.baseUrl,
    required this.authToken,
    required this.db,
    required this.tempDir,
    RemoteAttachmentCrypto? crypto,
    HttpClient? httpClient,
  }) : _crypto = crypto ?? RemoteAttachmentCrypto(),
       _httpClient = httpClient ?? HttpClient();

  final String baseUrl;
  final String authToken;
  final HelixRemoteDatabase db;
  final Directory tempDir;
  final RemoteAttachmentCrypto _crypto;
  final HttpClient _httpClient;

  /// Prepares a file for upload: generates random key/IV, encrypts the file
  /// to a temporary ciphertext file, saves metadata locally.
  /// Returns the attachment metadata mapping.
  Future<Map<String, dynamic>> prepareAttachment(
    File plaintextFile, {
    File? thumbnailFile,
  }) async {
    final originalLength = plaintextFile.lengthSync();
    if (originalLength > 10 * 1024 * 1024) {
      throw ArgumentError('File size exceeds the 10MB limit');
    }

    final keys = _crypto.generateAttachmentKeys();
    final keyBytes = keys['key']!;
    final ivBytes = keys['iv']!;

    final plaintext = await plaintextFile.readAsBytes();
    final ciphertext = await _crypto.encryptFile(plaintext, keyBytes, ivBytes);

    // Write ciphertext to a temp file
    final filename = p.basename(plaintextFile.path);
    final tempCipherFile = File(p.join(tempDir.path, '$filename.enc'));
    if (!tempCipherFile.parent.existsSync()) {
      tempCipherFile.parent.createSync(recursive: true);
    }
    await tempCipherFile.writeAsBytes(ciphertext);

    // Compute ciphertext hash
    final sha256Hash = await _computeSha256(ciphertext);

    // Save locally to database
    final encKeyStr = base64UrlEncode(keyBytes);
    final encIvStr = base64UrlEncode(ivBytes);
    final keyWithIv = '$encKeyStr:$encIvStr';

    db.saveAttachment(
      attachmentId: sha256Hash,
      filename: filename,
      sizeBytes: ciphertext.length,
      encryptedKey: keyWithIv,
      localPath: plaintextFile.path,
      status: 'PENDING',
    );

    final result = <String, dynamic>{
      'attachment_id': sha256Hash,
      'filename': filename,
      'size_bytes': ciphertext.length,
      'file_hash': sha256Hash,
      'encrypted_key': keyWithIv,
      'ciphertext_path': tempCipherFile.path,
    };

    if (thumbnailFile != null) {
      if (thumbnailFile.lengthSync() > 1024 * 1024) {
        throw ArgumentError('Thumbnail file size exceeds the 1MB limit');
      }

      final thumbKeys = _crypto.generateAttachmentKeys();
      final thumbKeyBytes = thumbKeys['key']!;
      final thumbIvBytes = thumbKeys['iv']!;

      final thumbPlaintext = await thumbnailFile.readAsBytes();
      final thumbCiphertext = await _crypto.encryptFile(
        thumbPlaintext,
        thumbKeyBytes,
        thumbIvBytes,
      );

      final thumbFilename = '$filename.thumb';
      final tempThumbCipherFile = File(
        p.join(tempDir.path, '$thumbFilename.enc'),
      );
      await tempThumbCipherFile.writeAsBytes(thumbCiphertext);

      final thumbSha256Hash = await _computeSha256(thumbCiphertext);

      final thumbEncKeyStr = base64UrlEncode(thumbKeyBytes);
      final thumbEncIvStr = base64UrlEncode(thumbIvBytes);
      final thumbKeyWithIv = '$thumbEncKeyStr:$thumbEncIvStr';

      db.saveAttachment(
        attachmentId: thumbSha256Hash,
        filename: thumbFilename,
        sizeBytes: thumbCiphertext.length,
        encryptedKey: thumbKeyWithIv,
        localPath: thumbnailFile.path,
        status: 'PENDING',
      );

      result['thumbnail'] = {
        'attachment_id': thumbSha256Hash,
        'filename': thumbFilename,
        'size_bytes': thumbCiphertext.length,
        'file_hash': thumbSha256Hash,
        'encrypted_key': thumbKeyWithIv,
        'ciphertext_path': tempThumbCipherFile.path,
      };
    }

    return result;
  }

  /// Performs a resumable upload to the server.
  Future<void> uploadAttachment({
    required String attachmentId,
    required String ciphertextPath,
    void Function(double progress)? onProgress,
  }) async {
    final cipherFile = File(ciphertextPath);
    if (!cipherFile.existsSync()) {
      throw StateError('Ciphertext file not found at $ciphertextPath');
    }

    final totalSize = cipherFile.lengthSync();

    // 1. Request upload session
    final requestUrl = Uri.parse('$baseUrl/api/v1/attachments/upload');
    final req = await _httpClient.postUrl(requestUrl);
    req.headers.set('Authorization', 'Bearer $authToken');
    req.headers.set('Content-Type', 'application/json');
    req.add(
      utf8.encode(
        jsonEncode({'file_size': totalSize, 'file_hash': attachmentId}),
      ),
    );
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw StateError('Upload request failed with status ${resp.statusCode}');
    }
    final respBody =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    final uploadPath = respBody['upload_url'] as String;
    final uploadUrl = Uri.parse('$baseUrl$uploadPath');

    // 2. Query upload status to get current offset
    final statusUrl = Uri.parse(
      '$baseUrl/api/v1/attachments/upload/status/$attachmentId',
    );
    final statusReq = await _httpClient.getUrl(statusUrl);
    statusReq.headers.set('Authorization', 'Bearer $authToken');
    final statusResp = await statusReq.close();
    if (statusResp.statusCode != 200) {
      throw StateError('Failed to query upload status');
    }
    final statusBody =
        jsonDecode(await statusResp.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    int offset = statusBody['uploaded_bytes'] as int;

    // 3. Upload loop
    while (offset < totalSize) {
      final uploadChunkUrl = uploadUrl.replace(
        queryParameters: {'offset': offset.toString()},
      );
      final uploadReq = await _httpClient.putUrl(uploadChunkUrl);
      uploadReq.headers.set('Authorization', 'Bearer $authToken');
      uploadReq.headers.set('Content-Type', 'application/octet-stream');

      // Slice the file from offset
      final stream = cipherFile.openRead(offset);
      await uploadReq.addStream(stream);

      final uploadResp = await uploadReq.close();
      if (uploadResp.statusCode != 200) {
        throw StateError(
          'Chunk upload failed with status ${uploadResp.statusCode}',
        );
      }

      final uploadBody =
          jsonDecode(await uploadResp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      offset = uploadBody['uploaded_bytes'] as int;
      final status = uploadBody['status'] as String;

      if (onProgress != null) {
        onProgress(offset / totalSize);
      }

      if (status == 'COMPLETED') {
        break;
      }
    }

    // Update local status
    final localAttachment = db.getAttachment(attachmentId);
    if (localAttachment != null) {
      db.saveAttachment(
        attachmentId: attachmentId,
        filename: localAttachment['filename'] as String,
        sizeBytes: localAttachment['size_bytes'] as int,
        encryptedKey: localAttachment['encrypted_key'] as String,
        localPath: localAttachment['local_path'] as String?,
        status: 'COMPLETED',
      );
    }
  }

  /// Downloads an attachment with support for resuming.
  Future<File> downloadAttachment({
    required String attachmentId,
    required String savePath,
    void Function(double progress)? onProgress,
  }) async {
    // 1. Request download URL
    final requestUrl = Uri.parse(
      '$baseUrl/api/v1/attachments/download/$attachmentId',
    );
    final req = await _httpClient.getUrl(requestUrl);
    req.headers.set('Authorization', 'Bearer $authToken');
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw StateError(
        'Download request failed with status ${resp.statusCode}',
      );
    }
    final respBody =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    final downloadPath = respBody['download_url'] as String;
    final downloadUrl = Uri.parse('$baseUrl$downloadPath');

    // 2. Setup local download file
    final destFile = File(savePath);
    int offset = 0;
    if (destFile.existsSync()) {
      offset = destFile.lengthSync();
    } else {
      destFile.createSync(recursive: true);
    }

    // 3. Initiate download request with Range header if offset > 0
    final downloadReq = await _httpClient.getUrl(downloadUrl);
    downloadReq.headers.set('Authorization', 'Bearer $authToken');
    if (offset > 0) {
      downloadReq.headers.set('Range', 'bytes=$offset-');
    }

    final downloadResp = await downloadReq.close();
    if (downloadResp.statusCode != 200 && downloadResp.statusCode != 206) {
      throw StateError(
        'Download file request failed with status ${downloadResp.statusCode}',
      );
    }

    final totalLengthHeader = downloadResp.headers.value('content-length');
    int totalLength = totalLengthHeader != null
        ? int.tryParse(totalLengthHeader) ?? 0
        : 0;
    if (downloadResp.statusCode == 206) {
      // Content-Range: bytes start-end/total
      final contentRange = downloadResp.headers.value('content-range');
      if (contentRange != null) {
        final parts = contentRange.split('/');
        if (parts.length > 1) {
          totalLength = int.tryParse(parts[1]) ?? totalLength;
        }
      }
    }

    final sink = destFile.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    int downloadedBytes = offset;

    await for (final chunk in downloadResp) {
      sink.add(chunk);
      downloadedBytes += chunk.length;
      if (onProgress != null && totalLength > 0) {
        onProgress(downloadedBytes / totalLength);
      }
    }
    await sink.close();

    // 4. Decrypt and verify integrity
    final localAttachment = db.getAttachment(attachmentId);
    if (localAttachment == null) {
      throw StateError('Attachment metadata not found locally');
    }

    final keyWithIv = localAttachment['encrypted_key'] as String;
    final parts = keyWithIv.split(':');
    final keyBytes = base64Url.decode(parts[0]);
    final ivBytes = base64Url.decode(parts[1]);

    final ciphertext = await destFile.readAsBytes();
    final actualHash = await _computeSha256(ciphertext);
    if (actualHash != attachmentId) {
      throw StateError('Downloaded file hash mismatch');
    }

    final plaintext = await _crypto.decryptFile(ciphertext, keyBytes, ivBytes);

    // Overwrite the file with plaintext or save to desired path
    final plaintextFile = File(
      savePath.endsWith('.enc')
          ? savePath.substring(0, savePath.length - 4)
          : '$savePath.dec',
    );
    await plaintextFile.writeAsBytes(plaintext);

    // Update database status
    db.saveAttachment(
      attachmentId: attachmentId,
      filename: localAttachment['filename'] as String,
      sizeBytes: localAttachment['size_bytes'] as int,
      encryptedKey: localAttachment['encrypted_key'] as String,
      localPath: plaintextFile.path,
      status: 'DOWNLOADED',
    );

    return plaintextFile;
  }

  /// Removes the locally cached plaintext file for [attachmentId] without
  /// touching the server copy. Status is set to CACHE_EVICTED so a future
  /// download can recover the file.
  void evictLocalCache(String attachmentId) {
    final localAttachment = db.getAttachment(attachmentId);
    if (localAttachment == null) return;

    final localPath = localAttachment['local_path'] as String?;
    if (localPath != null) {
      final localFile = File(localPath);
      if (localFile.existsSync()) {
        localFile.deleteSync();
      }
    }

    db.saveAttachment(
      attachmentId: attachmentId,
      filename: localAttachment['filename'] as String,
      sizeBytes: localAttachment['size_bytes'] as int,
      encryptedKey: localAttachment['encrypted_key'] as String,
      localPath: null,
      status: 'CACHE_EVICTED',
    );
  }

  /// Packages the plaintext [attachmentKey] into per-device slots for
  /// multi-device key delivery. [encryptForDevice] should encrypt the key to
  /// each device's public key; when omitted the raw key is used (test-only).
  AttachmentKeyPackage buildKeyDeliveryPackage({
    required String attachmentId,
    required String attachmentKey,
    required List<String> deviceIds,
    String Function(String deviceId, String key)? encryptForDevice,
  }) {
    final deviceKeys = <String, String>{};
    for (final deviceId in deviceIds) {
      deviceKeys[deviceId] = encryptForDevice != null
          ? encryptForDevice(deviceId, attachmentKey)
          : attachmentKey;
    }
    return AttachmentKeyPackage(
      attachmentId: attachmentId,
      deviceKeys: deviceKeys,
    );
  }

  Future<String> _computeSha256(Uint8List data) async {
    final hash = await crypto_pkg.Sha256().hash(data);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> registerReference({
    required String fileId,
    required String messageId,
  }) async {
    final requestUrl = Uri.parse(
      '$baseUrl/api/v1/attachments/register-reference',
    );
    final req = await _httpClient.postUrl(requestUrl);
    req.headers.set('Authorization', 'Bearer $authToken');
    req.headers.set('Content-Type', 'application/json');
    req.add(
      utf8.encode(jsonEncode({'file_id': fileId, 'message_id': messageId})),
    );
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw StateError(
        'Failed to register reference with status ${resp.statusCode}',
      );
    }
  }
}
