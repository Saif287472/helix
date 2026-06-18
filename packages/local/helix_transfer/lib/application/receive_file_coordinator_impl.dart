import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:helix_protocol/application/contracts/gateways.dart';
import 'package:helix_domain/application/contracts/repositories.dart';
import 'package:helix_protocol/application/contracts/use_cases.dart';
import 'package:helix_domain/domain/models.dart';
import 'package:helix_protocol/protocol/protocol_messages.dart';
import 'package:helix_domain/core/constants.dart';

class _DigestAccumulator implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest d) => value = d;
  @override
  void close() {}
}

class ReceiveFileCoordinatorImpl implements ReceiveFileCoordinator {
  ReceiveFileCoordinatorImpl({
    required this._repository,
    required this._onProgressUpdate,
    required this._getCacheDirectory,
    this._getFinalDirectory,
  });

  final TransferRepository _repository;
  final void Function(
    String threadId,
    String messageId,
    double? progress, {
    String? localFilePath,
  })
  _onProgressUpdate;
  final Future<Directory> Function() _getCacheDirectory;
  // If provided, completed files are moved here instead of staying in cache.
  final Future<Directory> Function(String mimeType)? _getFinalDirectory;

  final Map<String, RandomAccessFile> _openFiles = {};
  // Cached once on first use to avoid a platform-channel call per received chunk.
  Directory? _cachedCacheDir;
  // Tracks the next expected write position per file to skip redundant seeks.
  final Map<String, int> _fileWritePositions = {};
  // Mutable in-place chunk sets — avoids O(n²) Set.of() copy on every chunk.
  final Map<String, Set<int>> _chunkSets = {};
  
  final Map<String, Future<dynamic>> _fileOperations = {};

