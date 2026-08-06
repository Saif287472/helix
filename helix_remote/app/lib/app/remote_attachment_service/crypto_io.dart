part of '../remote_attachment_service.dart';

extension _RemoteAttachmentCryptoIo on RemoteAttachmentService {
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
    sink.add(RemoteAttachmentService._frameMagic);
    sink.add(_uint32Bytes(RemoteAttachmentService._chunkSize));
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
      final magic = await raf.read(RemoteAttachmentService._frameMagic.length);
      if (!_bytesEqual(magic, RemoteAttachmentService._frameMagic)) {
        throw StateError('Unsupported attachment ciphertext framing');
      }
      final chunkSize = _readUint32(await raf.read(4));
      final originalLength = _readUint64(await raf.read(8));
      if (chunkSize <= 0 || chunkSize > RemoteAttachmentService._chunkSize) {
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
    view.setUint32(8, index, Endian.big);
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
          'version': RemoteAttachmentService._deliverySecretVersion,
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
    if (decoded['version'] != RemoteAttachmentService._deliverySecretVersion) {
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
