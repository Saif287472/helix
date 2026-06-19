class RemoteAttachmentManifest {
  const RemoteAttachmentManifest({
    required this.fileId,
    required this.fileSize,
    required this.fileHash,
    required this.mimeType,
  });

  final String fileId;
  final int fileSize;
  final String fileHash;
  final String mimeType;

  Map<String, dynamic> toJson() => {
    'file_id': fileId,
    'file_size': fileSize,
    'file_hash': fileHash,
    'mime_type': mimeType,
  };

  factory RemoteAttachmentManifest.fromJson(Map<String, dynamic> json) {
    return RemoteAttachmentManifest(
      fileId: json['file_id'] as String,
      fileSize: json['file_size'] as int,
      fileHash: json['file_hash'] as String,
      mimeType: json['mime_type'] as String,
    );
  }
}
