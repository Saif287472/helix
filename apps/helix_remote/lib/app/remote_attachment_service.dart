import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:helix_remote/app/remote_endpoints.dart';
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
       _endpoints = RemoteApiEndpoints(Uri.parse(baseUrl)),
       _httpClient = httpClient ?? HttpClient();

  final String baseUrl;
  String authToken;
  final HelixRemoteDatabase db;
  final Directory tempDir;
  final Uint8List wrappingKey;
  final RemoteAttachmentCrypto _crypto;
  final RemoteApiEndpoints _endpoints;
  final HttpClient _httpClient;
  static const int _chunkSize = 64 * 1024;
  static final Uint8List _frameMagic = Uint8List.fromList([
    0x48,
    0x4c,
    0x58,
    0x41,
    0x31,
    0x0a,
  ]);
  static const String _deliverySecretVersion = 'helix.remote.attachment-key.v1';

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

    final stagingCipherFile = File(
      p.join(tempDir.path, '${_randomFileStem()}.upload.enc'),
    );
    if (!stagingCipherFile.parent.existsSync()) {
      stagingCipherFile.parent.createSync(recursive: true);
    }
    await _encryptFileToCache(
      plaintextFile,
      stagingCipherFile,
      keyBytes,
      ivBytes,
    );

    final sha256Hash = await _computeSha256File(stagingCipherFile);
    final tempCipherFile = File(p.join(tempDir.path, '$sha256Hash.enc'));
    if (tempCipherFile.existsSync()) {
      await tempCipherFile.delete();
    }
    await stagingCipherFile.rename(tempCipherFile.path);

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
      sizeBytes: tempCipherFile.lengthSync(),
      encryptedKey: wrappedKeyStr,
      localPath: null,
      importedSourcePath: plaintextFile.path,
      encryptedCachePath: tempCipherFile.path,
      status: 'PENDING',
    );

    final result = <String, dynamic>{
      'attachment_id': sha256Hash,
      'filename': p.basename(plaintextFile.path),
      'size_bytes': tempCipherFile.lengthSync(),
      'file_hash': sha256Hash,
      'encrypted_key': wrappedKeyStr,
      'key_delivery_secret': _encodeDeliverySecret(keyBytes, ivBytes),
      'ciphertext_path': tempCipherFile.path,
    };

    if (thumbnailFile != null) {
      if (thumbnailFile.lengthSync() > 1024 * 1024) {
        throw ArgumentError('Thumbnail file size exceeds the 1MB limit');
      }

      final thumbKeys = _crypto.generateAttachmentKeys();
      final thumbKeyBytes = thumbKeys['key']!;
      final thumbIvBytes = thumbKeys['iv']!;

      final thumbStagingCipherFile = File(
        p.join(tempDir.path, '${_randomFileStem()}.thumb.upload.enc'),
      );
      await _encryptFileToCache(
        thumbnailFile,
        thumbStagingCipherFile,
        thumbKeyBytes,
        thumbIvBytes,
      );
      final thumbSha256Hash = await _computeSha256File(thumbStagingCipherFile);
      final tempThumbCipherFile = File(
        p.join(tempDir.path, '$thumbSha256Hash.enc'),
      );
      if (tempThumbCipherFile.existsSync()) {
        await tempThumbCipherFile.delete();
      }
      await thumbStagingCipherFile.rename(tempThumbCipherFile.path);

      final thumbWrapped = await _crypto.wrapAttachmentKey(
        thumbKeyBytes,
        thumbIvBytes,
        wrappingKey,
      );
      final thumbWrappedStr = base64Url.encode(thumbWrapped);

      db.saveAttachment(
        attachmentId: thumbSha256Hash,
        filename: '${p.basename(plaintextFile.path)}.thumb',
        sizeBytes: tempThumbCipherFile.lengthSync(),
        encryptedKey: thumbWrappedStr,
        localPath: null,
        importedSourcePath: thumbnailFile.path,
        encryptedCachePath: tempThumbCipherFile.path,
        status: 'PENDING',
      );

      result['thumbnail'] = {
        'attachment_id': thumbSha256Hash,
        'filename': '${p.basename(plaintextFile.path)}.thumb',
        'size_bytes': tempThumbCipherFile.lengthSync(),
        'file_hash': thumbSha256Hash,
        'encrypted_key': thumbWrappedStr,
        'key_delivery_secret': _encodeDeliverySecret(
          thumbKeyBytes,
          thumbIvBytes,
        ),
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

    final requestUrl = _endpoints.attachmentsUpload;
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
    final uploadUrl = _endpoints.resolveServerPath(uploadPath);

    final statusUrl = _endpoints.attachmentUploadStatus(attachmentId);
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
        importedSourcePath: localAttachment['imported_source_path'] as String?,
        encryptedCachePath: localAttachment['encrypted_cache_path'] as String?,
        downloadedCiphertextPath:
            localAttachment['downloaded_ciphertext_path'] as String?,
        exportedPlaintextPath:
            localAttachment['exported_plaintext_path'] as String?,
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
    final requestUrl = _endpoints.attachmentDownload(attachmentId);
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
    final downloadUrl = _endpoints.resolveServerPath(downloadPath);

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

    final plaintextFile = File(
      savePath.endsWith('.enc')
          ? savePath.substring(0, savePath.length - 4)
          : '$savePath.dec',
    );
    await _decryptCacheToFile(destFile, plaintextFile, keyBytes, ivBytes);

    db.saveAttachment(
      attachmentId: attachmentId,
      filename: localAttachment['filename'] as String,
      sizeBytes: localAttachment['size_bytes'] as int,
      encryptedKey: localAttachment['encrypted_key'] as String,
      localPath: plaintextFile.path,
      importedSourcePath: localAttachment['imported_source_path'] as String?,
      encryptedCachePath: localAttachment['encrypted_cache_path'] as String?,
      downloadedCiphertextPath: destFile.path,
      exportedPlaintextPath:
          localAttachment['exported_plaintext_path'] as String?,
      status: 'DOWNLOADED',
    );

    return plaintextFile;
  }

  void evictLocalCache(String attachmentId) {
    final localAttachment = db.getAttachment(attachmentId);
    if (localAttachment == null) return;

    _deleteIfAppOwned(localAttachment['local_path'] as String?);
    _deleteIfAppOwned(localAttachment['encrypted_cache_path'] as String?);
    _deleteIfAppOwned(localAttachment['downloaded_ciphertext_path'] as String?);

    db.saveAttachment(
      attachmentId: attachmentId,
      filename: localAttachment['filename'] as String,
      sizeBytes: localAttachment['size_bytes'] as int,
      encryptedKey: localAttachment['encrypted_key'] as String,
      localPath: null,
      importedSourcePath: localAttachment['imported_source_path'] as String?,
      encryptedCachePath: null,
      downloadedCiphertextPath: null,
      exportedPlaintextPath:
          localAttachment['exported_plaintext_path'] as String?,
      status: 'CACHE_EVICTED',
    );
  }

  Future<void> importAttachmentKeyFromMessage({
    required RemoteAttachmentManifest manifest,
    required String filename,
    required String keyDeliverySecret,
  }) async {
    if (db.getAttachment(manifest.fileId) != null) return;
    final keyParts = _decodeDeliverySecret(keyDeliverySecret);
    final wrappedKey = await _crypto.wrapAttachmentKey(
      keyParts['key']!,
      keyParts['iv']!,
      wrappingKey,
    );
    db.saveAttachment(
      attachmentId: manifest.fileId,
      filename: filename,
      sizeBytes: manifest.fileSize,
      encryptedKey: base64Url.encode(wrappedKey),
      status: 'PENDING',
    );
  }

  void updateAttachmentStatus(String attachmentId, String status) {
    final localAttachment = db.getAttachment(attachmentId);
    if (localAttachment == null) return;
    db.saveAttachment(
      attachmentId: attachmentId,
      filename: localAttachment['filename'] as String,
      sizeBytes: localAttachment['size_bytes'] as int,
      encryptedKey: localAttachment['encrypted_key'] as String,
      localPath: localAttachment['local_path'] as String?,
      importedSourcePath: localAttachment['imported_source_path'] as String?,
      encryptedCachePath: localAttachment['encrypted_cache_path'] as String?,
      downloadedCiphertextPath:
          localAttachment['downloaded_ciphertext_path'] as String?,
      exportedPlaintextPath:
          localAttachment['exported_plaintext_path'] as String?,
      status: status,
    );
  }

  void markAttachmentExported({
    required String attachmentId,
    required String exportedPlaintextPath,
  }) {
    final localAttachment = db.getAttachment(attachmentId);
    if (localAttachment == null) return;
    db.saveAttachment(
      attachmentId: attachmentId,
      filename: localAttachment['filename'] as String,
      sizeBytes: localAttachment['size_bytes'] as int,
      encryptedKey: localAttachment['encrypted_key'] as String,
      localPath: localAttachment['local_path'] as String?,
      importedSourcePath: localAttachment['imported_source_path'] as String?,
      encryptedCachePath: localAttachment['encrypted_cache_path'] as String?,
      downloadedCiphertextPath:
          localAttachment['downloaded_ciphertext_path'] as String?,
      exportedPlaintextPath: exportedPlaintextPath,
      status: localAttachment['status'] as String,
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
    final requestUrl = _endpoints.attachmentsRegisterReference;
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

  Future<void> _encryptFileToCache(
    File plaintextFile,
    File ciphertextFile,
    Uint8List keyBytes,
    Uint8List ivBytes,
  ) async {
    final algorithm = crypto_pkg.AesGcm.with256bits();
    final secretKey = crypto_pkg.SecretKey(keyBytes);
    final sink = ciphertextFile.openWrite(mode: FileMode.write);
    final originalLength = plaintextFile.lengthSync();
    sink.add(_frameMagic);
    sink.add(_uint32Bytes(_chunkSize));
    sink.add(_uint64Bytes(originalLength));
    var index = 0;
    await for (final chunk in plaintextFile.openRead()) {
      final nonce = _chunkNonce(ivBytes, index);
      final aad = _chunkAad(index, originalLength, chunk.length);
      final box = await algorithm.encrypt(
        chunk,
        secretKey: secretKey,
        nonce: nonce,
        aad: aad,
      );
      final framed = Uint8List.fromList(box.concatenation());
      sink.add(_uint32Bytes(index));
      sink.add(_uint32Bytes(chunk.length));
      sink.add(_uint32Bytes(framed.length));
      sink.add(framed);
      index++;
    }
    await sink.close();
  }

  Future<void> _decryptCacheToFile(
    File ciphertextFile,
    File plaintextFile,
    Uint8List keyBytes,
    Uint8List ivBytes,
  ) async {
    final raf = await ciphertextFile.open();
    IOSink? sink;
    try {
      final magic = await raf.read(_frameMagic.length);
      if (!_bytesEqual(magic, _frameMagic)) {
        throw StateError('Unsupported attachment ciphertext framing');
      }
      final chunkSize = _readUint32(await raf.read(4));
      final originalLength = _readUint64(await raf.read(8));
      if (chunkSize <= 0 || chunkSize > _chunkSize) {
        throw StateError('Invalid attachment chunk size');
      }

      final algorithm = crypto_pkg.AesGcm.with256bits();
      final secretKey = crypto_pkg.SecretKey(keyBytes);
      if (!plaintextFile.parent.existsSync()) {
        plaintextFile.parent.createSync(recursive: true);
      }
      sink = plaintextFile.openWrite(mode: FileMode.write);
      var expectedIndex = 0;
      var written = 0;
      while (await raf.position() < await raf.length()) {
        final index = _readUint32(await raf.read(4));
        final plainLength = _readUint32(await raf.read(4));
        final boxLength = _readUint32(await raf.read(4));
        if (index != expectedIndex ||
            plainLength < 0 ||
            plainLength > chunkSize ||
            boxLength < 28) {
          throw StateError('Invalid attachment ciphertext chunk order');
        }
        final framed = await raf.read(boxLength);
        if (framed.length != boxLength) {
          throw StateError('Truncated attachment ciphertext chunk');
        }
        final box = crypto_pkg.SecretBox.fromConcatenation(
          framed,
          nonceLength: 12,
          macLength: 16,
        );
        final aad = _chunkAad(index, originalLength, plainLength);
        final plaintext = await algorithm.decrypt(
          box,
          secretKey: secretKey,
          aad: aad,
        );
        if (plaintext.length != plainLength) {
          throw StateError('Attachment plaintext chunk length mismatch');
        }
        sink.add(plaintext);
        written += plaintext.length;
        expectedIndex++;
      }
      await sink.close();
      sink = null;
      if (written != originalLength) {
        throw StateError('Attachment plaintext length mismatch');
      }
    } catch (_) {
      if (plaintextFile.existsSync()) {
        try {
          plaintextFile.deleteSync();
        } catch (_) {}
      }
      rethrow;
    } finally {
      await sink?.close();
      await raf.close();
    }
  }

  Uint8List _chunkNonce(Uint8List ivBytes, int index) {
    final nonce = Uint8List.fromList(ivBytes);
    final view = ByteData.sublistView(nonce);
    final low = view.getUint32(8, Endian.big);
    view.setUint32(8, low ^ index, Endian.big);
    return nonce;
  }

  Uint8List _chunkAad(int index, int originalLength, int plainLength) {
    return Uint8List.fromList(
      utf8.encode(
        'helix.remote.attachment.v1:$index:$originalLength:$plainLength',
      ),
    );
  }

  Uint8List _uint32Bytes(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  Uint8List _uint64Bytes(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  int _readUint32(Uint8List bytes) {
    if (bytes.length != 4) throw StateError('Truncated uint32');
    return ByteData.sublistView(bytes).getUint32(0, Endian.big);
  }

  int _readUint64(Uint8List bytes) {
    if (bytes.length != 8) throw StateError('Truncated uint64');
    return ByteData.sublistView(bytes).getUint64(0, Endian.big);
  }

  bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  String _randomFileStem() {
    final bytes = _crypto.aesGcm.newNonce();
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _encodeDeliverySecret(Uint8List keyBytes, Uint8List ivBytes) {
    return base64Url.encode(
      utf8.encode(
        jsonEncode({
          'version': _deliverySecretVersion,
          'key': base64Url.encode(keyBytes),
          'iv': base64Url.encode(ivBytes),
        }),
      ),
    );
  }

  Map<String, Uint8List> _decodeDeliverySecret(String secret) {
    final decoded =
        jsonDecode(utf8.decode(base64Url.decode(secret)))
            as Map<String, dynamic>;
    if (decoded['version'] != _deliverySecretVersion) {
      throw StateError('Unsupported attachment key delivery version');
    }
    return {
      'key': Uint8List.fromList(base64Url.decode(decoded['key'] as String)),
      'iv': Uint8List.fromList(base64Url.decode(decoded['iv'] as String)),
    };
  }

  void _deleteIfAppOwned(String? path) {
    if (path == null || path.isEmpty) return;
    final normalizedBase = p.normalize(p.absolute(tempDir.path));
    final normalizedTarget = p.normalize(p.absolute(path));
    if (!p.isWithin(normalizedBase, normalizedTarget) &&
        normalizedBase != normalizedTarget) {
      return;
    }
    final file = File(normalizedTarget);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
