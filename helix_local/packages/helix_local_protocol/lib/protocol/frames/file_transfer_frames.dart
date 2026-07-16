part of '../protocol_messages.dart';

// ---------------------------------------------------------------------------
// 0x13 FileTransferFrame
// ---------------------------------------------------------------------------

class FileTransferFrame extends ProtocolFrame {
  @override
  final int type = kTypeFileTransfer;

  final String fileId;
  final String fileName;
  final String mimeType;
  final int totalSize;
  final int chunkIndex;
  final int chunkCount;
  final Uint8List chunkData;

  FileTransferFrame({
    required this.fileId,
    required this.fileName,
    required this.mimeType,
    required this.totalSize,
    required this.chunkIndex,
    required this.chunkCount,
    required this.chunkData,
  });

  factory FileTransferFrame._fromMap(Map<Object?, Object?> map) {
    final fileId = _requireString(map, 1, 'fileId');
    final validId = RegExp(r'^[a-zA-Z0-9_\-]{1,64}$');
    if (!validId.hasMatch(fileId)) {
      throw const FormatException('Invalid file ID format');
    }
    return FileTransferFrame(
      fileId: fileId,
      fileName: _requireString(map, 2, 'fileName'),
      mimeType: _requireString(map, 3, 'mimeType'),
      totalSize: _requireInt(map, 4, 'totalSize'),
      chunkIndex: _requireInt(map, 5, 'chunkIndex'),
      chunkCount: _requireInt(map, 6, 'chunkCount'),
      chunkData: _requireBytes(map, 7, 'chunkData'),
    );
  }

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeFileTransfer,
    1: fileId,
    2: fileName,
    3: mimeType,
    4: totalSize,
    5: chunkIndex,
    6: chunkCount,
    7: chunkData,
  });
}

// ---------------------------------------------------------------------------
// 0x17 FileProbeFrame — sender announces intent + SHA-256 before sending chunks
// ---------------------------------------------------------------------------

class FileProbeFrame extends ProtocolFrame {
  @override
  final int type = kTypeFileProbe;

  final String fileId;
  final String fileName;
  final String mimeType;
  final int totalSize;

  /// Hex-encoded SHA-256 of the complete file, used for final verification.
  final String sha256;

  FileProbeFrame({
    required this.fileId,
    required this.fileName,
    required this.mimeType,
    required this.totalSize,
    required this.sha256,
  });

  factory FileProbeFrame._fromMap(Map<Object?, Object?> map) {
    final fileId = _requireString(map, 1, 'fileId');
    final validId = RegExp(r'^[a-zA-Z0-9_\-]{1,64}$');
    if (!validId.hasMatch(fileId)) {
      throw const FormatException('Invalid file ID format');
    }
    return FileProbeFrame(
      fileId: fileId,
      fileName: _requireString(map, 2, 'fileName'),
      mimeType: _requireString(map, 3, 'mimeType'),
      totalSize: _requireInt(map, 4, 'totalSize'),
      sha256: _requireString(map, 5, 'sha256'),
    );
  }

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeFileProbe,
    1: fileId,
    2: fileName,
    3: mimeType,
    4: totalSize,
    5: sha256,
  });
}

// ---------------------------------------------------------------------------
// 0x18 FileResumeFrame — receiver replies with byte offset to resume from
// ---------------------------------------------------------------------------

class FileResumeFrame extends ProtocolFrame {
  @override
  final int type = kTypeFileResume;

  final String fileId;

  /// Byte offset in the file where the sender should start (re-)sending.
  /// 0 for a fresh transfer; positive for a resumed partial transfer.
  final int resumeOffset;

  FileResumeFrame({required this.fileId, required this.resumeOffset});

  factory FileResumeFrame._fromMap(Map<Object?, Object?> map) =>
      FileResumeFrame(
        fileId: _requireString(map, 1, 'fileId'),
        resumeOffset: _requireInt(map, 2, 'resumeOffset'),
      );

  @override
  Uint8List encode() =>
      _cborEncodeMap({0: kTypeFileResume, 1: fileId, 2: resumeOffset});
}

// ---------------------------------------------------------------------------
// 0x19 FileCompleteFrame — sender signals all chunks were sent; receiver finalizes
// ---------------------------------------------------------------------------

class FileCompleteFrame extends ProtocolFrame {
  @override
  final int type = kTypeFileComplete;

  final String fileId;

  /// SHA-256 of the complete file for final integrity check.
  final String sha256;

  FileCompleteFrame({required this.fileId, required this.sha256});

  factory FileCompleteFrame._fromMap(Map<Object?, Object?> map) =>
      FileCompleteFrame(
        fileId: _requireString(map, 1, 'fileId'),
        sha256: _requireString(map, 2, 'sha256'),
      );

  @override
  Uint8List encode() =>
      _cborEncodeMap({0: kTypeFileComplete, 1: fileId, 2: sha256});
}

// ---------------------------------------------------------------------------
// 0x1A FileCancelFrame — either peer aborts an in-progress transfer
// ---------------------------------------------------------------------------

class FileCancelFrame extends ProtocolFrame {
  @override
  final int type = kTypeFileCancel;

  final String fileId;
  final String reason;

  FileCancelFrame({required this.fileId, required this.reason});

  factory FileCancelFrame._fromMap(Map<Object?, Object?> map) =>
      FileCancelFrame(
        fileId: _requireString(map, 1, 'fileId'),
        reason: _requireString(map, 2, 'reason'),
      );

  @override
  Uint8List encode() =>
      _cborEncodeMap({0: kTypeFileCancel, 1: fileId, 2: reason});
}

// ---------------------------------------------------------------------------
// 0x1B EphemeralMediaFrame — one chunk of a RAM-only private media transfer.
// The receiver accumulates all chunks in RAM; nothing is ever written to disk.
// ---------------------------------------------------------------------------

class EphemeralMediaFrame extends ProtocolFrame {
  @override
  final int type = kTypeEphemeralMedia;

  final String mediaId;
  final String mimeType;
  final int totalSize;
  final int chunkIndex;
  final int chunkCount;
  final Uint8List chunkData;

  EphemeralMediaFrame({
    required this.mediaId,
    required this.mimeType,
    required this.totalSize,
    required this.chunkIndex,
    required this.chunkCount,
    required this.chunkData,
  });

  factory EphemeralMediaFrame._fromMap(Map<Object?, Object?> map) =>
      EphemeralMediaFrame(
        mediaId: _requireString(map, 1, 'mediaId'),
        mimeType: _requireString(map, 2, 'mimeType'),
        totalSize: _requireInt(map, 3, 'totalSize'),
        chunkIndex: _requireInt(map, 4, 'chunkIndex'),
        chunkCount: _requireInt(map, 5, 'chunkCount'),
        chunkData: _requireBytes(map, 6, 'chunkData'),
      );

  @override
  Uint8List encode() => _cborEncodeMap({
    0: kTypeEphemeralMedia,
    1: mediaId,
    2: mimeType,
    3: totalSize,
    4: chunkIndex,
    5: chunkCount,
    6: chunkData,
  });
}
