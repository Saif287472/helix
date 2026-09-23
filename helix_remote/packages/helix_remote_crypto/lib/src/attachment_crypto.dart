import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;

class RemoteAttachmentCrypto {
  final crypto.AesGcm aesGcm = crypto.AesGcm.with256bits();

  /// STREAM format constants
  static const List<int> streamMagic = [0x48, 0x58, 0x53, 0x54]; // 'HXST'
  static const int streamVersion = 1;
  static const int defaultChunkSize = 65536; // 64 KB

  /// Generate a random 256-bit symmetric key and 96-bit IV.
  Future<Map<String, Uint8List>> generateAttachmentKeys() async {
    final secretKey = await aesGcm.newSecretKey();
    final keyBytes = await secretKey.extractBytes();
    final key = Uint8List.fromList(keyBytes);
    final rand = Random.secure();
    final iv = Uint8List.fromList(List.generate(12, (_) => rand.nextInt(256)));
    return {'key': key, 'iv': iv};
  }

  /// Encrypt a file payload (single-shot for small attachments).
  Future<Uint8List> encryptFile(
    Uint8List plaintext,
    Uint8List key,
    Uint8List iv,
  ) async {
    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: crypto.SecretKey(key),
      nonce: iv,
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Decrypt a file payload (single-shot for small attachments).
  Future<Uint8List> decryptFile(
    Uint8List ciphertextBytes,
    Uint8List key,
    Uint8List iv,
  ) async {
    final box = crypto.SecretBox.fromConcatenation(
      ciphertextBytes,
      nonceLength: 12,
      macLength: 16,
    );
    final plaintext = await aesGcm.decrypt(
      box,
      secretKey: crypto.SecretKey(key),
    );
    return Uint8List.fromList(plaintext);
  }

  /// Wrap a raw attachment key+IV pair using a device-local wrapping key.
  Future<Uint8List> wrapAttachmentKey(
    Uint8List key,
    Uint8List iv,
    Uint8List wrappingKey,
  ) async {
    final plaintext = Uint8List.fromList([...key, ...iv]);
    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: crypto.SecretKey(wrappingKey),
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Unwrap a previously-wrapped attachment key blob using the same
  /// device-local [wrappingKey].
  Future<Map<String, Uint8List>> unwrapAttachmentKey(
    Uint8List wrapped,
    Uint8List wrappingKey,
  ) async {
    final box = crypto.SecretBox.fromConcatenation(
      wrapped,
      nonceLength: 12,
      macLength: 16,
    );
    final decryptedList = await aesGcm.decrypt(
      box,
      secretKey: crypto.SecretKey(wrappingKey),
    );
    final decrypted = Uint8List.fromList(decryptedList);
    return {
      'key': Uint8List.sublistView(decrypted, 0, 32),
      'iv': Uint8List.sublistView(decrypted, 32, 44),
    };
  }

  // ---------------------------------------------------------------------------
  // STREAM Authenticated Framing (64KB chunks, constant memory)
  // ---------------------------------------------------------------------------

  /// Encrypts an arbitrary byte [source] stream using chunked authenticated STREAM construction.
  Stream<List<int>> encryptStream(
    Stream<List<int>> source,
    Uint8List key, {
    int chunkSize = defaultChunkSize,
    Uint8List? baseNonce,
  }) async* {
    final rand = Random.secure();
    final nonce =
        baseNonce ??
        Uint8List.fromList(List.generate(12, (_) => rand.nextInt(256)));

    // 1. Build and yield STREAM header (21 bytes)
    // [4 bytes magic 'HXST'] [1 byte ver] [4 bytes chunkSize] [12 bytes baseNonce]
    final header = Uint8List(21);
    header.setRange(0, 4, streamMagic);
    header[4] = streamVersion;
    final bData = ByteData.sublistView(header);
    bData.setUint32(5, chunkSize, Endian.big);
    header.setRange(9, 21, nonce);
    yield header;

    final secretKey = crypto.SecretKey(key);
    var counter = 0;
    final buffer = <int>[];

    await for (final chunk in source) {
      buffer.addAll(chunk);
      while (buffer.length > chunkSize) {
        final blockPlaintext = Uint8List.fromList(buffer.sublist(0, chunkSize));
        buffer.removeRange(0, chunkSize);

        final blockNonce = _deriveChunkNonce(nonce, counter, false);
        final aad = _buildChunkAad(header, counter, false);

        final box = await aesGcm.encrypt(
          blockPlaintext,
          secretKey: secretKey,
          nonce: blockNonce,
          aad: aad,
        );

        final cipherBytes = box.concatenation(nonce: false);
        final frame = _buildChunkFrame(cipherBytes, false);
        yield frame;
        counter++;
      }
    }

    // Emit final block (can be 0 to chunkSize bytes)
    final finalPlaintext = Uint8List.fromList(buffer);
    final finalNonce = _deriveChunkNonce(nonce, counter, true);
    final finalAad = _buildChunkAad(header, counter, true);

    final finalBox = await aesGcm.encrypt(
      finalPlaintext,
      secretKey: secretKey,
      nonce: finalNonce,
      aad: finalAad,
    );

    final finalCipherBytes = finalBox.concatenation(nonce: false);
    final finalFrame = _buildChunkFrame(finalCipherBytes, true);
    yield finalFrame;
  }

  /// Decrypts a framed STREAM ciphertext [source] stream, verifying authenticity
  /// of every block and rejecting out-of-order, corrupt, or truncated streams.
  Stream<List<int>> decryptStream(
    Stream<List<int>> source,
    Uint8List key,
  ) async* {
    final secretKey = crypto.SecretKey(key);
    final buffer = <int>[];
    Uint8List? header;
    Uint8List? baseNonce;
    var counter = 0;
    var finished = false;

    await for (final chunk in source) {
      buffer.addAll(chunk);

      // Read header if not yet read
      if (header == null) {
        if (buffer.length < 21) continue;
        header = Uint8List.fromList(buffer.sublist(0, 21));
        buffer.removeRange(0, 21);

        if (header[0] != streamMagic[0] ||
            header[1] != streamMagic[1] ||
            header[2] != streamMagic[2] ||
            header[3] != streamMagic[3]) {
          throw const FormatException('Invalid STREAM magic header');
        }
        if (header[4] != streamVersion) {
          throw FormatException('Unsupported STREAM version: ${header[4]}');
        }
        baseNonce = Uint8List.sublistView(header, 9, 21);
      }

      // Read frames: [4 bytes cipherLen] [1 byte isLast] [cipherLen bytes ciphertext+mac]
      while (buffer.length >= 5) {
        final bData = ByteData.sublistView(
          Uint8List.fromList(buffer.sublist(0, 4)),
        );
        final cipherLen = bData.getUint32(0, Endian.big);
        final isLast = buffer[4] == 1;

        final totalFrameLen = 5 + cipherLen;
        if (buffer.length < totalFrameLen) {
          break; // Need more bytes from source
        }

        final cipherBytes = Uint8List.fromList(
          buffer.sublist(5, totalFrameLen),
        );
        buffer.removeRange(0, totalFrameLen);

        final chunkNonce = _deriveChunkNonce(baseNonce!, counter, isLast);
        final aad = _buildChunkAad(header, counter, isLast);

        if (cipherBytes.length < 16) {
          throw const FormatException('Invalid STREAM frame: cipherLen < 16');
        }
        final cipherOnly = cipherBytes.sublist(0, cipherBytes.length - 16);
        final macBytes = cipherBytes.sublist(cipherBytes.length - 16);
        final box = crypto.SecretBox(
          cipherOnly,
          nonce: chunkNonce,
          mac: crypto.Mac(macBytes),
        );

        final plaintext = await aesGcm.decrypt(
          box,
          secretKey: secretKey,
          aad: aad,
        );

        yield plaintext;
        counter++;

        if (isLast) {
          finished = true;
          break;
        }
      }

      if (finished) break;
    }

    if (!finished) {
      throw const FormatException(
        'STREAM truncated: unexpected EOF before final block marker',
      );
    }
  }

  /// Helper to encrypt a file to an output file using constant-memory STREAM.
  Future<void> encryptFileStream({
    required File inputFile,
    required File outputFile,
    required Uint8List key,
    int chunkSize = defaultChunkSize,
  }) async {
    final sink = outputFile.openWrite();
    try {
      await for (final block in encryptStream(
        inputFile.openRead(),
        key,
        chunkSize: chunkSize,
      )) {
        sink.add(block);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// Helper to decrypt a STREAM file to an output file using constant-memory STREAM.
  Future<void> decryptFileStream({
    required File inputFile,
    required File outputFile,
    required Uint8List key,
  }) async {
    final sink = outputFile.openWrite();
    try {
      await for (final block in decryptStream(inputFile.openRead(), key)) {
        sink.add(block);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Uint8List _deriveChunkNonce(Uint8List baseNonce, int counter, bool isLast) {
    final nonce = Uint8List.fromList(baseNonce);
    nonce[7] ^= (counter >> 24) & 0xFF;
    nonce[8] ^= (counter >> 16) & 0xFF;
    nonce[9] ^= (counter >> 8) & 0xFF;
    nonce[10] ^= counter & 0xFF;
    nonce[11] ^= isLast ? 0x01 : 0x00;
    return nonce;
  }

  Uint8List _buildChunkAad(Uint8List header, int counter, bool isLast) {
    final aad = Uint8List(header.length + 5);
    aad.setRange(0, header.length, header);
    final bData = ByteData.sublistView(aad, header.length, aad.length);
    bData.setUint32(0, counter, Endian.big);
    aad[header.length + 4] = isLast ? 1 : 0;
    return aad;
  }

  Uint8List _buildChunkFrame(List<int> cipherBytes, bool isLast) {
    final frame = Uint8List(5 + cipherBytes.length);
    final bData = ByteData.sublistView(frame);
    bData.setUint32(0, cipherBytes.length, Endian.big);
    frame[4] = isLast ? 1 : 0;
    frame.setRange(5, frame.length, cipherBytes);
    return frame;
  }
}
