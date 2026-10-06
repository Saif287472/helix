import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:helix_remote_crypto/src/v2/errors.dart';
import 'package:helix_remote_crypto/src/v2/primitives.dart';

/// Attachment encryption (CRYPTO_V2.md §12): AES-256-GCM in the STREAM
/// construction, re-versioned from v1's unused `RemoteAttachmentCrypto`.
///
/// ```
/// header   = "HXS2" ‖ u8(2) ‖ u32(chunk_size) ‖ nonce_prefix(7)     16 bytes
/// chunk_i  = AES-256-GCM(key, nonce_prefix ‖ u32(i) ‖ u8(last),
///                        chunk plaintext, aad = header ‖ u32(i) ‖ u8(last))
/// file     = header ‖ chunk_0 ‖ … ‖ chunk_n
/// ```
///
/// Every chunk but the last holds exactly `chunk_size` plaintext bytes (so
/// `chunk_size + 16` ciphertext bytes); the last holds 0..chunk_size and is
/// flagged. The header is authenticated by every chunk, and truncation at a
/// chunk boundary fails because the new last chunk was sealed as not-last.
/// `digest = SHA-256(file)` travels in the encrypted `MediaPointer`.
abstract final class AttachmentCrypto {
  static const magic = 'HXS2';
  static const version = 2;
  static const defaultChunkSize = 64 * 1024;
  static const minChunkSize = 64;
  static const maxChunkSize = 1024 * 1024;
  static const headerLength = 16;
  static const noncePrefixLength = 7;
  static const keyLength = 32;

  static Uint8List newKey(CryptoRandom random) => random.nextBytes(keyLength);

  /// Ciphertext size for a plaintext of [plaintextLength] bytes (what
  /// `POST /v1/media` declares).
  static int ciphertextLength(
    int plaintextLength, {
    int chunkSize = defaultChunkSize,
  }) {
    final chunks = plaintextLength == 0
        ? 1
        : (plaintextLength + chunkSize - 1) ~/ chunkSize;
    return headerLength + plaintextLength + chunks * Aead.tagLength;
  }

  static Stream<Uint8List> encrypt(
    Stream<List<int>> plaintext,
    List<int> key, {
    required CryptoRandom random,
    int chunkSize = defaultChunkSize,
  }) async* {
    requireLength(key, keyLength, 'attachment key');
    _checkChunkSize(chunkSize);
    final header = concatBytes([
      label(magic),
      u8(version),
      u32(chunkSize),
      random.nextBytes(noncePrefixLength),
    ]);
    yield header;
    final buffer = _ByteQueue();
    var counter = 0;
    await for (final part in plaintext) {
      buffer.add(part);
      while (buffer.length > chunkSize) {
        yield await _seal(
          key,
          header,
          counter++,
          false,
          buffer.take(chunkSize),
        );
      }
    }
    yield await _seal(key, header, counter, true, buffer.take(buffer.length));
  }

  /// Decrypts and authenticates every chunk. With [expectedDigest], also
  /// checks the SHA-256 of the whole ciphertext at the end; on any error the
  /// caller must discard what was already emitted.
  static Stream<Uint8List> decrypt(
    Stream<List<int>> ciphertext,
    List<int> key, {
    List<int>? expectedDigest,
  }) async* {
    requireLength(key, keyLength, 'attachment key');
    final digest = Sha256Accumulator();
    final buffer = _ByteQueue();
    Uint8List? header;
    var chunkSize = 0;
    var counter = 0;
    await for (final part in ciphertext) {
      digest.add(part);
      buffer.add(part);
      if (header == null) {
        if (buffer.length < headerLength) continue;
        header = buffer.take(headerLength);
        chunkSize = _parseHeader(header);
      }
      while (buffer.length > chunkSize + Aead.tagLength) {
        yield await _open(
          key,
          header,
          counter++,
          false,
          buffer.take(chunkSize + Aead.tagLength),
        );
      }
    }
    if (header == null) {
      throw const MalformedCryptoInputException('attachment header missing');
    }
    if (buffer.length < Aead.tagLength) {
      throw const DecryptionFailedException('attachment truncated');
    }
    yield await _open(key, header, counter, true, buffer.take(buffer.length));
    if (expectedDigest != null && !bytesEqual(digest.close(), expectedDigest)) {
      throw const DecryptionFailedException('attachment digest mismatch');
    }
  }