  Future<T> _serialize<T>(String fileId, Future<T> Function() operation) {
    final previous = _fileOperations[fileId] ?? Future.value();
    final completer = Completer<T>();
    final next = previous.catchError((_) {}).then((_) async {
      try {
        final result = await operation();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    late final Future<void> cleanup;
    cleanup = next.whenComplete(() {
      if (identical(_fileOperations[fileId], cleanup)) {
        _fileOperations.remove(fileId);
      }
    });
    _fileOperations[fileId] = cleanup;
    return completer.future;
  }

  Future<Directory> _getOrFetchCacheDir() async {
    return _cachedCacheDir ??= await _getCacheDirectory();
  }

  static const _kMaxActiveTransfers = 32;

  @override
  Future<File?> receiveChunk({
    required String threadId,
    required String messageId,
    required FileTransferFrame frame,
  }) {
    return _serialize(frame.fileId, () async {
      final expectedChunks =
          (frame.totalSize + kFileChunkSize - 1) ~/ kFileChunkSize;

      final expectedLength = frame.chunkIndex == expectedChunks - 1
          ? frame.totalSize - frame.chunkIndex * kFileChunkSize
          : kFileChunkSize;

      if (frame.chunkCount != expectedChunks ||
          frame.chunkData.length != expectedLength ||
          frame.totalSize <= 0 ||
          frame.totalSize > kMaxFileBytes ||
          frame.chunkIndex < 0 ||
          frame.chunkIndex >= frame.chunkCount) {
        await _cancelTransfer(frame.fileId);
        return null;
      }

      final validId = RegExp(r'^[a-zA-Z0-9_\-]{1,64}$');
      if (!validId.hasMatch(frame.fileId)) {
        throw const FormatException('Invalid file ID');
      }

      var transfer = _repository.loadTransfer(frame.fileId);
      final cacheDir = await _getOrFetchCacheDir();
      final transferDir = Directory(p.join(cacheDir.path, 'transfers'));
      final root = p.normalize(transferDir.absolute.path);
      final partPath = p.normalize(p.join(root, '${frame.fileId}.part'));
      if (!p.isWithin(root, partPath)) {
        throw const FormatException('Unsafe transfer path');
      }
      final partFile = File(partPath);

      if (transfer == null) {
        if (_openFiles.length >= _kMaxActiveTransfers) return null;
        await transferDir.create(recursive: true);
        transfer = FileTransferSession(
          fileId: frame.fileId,
          fileName: frame.fileName,
          mimeType: frame.mimeType,
          totalSize: frame.totalSize,
          chunkCount: frame.chunkCount,
          receivedChunks: const {},
        );
        await _repository.saveTransfer(transfer);
        _chunkSets[frame.fileId] = {};
      }

      if (frame.chunkIndex >= transfer.chunkCount) return null;

      // Open the file if not already open
      var raf = _openFiles[frame.fileId];
      if (raf == null) {
        final isResuming = transfer.usingProbeProtocol;
        final resumeOffset = isResuming ? transfer.resumeStartChunk * kFileChunkSize : 0;
        if (resumeOffset > 0 && await partFile.exists()) {
          raf = await partFile.open(mode: FileMode.writeOnlyAppend);
          await raf.truncate(resumeOffset);
          await raf.setPosition(resumeOffset);
          _fileWritePositions[frame.fileId] = resumeOffset;
        } else {
          raf = await partFile.open(mode: FileMode.writeOnly);
          _fileWritePositions[frame.fileId] = 0;
        }
        _openFiles[frame.fileId] = raf;
      }

      // Use the in-coordinator mutable set — avoids O(n²) Set.of() copy per chunk.
      final chunkSet = _chunkSets[frame.fileId] ??= Set.of(transfer.receivedChunks);

      // Write chunk — skip seek when chunks arrive sequentially (common case).
      if (!chunkSet.contains(frame.chunkIndex)) {
        final expectedPos = frame.chunkIndex * kFileChunkSize;
        if (_fileWritePositions[frame.fileId] != expectedPos) {
          await raf.setPosition(expectedPos);
        }
        await raf.writeFrom(frame.chunkData);
        _fileWritePositions[frame.fileId] = expectedPos + frame.chunkData.length;
        chunkSet.add(frame.chunkIndex);
      }

      final receivedCount = chunkSet.length;
      final isComplete = receivedCount == transfer.chunkCount;
      _onProgressUpdate(
        threadId,
        messageId,
        isComplete ? null : receivedCount / transfer.chunkCount,
      );

      if (!isComplete) return null;

      // When using the probe/resume protocol, finalization is triggered by
      // FileCompleteFrame (receiveComplete). Skip it here.
      if (transfer.usingProbeProtocol) return null;

      await _closeFile(frame.fileId);

      bool success = false;
      File? outFile;
      try {
        await _computeFileSha256(partFile);
        final actualSize = await partFile.length();
        if (actualSize == transfer.totalSize) {
          outFile = await _finalizeFile(
            partFile: partFile,
            mimeType: frame.mimeType,
            fileName: frame.fileName,
          );
          success = true;
        }
      } catch (_) {}

      if (success && outFile != null) {
        await _repository.removeTransfer(frame.fileId);
        _onProgressUpdate(threadId, messageId, null, localFilePath: outFile.path);
        return outFile;
      } else {
        await _cancelTransfer(frame.fileId);
        _onProgressUpdate(threadId, messageId, null);
        return null;
      }
    });
  }

  @override
  Future<void> receiveProbe({
    required String threadId,
    required String messageId,
    required FileProbeFrame frame,
    required TransferGateway gateway,
  }) {
    return _serialize(frame.fileId, () async {
      final validId = RegExp(r'^[a-zA-Z0-9_\-]{1,64}$');
      if (!validId.hasMatch(frame.fileId) ||
          frame.totalSize <= 0 ||
          frame.totalSize > kMaxFileBytes ||
          (!_openFiles.containsKey(frame.fileId) &&
              _openFiles.length >= _kMaxActiveTransfers)) {
        return;
      }

      final cacheDir = await _getOrFetchCacheDir();
      final transferDir = Directory(p.join(cacheDir.path, 'transfers'));
      final root = p.normalize(transferDir.absolute.path);
      final partPath = p.normalize(p.join(root, '${frame.fileId}.part'));
      if (!p.isWithin(root, partPath)) {
        return;
      }
      final partFile = File(partPath);

      int verifiedOffset = 0;

      var transfer = _repository.loadTransfer(frame.fileId);
      if (transfer != null) {
        if (transfer.totalSize != frame.totalSize ||
            transfer.mimeType != frame.mimeType) {
          await _repository.removeTransfer(frame.fileId);
          await _closeFile(frame.fileId);
          try {
            if (await partFile.exists()) await partFile.delete();
          } catch (_) {}
          transfer = null;
        }
      }

      if (transfer != null) {
        // Active in-progress transfer from this session — find last consecutive chunk.
        final chunks = _chunkSets[frame.fileId] ?? Set.of(transfer.receivedChunks);
        int consecutive = 0;
        while (chunks.contains(consecutive)) {
          consecutive++;
        }
        verifiedOffset = consecutive * kFileChunkSize;
        if (verifiedOffset > frame.totalSize) {
          verifiedOffset = 0;
          try {
            if (await partFile.exists()) await partFile.delete();
          } catch (_) {}
        }

        transfer = FileTransferSession(
          fileId: transfer.fileId,
          fileName: transfer.fileName,
          mimeType: transfer.mimeType,
          totalSize: transfer.totalSize,
          chunkCount: transfer.chunkCount,
          resumeStartChunk: verifiedOffset ~/ kFileChunkSize,
          usingProbeProtocol: true,
          receivedChunks: transfer.receivedChunks,
        );
        await _repository.saveTransfer(transfer);
        _chunkSets[frame.fileId] = chunks;
      } else {
        final chunkCount =
            ((frame.totalSize + kFileChunkSize - 1) ~/ kFileChunkSize).clamp(
              1,
              1 << 31,
            );

        if (await partFile.exists()) {
          final rawSize = await partFile.length();
          if (rawSize > frame.totalSize) {
            try {
              await partFile.delete();
            } catch (_) {}
            verifiedOffset = 0;
          } else {
            verifiedOffset = (rawSize ~/ kFileChunkSize) * kFileChunkSize;
          }
        }

        await transferDir.create(recursive: true);
        transfer = FileTransferSession(
          fileId: frame.fileId,
          fileName: frame.fileName,
          mimeType: frame.mimeType,
          totalSize: frame.totalSize,
          chunkCount: chunkCount,
          resumeStartChunk: verifiedOffset ~/ kFileChunkSize,
          usingProbeProtocol: true,
          receivedChunks: const {},
        );
        await _repository.saveTransfer(transfer);
        _chunkSets[frame.fileId] = {};
      }

      // Open file (preserve existing if offset > 0)
      await _closeFile(frame.fileId);
      final raf = await partFile.open(
        mode: verifiedOffset > 0 ? FileMode.writeOnlyAppend : FileMode.writeOnly,
      );
      _openFiles[frame.fileId] = raf;
      _fileWritePositions[frame.fileId] = verifiedOffset;
      if (verifiedOffset > 0) {
        await raf.truncate(verifiedOffset);
        await raf.setPosition(verifiedOffset);
      }

      // Reply to the sender so it knows where to start.
      await gateway.sendFileResume(
        FileResumeFrame(fileId: frame.fileId, resumeOffset: verifiedOffset),
      );
    });
  }

  @override
  Future<void> receiveComplete({
    required String threadId,
    required String messageId,
    required String fileId,
    required String expectedSha256,
  }) {
    return _serialize(fileId, () async {
      final validId = RegExp(r'^[a-zA-Z0-9_\-]{1,64}$');
      if (!validId.hasMatch(fileId)) {
        throw const FormatException('Invalid file ID');
      }

      final transfer = _repository.loadTransfer(fileId);
      if (transfer == null) return;
      await _closeFile(fileId);

      final cacheDir = await _getOrFetchCacheDir();
      final transferDir = Directory(p.join(cacheDir.path, 'transfers'));
      final root = p.normalize(transferDir.absolute.path);
      final partPath = p.normalize(p.join(root, '$fileId.part'));
      if (!p.isWithin(root, partPath)) {
        throw const FormatException('Unsafe transfer path');
      }
      final partFile = File(partPath);

      if (!await partFile.exists()) {
        await _repository.removeTransfer(fileId);
        return;
      }

      bool success = false;
      File? outFile;
      try {
        final actualSha256 = await _computeFileSha256(partFile);
        final actualSize = await partFile.length();
        if (actualSize == transfer.totalSize &&
            actualSha256.toLowerCase() == expectedSha256.toLowerCase()) {
          outFile = await _finalizeFile(
            partFile: partFile,
            mimeType: transfer.mimeType,
            fileName: transfer.fileName,
          );
          success = true;
        }
      } catch (_) {}

      if (success && outFile != null) {
        await _repository.removeTransfer(fileId);
        _onProgressUpdate(threadId, messageId, null, localFilePath: outFile.path);
      } else {
        try {
          if (await partFile.exists()) {
            await partFile.delete();
          }
        } catch (_) {}
        await _repository.removeTransfer(fileId);
        _onProgressUpdate(threadId, messageId, null);
      }
    });
  }

  Future<void> _cancelTransfer(String fileId) async {
    final validId = RegExp(r'^[a-zA-Z0-9_\-]{1,64}$');
    if (!validId.hasMatch(fileId)) {
      return;
    }

    await _repository.removeTransfer(fileId);
    await _closeFile(fileId);

    try {
      final cacheDir = await _getCacheDirectory();
      final transferDir = Directory(p.join(cacheDir.path, 'transfers'));
      final root = p.normalize(transferDir.absolute.path);
      final partPath = p.normalize(p.join(root, '$fileId.part'));
      if (!p.isWithin(root, partPath)) return;
      final partFile = File(partPath);
      if (await partFile.exists()) {
        await partFile.delete();
      }
    } catch (_) {}
  }

  @override
  Future<void> cancelTransfer(String fileId) {
    return _serialize(fileId, () => _cancelTransfer(fileId));
  }

  Future<void> cleanupOldFiles() async {
    try {
      final cacheDir = await _getCacheDirectory();
      final transferDir = Directory(p.join(cacheDir.path, 'transfers'));
      if (!await transferDir.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      await for (final entity in transferDir.list()) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  // Moves .part file to its permanent location and returns the resulting File.
  Future<File> _finalizeFile({
    required File partFile,
    required String mimeType,
    required String fileName,
  }) async {
    final getFinal = _getFinalDirectory;
    final destDir = getFinal != null
        ? await getFinal(mimeType)
        : partFile.parent;
    await destDir.create(recursive: true);

    final safeName = _sanitize(fileName);
    var destPath = p.join(destDir.path, safeName);

    // Avoid overwriting existing files by appending a counter.
    if (await File(destPath).exists()) {
      final ext = p.extension(safeName);
      final base = p.basenameWithoutExtension(safeName);
      var counter = 1;
      while (await File(destPath).exists()) {
        destPath = p.join(destDir.path, '${base}_$counter$ext');
        counter++;
      }
    }

    try {
      // Prefer atomic rename (same volume).
      return await partFile.rename(destPath);
    } catch (_) {
      // Cross-volume fallback: copy then delete.
      final copied = await partFile.copy(destPath);
      try {
        await partFile.delete();
      } catch (_) {}
      return copied;
    }
  }

  Future<void> _closeFile(String fileId) async {
    _fileWritePositions.remove(fileId);
    _chunkSets.remove(fileId);
    final raf = _openFiles.remove(fileId);
    if (raf != null) {
      await raf.close();
    }
  }

  static Future<String> _computeFileSha256(File file) async {
    try {
      final acc = _DigestAccumulator();
      final sink = crypto.sha256.startChunkedConversion(acc);
      await for (final chunk in file.openRead()) {
        sink.add(chunk);
      }
      sink.close();
      return acc.value?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^a-zA-Z0-9._\-]'), '_');
    return cleaned.substring(0, cleaned.length.clamp(0, 64));
  }

  @override
  Future<void> dispose() async {
    final ids = List<String>.of(_openFiles.keys);
    for (final id in ids) {
      await _closeFile(id);
    }
  }
}
