class FileTransferSession {
  const FileTransferSession({
    required this.fileId,
    required this.fileName,
    required this.mimeType,
    required this.totalSize,
    required this.chunkCount,
    this.resumeStartChunk = 0,
    this.usingProbeProtocol = false,
    required this.receivedChunks,
  });

  final String fileId;
  final String fileName;
  final String mimeType;
  final int totalSize;
  final int chunkCount;
  final int resumeStartChunk;
  final bool usingProbeProtocol;
  final Set<int> receivedChunks;

  int get receivedThisSession => receivedChunks.length;
  bool get isComplete => resumeStartChunk + receivedChunks.length == chunkCount;
  double get progress => chunkCount == 0
      ? 0.0
      : (resumeStartChunk + receivedChunks.length) / chunkCount;
}
