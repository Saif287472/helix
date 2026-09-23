import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_crypto/src/attachment_crypto.dart';

void main() {
  late RemoteAttachmentCrypto crypto;
  late Uint8List symmetricKey;

  setUp(() async {
    crypto = RemoteAttachmentCrypto();
    final keys = await crypto.generateAttachmentKeys();
    symmetricKey = keys['key']!;
  });

  test('STREAM round-trip with empty payload', () async {
    final input = <int>[];
    final encryptedChunks = <int>[];

    await for (final chunk in crypto.encryptStream(
      Stream.fromIterable([input]),
      symmetricKey,
    )) {
      encryptedChunks.addAll(chunk);
    }

    final decrypted = <int>[];
    await for (final chunk in crypto.decryptStream(
      Stream.fromIterable([encryptedChunks]),
      symmetricKey,
    )) {
      decrypted.addAll(chunk);
    }

    expect(decrypted, isEmpty);
  });

  test('STREAM round-trip with multi-chunk payload (custom small chunk size)', () async {
    // Generate 5000 random bytes with 1024-byte chunks (yields 4 full blocks + 1 final 904-byte block)
    final rand = Random(42);
    final original = Uint8List.fromList(List.generate(5000, (_) => rand.nextInt(256)));

    final encryptedBytes = <int>[];
    await for (final block in crypto.encryptStream(
      Stream.value(original),
      symmetricKey,
      chunkSize: 1024,
    )) {
      encryptedBytes.addAll(block);
    }

    final decryptedBytes = <int>[];
    await for (final block in crypto.decryptStream(
      Stream.value(encryptedBytes),
      symmetricKey,
    )) {
      decryptedBytes.addAll(block);
    }

    expect(Uint8List.fromList(decryptedBytes), equals(original));
  });

  test('STREAM round-trip across default 64KB chunks', () async {
    // 150KB payload across 64KB blocks (2 full blocks + 1 final block)
    final rand = Random(123);
    final original = Uint8List.fromList(
      List.generate(150 * 1024, (_) => rand.nextInt(256)),
    );

    final encryptedBytes = <int>[];
    await for (final block in crypto.encryptStream(
      Stream.value(original),
      symmetricKey,
    )) {
      encryptedBytes.addAll(block);
    }

    final decryptedBytes = <int>[];
    await for (final block in crypto.decryptStream(
      Stream.value(encryptedBytes),
      symmetricKey,
    )) {
      decryptedBytes.addAll(block);
    }

    expect(Uint8List.fromList(decryptedBytes), equals(original));
  });

  test('STREAM rejects truncated ciphertext missing final chunk', () async {
    final original = Uint8List.fromList(List.generate(3000, (i) => i % 256));
    final frames = <List<int>>[];

    await for (final block in crypto.encryptStream(
      Stream.value(original),
      symmetricKey,
      chunkSize: 1000,
    )) {
      frames.add(block);
    }

    // frames contains [header, chunk0, chunk1, chunk2, chunkFinal]
    // Drop the last chunk to simulate network truncation
    frames.removeLast();

    final truncatedStream = Stream.fromIterable(frames);
    expect(
      () async {
        await for (final _ in crypto.decryptStream(truncatedStream, symmetricKey)) {}
      },
      throwsA(isA<FormatException>().having(
        (e) => e.message,
        'message',
        contains('STREAM truncated'),
      )),
    );
  });

  test('STREAM rejects corrupted chunk ciphertext/tag', () async {
    final original = Uint8List.fromList(List.generate(3000, (i) => i % 256));
    final encryptedBytes = <int>[];

    await for (final block in crypto.encryptStream(
      Stream.value(original),
      symmetricKey,
      chunkSize: 1000,
    )) {
      encryptedBytes.addAll(block);
    }

    // Corrupt one byte in the middle of ciphertext
    encryptedBytes[100] ^= 0xFF;

    expect(
      () async {
        await for (final _ in crypto.decryptStream(
          Stream.value(encryptedBytes),
          symmetricKey,
        )) {}
      },
      throwsA(anything), // AEAD MAC failure throws SecretBoxAuthenticationError
    );
  });

  test('STREAM file-based encryption and decryption round-trip', () async {
    final tempDir = await Directory.systemTemp.createTemp('helix_stream_test_');
    final inFile = File('${tempDir.path}/in.bin');
    final encFile = File('${tempDir.path}/enc.bin');
    final outFile = File('${tempDir.path}/out.bin');

    try {
      final sampleData = Uint8List.fromList(List.generate(20000, (i) => (i * 7) % 256));
      await inFile.writeAsBytes(sampleData);

      await crypto.encryptFileStream(
        inputFile: inFile,
        outputFile: encFile,
        key: symmetricKey,
        chunkSize: 4096,
      );

      await crypto.decryptFileStream(
        inputFile: encFile,
        outputFile: outFile,
        key: symmetricKey,
      );

      final decryptedData = await outFile.readAsBytes();
      expect(decryptedData, equals(sampleData));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