  /// Whole-file helper for small attachments and thumbnails.
  static Future<EncryptedAttachment> encryptBytes(
    List<int> plaintext,
    List<int> key, {
    required CryptoRandom random,
    int chunkSize = defaultChunkSize,
  }) async {
    final out = BytesBuilder(copy: false);
    await for (final part in encrypt(
      Stream.value(plaintext),
      key,
      random: random,
      chunkSize: chunkSize,
    )) {
      out.add(part);
    }
    final bytes = out.toBytes();
    return EncryptedAttachment(bytes, sha256(bytes));
  }

  /// Checks [digest] before decrypting anything.
  static Future<Uint8List> decryptBytes(
    List<int> ciphertext,
    List<int> key, {
    required List<int> digest,
  }) async {
    if (!bytesEqual(sha256(ciphertext), digest)) {
      throw const DecryptionFailedException('attachment digest mismatch');
    }
    final out = BytesBuilder(copy: false);
    await for (final part in decrypt(Stream.value(ciphertext), key)) {
      out.add(part);
    }
    return out.toBytes();
  }

  static Uint8List chunkNonce(List<int> header, int counter, bool last) =>
      concatBytes([header.sublist(9, 16), u32(counter), u8(last ? 1 : 0)]);

  static Uint8List chunkAad(List<int> header, int counter, bool last) =>
      concatBytes([header, u32(counter), u8(last ? 1 : 0)]);

  static Future<Uint8List> _seal(
    List<int> key,
    Uint8List header,
    int counter,
    bool last,
    Uint8List chunk,
  ) {
    if (!isU32(counter)) throw StateError('attachment too large');
    return Aead.seal(
      key: key,
      nonce: chunkNonce(header, counter, last),
      plaintext: chunk,
      aad: chunkAad(header, counter, last),
    );
  }

  static Future<Uint8List> _open(
    List<int> key,
    Uint8List header,
    int counter,
    bool last,
    Uint8List chunk,
  ) {
    if (!isU32(counter)) {
      throw const MalformedCryptoInputException('attachment too large');
    }
    return Aead.open(
      key: key,
      nonce: chunkNonce(header, counter, last),
      ciphertext: chunk,
      aad: chunkAad(header, counter, last),
    );
  }

  static int _parseHeader(Uint8List header) {
    if (!bytesEqual(header.sublist(0, 4), label(magic))) {
      throw const MalformedCryptoInputException('not a v2 attachment');
    }
    if (header[4] != version) {
      throw const MalformedCryptoInputException(
        'unsupported attachment version',
      );
    }
    final chunkSize = ByteData.sublistView(header).getUint32(5);
    if (chunkSize < minChunkSize || chunkSize > maxChunkSize) {
      throw const MalformedCryptoInputException('attachment chunk size');
    }
    return chunkSize;
  }

  static void _checkChunkSize(int chunkSize) {
    if (chunkSize < minChunkSize || chunkSize > maxChunkSize) {
      throw ArgumentError.value(chunkSize, 'chunkSize');
    }
  }
}

final class EncryptedAttachment {
  const EncryptedAttachment(this.ciphertext, this.digest);

  final Uint8List ciphertext;

  /// SHA-256 of [ciphertext], for `MediaPointer.digest`.
  final Uint8List digest;
}

/// Incremental SHA-256 (for digests of streamed ciphertext).
final class Sha256Accumulator {
  Sha256Accumulator() {
    _input = hashes.sha256.startChunkedConversion(_sink);
  }

  final _DigestSink _sink = _DigestSink();
  late final Sink<List<int>> _input;

  void add(List<int> bytes) => _input.add(bytes);

  Uint8List close() {
    _input.close();
    return Uint8List.fromList(_sink.value!.bytes);
  }
}

final class _DigestSink implements Sink<hashes.Digest> {
  hashes.Digest? value;

  @override
  void add(hashes.Digest data) => value = data;

  @override
  void close() {}
}

/// A FIFO of bytes that hands out exact-length slices.
final class _ByteQueue {
  final List<Uint8List> _parts = [];
  int _offset = 0;
  int length = 0;

  void add(List<int> bytes) {
    if (bytes.isEmpty) return;
    _parts.add(Uint8List.fromList(bytes));
    length += bytes.length;
  }

  Uint8List take(int n) {
    final out = Uint8List(n);
    var filled = 0;
    while (filled < n) {
      final head = _parts.first;
      final available = head.length - _offset;
      final count = available < n - filled ? available : n - filled;
      out.setRange(filled, filled + count, head, _offset);
      filled += count;
      _offset += count;
      if (_offset == head.length) {
        _parts.removeAt(0);
        _offset = 0;
      }
    }
    length -= n;
    return out;
  }
}
