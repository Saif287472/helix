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
    required this.wrappingKey,
    RemoteAttachmentCrypto? crypto,
    HttpClient? httpClient,
  }) : _crypto = crypto ?? RemoteAttachmentCrypto(),
       _httpClient = httpClient ?? HttpClient();

  final String baseUrl;
  String authToken;
  final HelixRemoteDatabase db;
  final Directory tempDir;
  final Uint8List wrappingKey;
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

    // Compute ciphertext hash
    final sha256Hash = await _computeSha256(ciphertext);

    // Write ciphertext to a temp file named with attachment id
    final tempCipherFile = File(p.join(tempDir.path, '$sha256Hash.enc'));
    if (!tempCipherFile.parent.existsSync()) {
      tempCipherFile.parent.createSync(recursive: true);
    }
    await tempCipherFile.writeAsBytes(ciphertext);

    // Wrap key material before storing in DB
    final wrappedKey = await _crypto.wrapAttachmentKey(
      keyBytes,
      ivBytes,
      wrappingKey,
    );
    final wrappedKeyStr = base64Url.encode(wrappedKey);

    db.saveAttachment(
      attachmentId: sha256Hash,
      filename: p.basename(plaintextFile.path),
      sizeBytes: ciphertext.length,
      encryptedKey: wrappedKeyStr,
      localPath: plaintextFile.path,
      status: 'PENDING',
    );

    final result = <String, dynamic>{
      'attachment_id': sha256Hash,
      'filename': p.basename(plaintextFile.path),
      'size_bytes': ciphertext.length,
      'file_hash': sha256Hash,
      'encrypted_key': wrappedKeyStr,
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

      final thumbSha256Hash = await _computeSha256(thumbCiphertext);

      final tempThumbCipherFile = File(
        p.join(tempDir.path, '$thumbSha256Hash.enc'),
      );
      await tempThumbCipherFile.writeAsBytes(thumbCiphertext);

      final thumbWrapped = await _crypto.wrapAttachmentKey(
        thumbKeyBytes,
        thumbIvBytes,
        wrappingKey,
      );
      final thumbWrappedStr = base64Url.encode(thumbWrapped);

      db.saveAttachment(
        attachmentId: thumbSha256Hash,
        filename: '${p.basename(plaintextFile.path)}.thumb',
        sizeBytes: thumbCiphertext.length,
        encryptedKey: thumbWrappedStr,
        localPath: thumbnailFile.path,
        status: 'PENDING',
      );

      result['thumbnail'] = {
        'attachment_id': thumbSha256Hash,
        'filename': '${p.basename(plaintextFile.path)}.thumb',
        'size_bytes': thumbCiphertext.length,
        'file_hash': thumbSha256Hash,
        'encrypted_key': thumbWrappedStr,
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

    while (offset < totalSize) {
      final uploadChunkUrl = uploadUrl.replace(
        queryParameters: {'offset': offset.toString()},
      );
      final uploadReq = await _httpClient.putUrl(uploadChunkUrl);
      uploadReq.headers.set('Authorization', 'Bearer $authToken');
      uploadReq.headers.set('Content-Type', 'application/octet-stream');

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

    final destFile = File(savePath);
    int offset = 0;
    if (destFile.existsSync()) {
      offset = destFile.lengthSync();
    } else {
      destFile.createSync(recursive: true);
    }

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

    // Stream hash verification and decryption without loading full file
    final localAttachment = db.getAttachment(attachmentId);
    if (localAttachment == null) {
      throw StateError('Attachment metadata not found locally');
    }

    final wrappedKeyStr = localAttachment['encrypted_key'] as String;
    final wrappedKey = base64Url.decode(wrappedKeyStr);

    // Verify integrity via streaming hash
    final actualHash = await _computeSha256File(destFile);
    if (actualHash != attachmentId) {
      throw StateError('Downloaded file hash mismatch');
    }

    // Unwrap attachment key
    final unwrapped = await _crypto.unwrapAttachmentKey(
      wrappedKey,
      wrappingKey,
    );
    final keyBytes = unwrapped['key']!;
    final ivBytes = unwrapped['iv']!;

    // Open the ciphertext as secret box and decrypt
    final ciphertext = await destFile.readAsBytes();
    final plaintext = await _crypto.decryptFile(ciphertext, keyBytes, ivBytes);

    final plaintextFile = File(
      savePath.endsWith('.enc')
          ? savePath.substring(0, savePath.length - 4)
          : '$savePath.dec',
    );
    await plaintextFile.writeAsBytes(plaintext);

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

  AttachmentKeyPackage buildKeyDeliveryPackage({
    required String attachmentId,
    required String attachmentKey,
    required List<String> deviceIds,
    required String Function(String deviceId, String key) encryptForDevice,
  }) {
    final deviceKeys = <String, String>{};
    for (final deviceId in deviceIds) {
      deviceKeys[deviceId] = encryptForDevice(deviceId, attachmentKey);
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

  /// Computes SHA-256 hash of a file by reading it in chunks, avoiding
  /// loading the full file into memory.
  Future<String> _computeSha256File(File file) async {
    final sink = crypto_pkg.Sha256().newHashSink();
    final stream = file.openRead();
    await for (final chunk in stream) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
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
