import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_protocol/application/contracts/gateways.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix_domain/core/constants.dart';
import 'package:helix_protocol/protocol/protocol_messages.dart';

class SendEphemeralMediaUseCaseImpl implements SendEphemeralMediaUseCase {
  SendEphemeralMediaUseCaseImpl({
    required this._cache,
    required this._onProgressUpdate,
  });

  final EphemeralMediaCache _cache;
  final void Function(
    String threadId,
    String messageId,
    double? progress, {
    String? localFilePath,
  })
  _onProgressUpdate;

  @override
  Future<Uint8List> prepareImage(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    int quality = 85;
    Uint8List out;
    do {
      out = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
      if (out.length <= kEphemeralImageMaxBytes || quality <= 10) break;
      quality -= 10;
    } while (true);

    return out;
  }

  @override
  Uint8List prepareVoice(Uint8List bytes) {
    if (bytes.length > kEphemeralVoiceMaxBytes) {
      throw ArgumentError(
        'Voice note exceeds ${kEphemeralVoiceMaxBytes ~/ (1024 * 1024)} MiB limit',
      );
    }
    return _stripAudioMetadata(bytes);
  }

  // Strips ID3v2 (header at start) and ID3v1 (last 128 bytes) from MP3 bytes.
  // Other container formats (AAC/M4A, OGG, FLAC) are passed through unchanged.
  static Uint8List _stripAudioMetadata(Uint8List bytes) {
    var start = 0;
    var end = bytes.length;

    // ID3v2: starts with "ID3" magic
    if (bytes.length > 10 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      // Size is a syncsafe integer across bytes 6–9
      final size =
          (bytes[6] << 21) | (bytes[7] << 14) | (bytes[8] << 7) | bytes[9];
      final hasFooter = (bytes[5] & 0x10) != 0;
      final candidate = 10 + size + (hasFooter ? 10 : 0);
      if (candidate <= bytes.length) start = candidate;
    }

    // ID3v1: last 128 bytes starting with "TAG"
    if (end - start >= 128 &&
        bytes[end - 128] == 0x54 &&
        bytes[end - 127] == 0x41 &&
        bytes[end - 126] == 0x47) {
      end -= 128;
    }

    if (start == 0 && end == bytes.length) return bytes;
    return Uint8List.sublistView(bytes, start, end);
  }

  @override
  Future<void> sendMedia({
    required String mediaId,
    required String mimeType,
    required Uint8List prepared,
    required String threadId,
    required String messageId,
    required EphemeralMediaGateway gateway,
  }) async {
    // Cache locally
    _cache.storeMedia(mediaId, prepared);

    final totalSize = prepared.length;
    final chunkCount =
        ((totalSize + kEphemeralMediaChunkSize - 1) ~/ kEphemeralMediaChunkSize)
            .clamp(1, 1 << 31);

    for (var i = 0; i < chunkCount; i++) {
      final start = i * kEphemeralMediaChunkSize;
      final end = (start + kEphemeralMediaChunkSize).clamp(0, totalSize);
      final chunkData = prepared.sublist(start, end);

      await gateway.sendEphemeralMedia(
        EphemeralMediaFrame(
          mediaId: mediaId,
          mimeType: mimeType,
          totalSize: totalSize,
          chunkIndex: i,
          chunkCount: chunkCount,
          chunkData: chunkData,
        ),
      );

      final progress = (i + 1) / chunkCount;
      _onProgressUpdate(threadId, messageId, progress < 1.0 ? progress : null);
    }

    // Mark send complete
    _onProgressUpdate(threadId, messageId, null);
  }
}
