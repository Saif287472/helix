import 'dart:async';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';

class _DigestAccumulator implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest d) => value = d;
  @override
  void close() {}
}

class SendFileUseCaseImpl implements SendFileUseCase {
  SendFileUseCaseImpl({required this._onProgressUpdate});

  final void Function(
    String threadId,
    String messageId,
    double? progress, {
    String? localFilePath,
  })
  _onProgressUpdate;

  @override
  Future<void> sendFile({
    required String threadId,
    required String messageId,
    required String fileId,
    required File file,
    required String mimeType,
    required TransferGateway gateway,
  }) async {
    final fileName = p.basename(file.path);
    final totalSize = await file.length();
    final chunkCount = ((totalSize + kFileChunkSize - 1) ~/ kFileChunkSize)
        .clamp(1, 1 << 31);

    int startChunk = 0;

    if (gateway.supportsFileResume) {
      final completer = Completer<FileResumeFrame>();
      final resumeSub = gateway.resumeEvents
          .where((f) => f.fileId == fileId)
          .listen(
            (f) { if (!completer.isCompleted) completer.complete(f); },
            onError: (Object e, StackTrace s) {
              if (!completer.isCompleted) completer.completeError(e, s);
            },
          );

      try {
        // SHA-256 is computed inline during send; send empty hash in probe.
        // Receiver verifies against FileCompleteFrame which carries the real hash.
        await gateway.sendProbe(
          FileProbeFrame(
            fileId: fileId,
            fileName: fileName,
            mimeType: mimeType,
            totalSize: totalSize,
            sha256: '',
          ),
        );

        final resumeFrame = await completer.future
            .timeout(const Duration(seconds: 30));
        final offset = resumeFrame.resumeOffset;
        if (offset < 0 ||
            offset > totalSize ||
            offset % kFileChunkSize != 0) {
          throw const FormatException('Invalid resume offset');
        }
        startChunk = offset ~/ kFileChunkSize;
      } finally {
        await resumeSub.cancel();
      }
    }

    // Read the full file from byte 0 in a single sequential pass.
    // Chunks before startChunk are fed into the hash but not sent (fast disk-only
    // pass needed only for resumed transfers to produce a full-file SHA-256).
    // For fresh transfers startChunk == 0, so no extra I/O occurs.
    final shaAcc = _DigestAccumulator();
    final shaSink = crypto.sha256.startChunkedConversion(shaAcc);

    final raf = await file.open(mode: FileMode.read);
    try {
      for (var i = 0; i < chunkCount; i++) {
        final remaining = totalSize - i * kFileChunkSize;
        final length = min(kFileChunkSize, remaining);
        final buffer = Uint8List(length);
        final read = await raf.readInto(buffer, 0, length);
        if (read != length) {
          throw const FileSystemException('File changed during transfer');
        }
        shaSink.add(buffer);

        if (i >= startChunk) {
          await gateway.sendChunk(
            FileTransferFrame(
              fileId: fileId,
              fileName: fileName,
              mimeType: mimeType,
              totalSize: totalSize,
              chunkIndex: i,
              chunkCount: chunkCount,
              chunkData: buffer,
            ),
          );

          final sent = i - startChunk + 1;
          final total = chunkCount - startChunk;
          final progress = sent / total;
          _onProgressUpdate(
            threadId,
            messageId,
            progress < 1.0 ? progress : null,
          );
        }
      }
    } finally {
      await raf.close();
    }

    shaSink.close();
    final sha256 = shaAcc.value?.toString() ?? '';

    if (await file.length() != totalSize) {
      throw const FileSystemException('File size changed during transfer');
    }

    if (gateway.supportsFileResume) {
      await gateway.sendComplete(
        FileCompleteFrame(fileId: fileId, sha256: sha256),
      );
      _onProgressUpdate(threadId, messageId, null, localFilePath: file.path);
    } else {
      _onProgressUpdate(threadId, messageId, null, localFilePath: file.path);
    }
  }
}
